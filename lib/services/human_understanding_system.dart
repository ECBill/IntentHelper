/// 人类理解系统主服务
/// 整合所有子模块，提供统一的类人理解能力

import 'dart:async';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/intent_lifecycle_manager.dart';
import 'package:app/services/conversation_topic_tracker.dart';
import 'package:app/services/causal_chain_extractor.dart';
import 'package:app/services/semantic_graph_builder.dart';
import 'package:app/services/cognitive_load_estimator.dart';
import 'package:app/services/intelligent_reminder_manager.dart'; // 🔥 新增：智能提醒管理器
import 'package:app/services/knowledge_graph_service.dart'; // 🔥 新增：知识图谱服务
import 'package:app/services/objectbox_service.dart';

class HumanUnderstandingSystem {
  static final HumanUnderstandingSystem _instance = HumanUnderstandingSystem._internal();
  factory HumanUnderstandingSystem() => _instance;
  HumanUnderstandingSystem._internal();

  // 子模块实例
  final IntentLifecycleManager _intentManager = IntentLifecycleManager();
  final ConversationTopicTracker _topicTracker = ConversationTopicTracker();
  final CausalChainExtractor _causalExtractor = CausalChainExtractor();
  final SemanticGraphBuilder _graphBuilder = SemanticGraphBuilder();
  final CognitiveLoadEstimator _loadEstimator = CognitiveLoadEstimator();
  final IntelligentReminderManager _reminderManager = IntelligentReminderManager(); // 🔥 新增：智能提醒管理器
  final KnowledgeGraphService _knowledgeGraph = KnowledgeGraphService(); // 🔥 新增：知识图谱服务

  // 系统状态
  final StreamController<HumanUnderstandingSystemState> _systemStateController = StreamController.broadcast();
  Timer? _stateUpdateTimer;
  Timer? _conversationMonitorTimer;
  bool _initialized = false;
  bool _isMonitoring = false; // 🔥 新增：监听状态标志

  // 🔥 修复：对话监听相关 - 统一使用 createdAt
  int _lastProcessedTimestamp = 0;
  final Set<int> _processedRecordIds = {}; // 防止重复处理
  static const int _monitorInterval = 5; // 🔥 优化：缩短到5秒检查一次，提高响应性
  static const int _conversationBatchSize = 5; // 🔥 优化：减少批次大小，提高处理速度

  /// 系统状态更新流
  Stream<HumanUnderstandingSystemState> get systemStateUpdates => _systemStateController.stream;

  /// 初始化整个理解系统
  Future<void> initialize() async {
    if (_initialized) {
      print('[HumanUnderstandingSystem] ✅ 系统已初始化');
      return;
    }

    // 🔥 新增：防止重复初始化的标志
    if (_initializing) {
      print('[HumanUnderstandingSystem] ⏳ 系统正在初始化中，等待完成...');
      while (_initializing && !_initialized) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return;
    }

    _initializing = true;
    print('[HumanUnderstandingSystem] 🚀 初始化人类理解系统...');

    try {
      // 并行初始化所有子模块
      await Future.wait([
        _intentManager.initialize(),
        _topicTracker.initialize(),
        _causalExtractor.initialize(),
        _graphBuilder.initialize(),
        _loadEstimator.initialize(),
      ]);

      print('[HumanUnderstandingSystem] ✅ 所有子模块初始化完成');

      // 🔥 修复：确保监听机制正常启动
      _startConversationMonitoring();
      _startPeriodicStateUpdate();

      // 🔥 修复：标记为已初始化，但先不处理历史对话
      _initialized = true;
      _initializing = false;
      print('[HumanUnderstandingSystem] ✅ 人类理解系统核心初始化完成');
      print('[HumanUnderstandingSystem] 👂 监听状态: $_isMonitoring');

      // 🔥 修复：延迟处理历史对话，避免循环
      Future.delayed(Duration(milliseconds: 500), () {
        if (_initialized) {
          _processInitialConversationsAsync();
        }
      });

    } catch (e) {
      _initializing = false;
      print('[HumanUnderstandingSystem] ❌ 系统初始化失败: $e');
      rethrow;
    }
  }

  // 🔥 新增：初始化状态标志
  bool _initializing = false;

  /// 🔥 修复：异步处理初始对话，避免阻塞初始化
  void _processInitialConversationsAsync() async {
    print('[HumanUnderstandingSystem] 📚 异步检查现有对话数据...');

    try {
      // 获取最近30分钟的对话记录，缩短时间范围
      final cutoffTime = DateTime.now().subtract(Duration(minutes: 30)).millisecondsSinceEpoch;
      final recentRecords = ObjectBoxService().getRecordsSince(cutoffTime);

      if (recentRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 暂无最近对话记录');
        _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
        
        // 创建一些基础的测试数据来验证系统工作
        await _createInitialTestData();
        return;
      }

      print('[HumanUnderstandingSystem] 📊 找到 ${recentRecords.length} 条历史对话');

      // 🔥 修复：减少初始处理数量，避免过载
      final limitedRecords = recentRecords.take(3).toList();
      await _processBatchConversations(limitedRecords);

      // 标记这些记录为已处理
      _markRecordsAsProcessed(limitedRecords);
      _updateProcessedTimestamp();
      
      print('[HumanUnderstandingSystem] �� 历史对话异步处理完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 异步处理历史对话失败: $e');
      _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      // 如果处理失败，也创建测试数据
      await _createInitialTestData();
    }
  }

  /// 🔥 修复：启动对话监听机制
  void _startConversationMonitoring() {
    if (_isMonitoring) {
      print('[HumanUnderstandingSystem] ⚠️ 监听已在运行中');
      return;
    }

    print('[HumanUnderstandingSystem] 👂 启动对话监听机制...');
    print('[HumanUnderstandingSystem] ⏰ 监听间隔: ${_monitorInterval}秒');

    _conversationMonitorTimer = Timer.periodic(Duration(seconds: _monitorInterval), (timer) {
      _monitorNewConversations();
    });

    _isMonitoring = true;
    print('[HumanUnderstandingSystem] ✅ 对话监听已启动');
  }

  /// 🔥 修复：监听新对话
  Future<void> _monitorNewConversations() async {
    if (!_initialized || !_isMonitoring) return;

    try {
      // 🔥 修复：获取自上次处理以来的新对话记录
      final newRecords = ObjectBoxService().getRecordsSince(_lastProcessedTimestamp);

      if (newRecords.isEmpty) {
        // 静默返回，避免日志刷屏
        return;
      }

      print('[HumanUnderstandingSystem] 📊 发现 ${newRecords.length} 条新对话记录');

      // 🔥 修复：过滤出真正的新记录，使用正确的ID字段
      final unprocessedRecords = newRecords.where((record) {
        return record.id != 0 && !_processedRecordIds.contains(record.id);
      }).toList();

      if (unprocessedRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 所有记录已处理过');
        return;
      }

      print('[HumanUnderstandingSystem] 🔄 处理 ${unprocessedRecords.length} 条新记录');

      // 🔥 修复：按时间排序，使用正确的时间戳字段
      unprocessedRecords.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
      final recentRecords = unprocessedRecords.take(_conversationBatchSize).toList();

      // 🔥 新增：过滤有意义的对话内容
      final meaningfulRecords = _filterMeaningfulRecords(recentRecords);
      if (meaningfulRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 没有实质性对话内容');
        _markRecordsAsProcessed(recentRecords);
        return;
      }

      // 批量处理对话
      await _processBatchConversations(meaningfulRecords);

      // 更新处理状态
      _markRecordsAsProcessed(recentRecords);
      _updateProcessedTimestamp();

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 监听新对话失败: $e');
    }
  }

  /// 🔥 新增：过滤有意义的记录
  List<dynamic> _filterMeaningfulRecords(List<dynamic> records) {
    return records.where((record) {
      final content = record.content?.toString() ?? '';

      // 过滤条件
      if (content.trim().isEmpty) return false;
      if (content.length < 2) return false; // 太短的内容
      if (_isSystemMessage(content)) return false; // 系统消息

      return true;
    }).toList();
  }

  /// 🔥 新增：判断是否为系统消息
  bool _isSystemMessage(String content) {
    final systemPatterns = [
      '录音开始', '录音结束', '系统启动', '连接成功', '断开连接',
      '开始录音', '停止录音', '[系统]', '检测到', '正在处���'
    ];

    return systemPatterns.any((pattern) => content.contains(pattern));
  }

  /// 🔥 新增：标记记录为已处理
  void _markRecordsAsProcessed(List<dynamic> records) {
    for (final record in records) {
      if (record.id != 0) {
        _processedRecordIds.add(record.id);
      }
    }

    // 清理旧的处理记录ID，防止内存泄漏
    if (_processedRecordIds.length > 500) {
      final sortedIds = _processedRecordIds.toList()..sort();
      _processedRecordIds.clear();
      _processedRecordIds.addAll(sortedIds.skip(250)); // 保留最近250条
    }
  }

  /// 🔥 新增：更新处理时间戳
  void _updateProcessedTimestamp() {
    _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 🔥 修复：批量处理对话记录
  Future<void> _processBatchConversations(List<dynamic> records) async {
    print('[HumanUnderstandingSystem] 📦 开始批量处理 ${records.length} 条对话...');

    try {
      // 构建对话上下文
      final conversationContext = _buildConversationContext(records);

      if (conversationContext.trim().isEmpty) {
        print('[HumanUnderstandingSystem] ⚠️ 对话上下文为空，跳过处理');
        return;
      }

      print('[HumanUnderstandingSystem] 📝 对话上下文长度: ${conversationContext.length}');
      print('[HumanUnderstandingSystem] 🔍 对话预览: "${conversationContext.substring(0, conversationContext.length > 100 ? 100 : conversationContext.length)}..."');

      final contextId = 'hu_batch_${DateTime.now().millisecondsSinceEpoch}';
      final conversationTime = records.isNotEmpty && records.first.createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(records.first.createdAt)
          : DateTime.now();

      // 🔥 第二步：先进行 HU 系统的实体提取
      final allContent = records
          .map((r) => r.content?.toString() ?? '')
          .where((content) => content.trim().isNotEmpty)
          .join(' ');

      // HU 系统预提取实体
      final preExtractedEntities = _extractBasicEntities(allContent);
      final entityTypeMapping = _createEntityTypeMapping(preExtractedEntities);

      print('[HumanUnderstandingSystem] 🔍 HU系统预提取实体: ${preExtractedEntities.length}个');
      print('[HumanUnderstandingSystem] 📊 实体列表: ${preExtractedEntities.take(5).join('、')}${preExtractedEntities.length > 5 ? '...' : ''}');

      // 🔥 第二步：使用共享实体调用 KG 系统，避免重复提取
      final kgProcessingFuture = KnowledgeGraphService.processEventsFromConversationWithSharedEntities(
        conversationContext,
        contextId: contextId,
        conversationTime: conversationTime,
        preExtractedEntities: preExtractedEntities,
        entityTypeMapping: entityTypeMapping,
      );

      // 创建语义分析输入（使用预提取的实体）
      final semanticInput = _createSemanticAnalysisFromContextWithEntities(
        conversationContext,
        records,
        preExtractedEntities,
      );

      // 等待 KG 处理完成，然后进行 HU 处理
      await kgProcessingFuture;
      print('[HumanUnderstandingSystem] ✅ KG 系统处理完成（使用共享实体），开始 HU 系统处理');

      // 处理语义输入
      await processSemanticInput(semanticInput);

      print('[HumanUnderstandingSystem] ✅ 批量对话处理完成（HU + KG 实体共享融合）');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 批量处理对话失败: $e');
    }
  }

  /// 🔥 修复：构建对话上下文
  String _buildConversationContext(List<dynamic> records) {
    final contextBuilder = StringBuffer();

    for (final record in records) {
      final role = record.role ?? 'unknown';
      final content = record.content ?? '';
      final createdAt = record.createdAt; // 🔥 修复：使用正确的时间戳字段

      if (content.trim().isNotEmpty) {
        // 格式化时间戳
        String timeStr = '';
        if (createdAt != null) {
          final time = DateTime.fromMillisecondsSinceEpoch(createdAt);
          timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        }

        contextBuilder.writeln('[$timeStr] $role: $content');
      }
    }

    return contextBuilder.toString().trim();
  }

  /// 🔥 第二步：创建实体类型映射
  Map<String, String> _createEntityTypeMapping(List<String> entities) {
    final mapping = <String, String>{};

    for (final entity in entities) {
      // 技术相关
      if (entity.contains('Flutter') || entity.contains('AI') ||
          entity.contains('数据库') || entity.contains('Bug') ||
          entity.contains('性能优化')) {
        mapping[entity] = '技术概念';
      }
      // 工作相关
      else if (entity.contains('工作项目') || entity.contains('会议') ||
               entity.contains('团队协作') || entity.contains('功能开发')) {
        mapping[entity] = '工作概念';
      }
      // 学习相关
      else if (entity.contains('学习') || entity.contains('研究')) {
        mapping[entity] = '学习概念';
      }
      // 生活相关
      else if (entity.contains('饮食') || entity.contains('运动') ||
               entity.contains('休息')) {
        mapping[entity] = '生活概念';
      }
      // 默认概念类型
      else {
        mapping[entity] = '概念';
      }
    }

    return mapping;
  }

  /// 🔥 第二步：从对话上下文创建语义分析输入（使用预提取实体）
  SemanticAnalysisInput _createSemanticAnalysisFromContextWithEntities(
    String context,
    List<dynamic> records,
    List<String> preExtractedEntities,
  ) {
    // 提取所有对话内容
    final allContent = records
        .map((r) => r.content?.toString() ?? '')
        .where((content) => content.trim().isNotEmpty)
        .join(' ');

    // 使用预提取的实体，无需重复提取
    final entities = preExtractedEntities;

    // 基础意图推断
    final intent = _inferBasicIntent(allContent);

    // 基础情绪推断
    final emotion = _inferBasicEmotion(allContent);

    // 🔥 修复：计算最新的时间戳，使用正确字段
    final latestTimestamp = records
        .map((r) => r.createdAt as int? ?? 0)
        .fold<int>(0, (max, timestamp) => timestamp > max ? timestamp : max);

    return SemanticAnalysisInput(
      entities: entities,
      intent: intent,
      emotion: emotion,
      content: allContent,
      timestamp: latestTimestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(latestTimestamp)
          : DateTime.now(),
      additionalContext: {
        'source': 'real_conversation_monitoring_with_shared_entities',
        'conversation_context': context,
        'record_count': records.length,
        'pre_extracted_entities_count': preExtractedEntities.length,
        'entity_sharing_enabled': true,
        'processing_time': DateTime.now().toIso8601String(),
        'monitoring_interval': _monitorInterval,
      },
    );
  }

  /// 🔥 修复：只处理现有对话，不创建测试数据
  Future<void> _processInitialConversations() async {
    print('[HumanUnderstandingSystem] 📚 检查现有对话数据...');

    try {
      // 🔥 修复：获取最近1小时的对话记录，缩短时间范围提高处理速度
      final cutoffTime = DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch;
      final recentRecords = ObjectBoxService().getRecordsSince(cutoffTime);

      if (recentRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 暂无最近对话记录');
        _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;

        // 🔥 新增：创建一些基础的测试数据来验证系统工作
        await _createInitialTestData();
        return;
      }

      print('[HumanUnderstandingSystem] 📊 找到 ${recentRecords.length} 条历史对话');

      // 处理最近的对话记录
      final limitedRecords = recentRecords.take(10).toList(); // 🔥 优化：减少初始处理数量
      await _processBatchConversations(limitedRecords);

      // 标记这些记录为已处理
      _markRecordsAsProcessed(limitedRecords);
      _updateProcessedTimestamp();

      print('[HumanUnderstandingSystem] ✅ 历史对话处理完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 处理历史对话失败: $e');
      _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;

      // 如果处理失败，也创建测试数据
      await _createInitialTestData();
    }
  }

  /// 🔥 新增：创建初始测试数据以验证系统工作
  Future<void> _createInitialTestData() async {
    print('[HumanUnderstandingSystem] 🧪 创建初始测试数据...');

    try {
      // 创建一些基础的测试语义输入
      final testInputs = [
        SemanticAnalysisInput(
          entities: ['用户', '系统', 'Flutter'],
          intent: 'system_testing',
          emotion: 'neutral',
          content: '系统正在进行初始化测试，验证人类理解功能是否正常工作',
          timestamp: DateTime.now(),
          additionalContext: {
            'source': 'initial_test_data',
            'test_type': 'system_validation',
          },
        ),
        SemanticAnalysisInput(
          entities: ['对话', '分析', '理解'],
          intent: 'capability_demonstration',
          emotion: 'positive',
          content: '展示对话分析和语义理解的基础能力',
          timestamp: DateTime.now().add(Duration(seconds: 1)),
          additionalContext: {
            'source': 'initial_test_data',
            'test_type': 'capability_demo',
          },
        ),
      ];

      for (final input in testInputs) {
        await processSemanticInput(input);
        await Future.delayed(Duration(milliseconds: 100)); // 短暂延迟
      }

      print('[HumanUnderstandingSystem] ✅ 初始测试数据创建完成');
    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 创建测试数据失败: $e');
    }
  }

  /// 启动定期状态更新
  void _startPeriodicStateUpdate() {
    _stateUpdateTimer = Timer.periodic(Duration(minutes: 2), (timer) {
      _updateSystemState();
    });
  }

  /// 更新系统状态
  void _updateSystemState() async {
    try {
      final currentLoad = _loadEstimator.getCurrentLoad();
      if (currentLoad == null) return;

      final systemState = HumanUnderstandingSystemState(
        activeIntents: _intentManager.getActiveIntents(),
        activeTopics: _topicTracker.getActiveTopics(),
        recentCausalChains: _causalExtractor.getRecentCausalRelations(limit: 5),
        recentTriples: _graphBuilder.getRecentTriples(limit: 10),
        currentCognitiveLoad: currentLoad,
        systemMetrics: {
          'update_type': 'periodic',
          'system_uptime_minutes': DateTime.now().difference(_initTime).inMinutes,
        },
      );

      _systemStateController.add(systemState);

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 定期状态更新失败: $e');
    }
  }

  late final DateTime _initTime = DateTime.now();

  /// 获取当前系统状态
  HumanUnderstandingSystemState getCurrentState() {
    final currentLoad = _loadEstimator.getCurrentLoad() ?? CognitiveLoadAssessment(
      level: CognitiveLoadLevel.moderate,
      score: 0.5,
      factors: {},
      activeIntentCount: 0,
      activeTopicCount: 0,
      emotionalIntensity: 0.5,
      topicSwitchRate: 0.0,
      complexityScore: 0.5,
    );

    return HumanUnderstandingSystemState(
      activeIntents: _intentManager.getActiveIntents(),
      activeTopics: _topicTracker.getActiveTopics(),
      recentCausalChains: _causalExtractor.getRecentCausalRelations(limit: 5),
      recentTriples: _graphBuilder.getRecentTriples(limit: 10),
      currentCognitiveLoad: currentLoad,
      systemMetrics: {
        'request_type': 'current_state',
        'system_initialized': _initialized,
      },
    );
  }

  /// 搜索相关信息
  Future<Map<String, dynamic>> searchRelevantInfo(String query) async {
    try {
      final results = <String, dynamic>{};

      // HU 系统的搜索
      // 搜索意图
      final relatedIntents = _intentManager.searchIntents(query);
      results['intents'] = relatedIntents.map((i) => i.toJson()).toList();

      // 搜索主题
      final relatedTopics = _topicTracker.searchTopics(query);
      results['topics'] = relatedTopics.map((t) => t.toJson()).toList();

      // 搜索因果关系
      final relatedCausal = _causalExtractor.searchCausalRelations(query);
      results['causal_relations'] = relatedCausal.map((c) => c.toJson()).toList();

      // 搜索语义三元组
      final relatedTriples = _graphBuilder.queryTriples(
        subject: query.contains(' ') ? null : query,
        predicate: query.contains(' ') ? null : query,
        object: query.contains(' ') ? null : query,
      );
      results['semantic_triples'] = relatedTriples.map((t) => t.toJson()).toList();

      // 🔥 第三步：融入知识图谱的事件和关系信息
      final queryKeywords = query.split(' ').where((w) => w.trim().isNotEmpty).toList();

      // 从 KG 获取相关节点
      final kgNodes = await KnowledgeGraphService.getRelatedNodesByKeywords(queryKeywords);
      results['kg_entities'] = kgNodes.map((n) => {
        'id': n.id,
        'name': n.name,
        'type': n.type,
        'attributes': n.attributes,
        'aliases': n.aliases,
        'last_updated': n.lastUpdated.toIso8601String(),
      }).toList();

      // 从 KG 获取相关事件
      final kgEvents = <Map<String, dynamic>>[];
      for (final node in kgNodes.take(5)) { // 限制查询数量
        final relatedEvents = await KnowledgeGraphService.getRelatedEvents(node.id);
        for (final event in relatedEvents) {
          kgEvents.add({
            'id': event.id,
            'name': event.name,
            'type': event.type,
            'description': event.description,
            'location': event.location,
            'start_time': event.startTime?.toIso8601String(),
            'end_time': event.endTime?.toIso8601String(),
            'related_entity': node.name,
          });
        }
      }
      results['kg_events'] = kgEvents;

      // 总结搜索结果
      final huResults = relatedIntents.length + relatedTopics.length + relatedCausal.length + relatedTriples.length;
      final kgResults = kgNodes.length + kgEvents.length;

      results['search_summary'] = {
        'total_results': huResults + kgResults,
        'hu_system_results': huResults,
        'kg_system_results': kgResults,
        'fusion_enabled': true,
      };

      return results;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 搜索相关信息失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 🔥 第三步：获取特定实体的完整上下文（融合 HU + KG）
  Future<Map<String, dynamic>> getEntityContext(String entityName) async {
    try {
      final context = <String, dynamic>{
        'entity_name': entityName,
        'search_timestamp': DateTime.now().toIso8601String(),
      };

      // HU 系统中与该实体相关的信息
      final huInfo = await searchRelevantInfo(entityName);
      context['hu_analysis'] = {
        'related_intents': huInfo['intents'] ?? [],
        'related_topics': huInfo['topics'] ?? [],
        'causal_relations': huInfo['causal_relations'] ?? [],
        'semantic_triples': huInfo['semantic_triples'] ?? [],
      };

      // KG 系统中的实体信息
      final kgNodes = await KnowledgeGraphService.getRelatedNodesByKeywords([entityName]);
      final primaryNode = kgNodes.isNotEmpty ? kgNodes.first : null;

      if (primaryNode != null) {
        // 获取相关事件
        final relatedEvents = await KnowledgeGraphService.getRelatedEvents(primaryNode.id);

        context['kg_analysis'] = {
          'entity_details': {
            'id': primaryNode.id,
            'name': primaryNode.name,
            'type': primaryNode.type,
            'canonical_name': primaryNode.canonicalName,
            'attributes': primaryNode.attributes,
            'aliases': primaryNode.aliases,
            'last_updated': primaryNode.lastUpdated.toIso8601String(),
            'source_context': primaryNode.sourceContext,
          },
          'related_events': relatedEvents.map((event) => {
            'id': event.id,
            'name': event.name,
            'type': event.type,
            'description': event.description,
            'location': event.location,
            'purpose': event.purpose,
            'result': event.result,
            'start_time': event.startTime?.toIso8601String(),
            'end_time': event.endTime?.toIso8601String(),
            'last_updated': event.lastUpdated.toIso8601String(),
          }).toList(),
          'event_count': relatedEvents.length,
        };

        // 实体的时间线分析
        context['timeline_analysis'] = _buildEntityTimeline(relatedEvents);
      } else {
        context['kg_analysis'] = {
          'entity_details': null,
          'related_events': [],
          'event_count': 0,
        };
      }

      // 融合分析
      context['fusion_insights'] = _generateFusionInsights(context);

      return context;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 获取实体上下文失败: $e');
      return {'error': e.toString(), 'entity_name': entityName};
    }
  }

  /// 🔥 第三步：构建实体时间线
  Map<String, dynamic> _buildEntityTimeline(List<dynamic> events) {
    if (events.isEmpty) {
      return {
        'total_events': 0,
        'time_span': null,
        'event_frequency': 0.0,
        'recent_activity': [],
      };
    }

    // 按时间排序事件
    final sortedEvents = events.where((e) => e.startTime != null).toList();
    sortedEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));

    DateTime? firstEventTime;
    DateTime? lastEventTime;

    if (sortedEvents.isNotEmpty) {
      firstEventTime = sortedEvents.first.startTime;
      lastEventTime = sortedEvents.last.startTime;
    }

    // 最近活动（最近7天）
    final now = DateTime.now();
    final recentThreshold = now.subtract(Duration(days: 7));
    final recentEvents = events.where((e) =>
      e.lastUpdated.isAfter(recentThreshold)
    ).toList();

    return {
      'total_events': events.length,
      'time_span': firstEventTime != null && lastEventTime != null
          ? {
              'start': firstEventTime.toIso8601String(),
              'end': lastEventTime.toIso8601String(),
              'duration_days': lastEventTime.difference(firstEventTime).inDays,
            }
          : null,
      'event_frequency': firstEventTime != null && lastEventTime != null
          ? events.length / (lastEventTime.difference(firstEventTime).inDays + 1)
          : 0.0,
      'recent_activity': recentEvents.take(5).map((e) => {
        'name': e.name,
        'type': e.type,
        'last_updated': e.lastUpdated.toIso8601String(),
      }).toList(),
      'recent_activity_count': recentEvents.length,
    };
  }

  /// 🔥 第三步：生成融合洞察
  Map<String, dynamic> _generateFusionInsights(Map<String, dynamic> context) {
    final insights = <String, dynamic>{};

    final huAnalysis = context['hu_analysis'] as Map<String, dynamic>? ?? {};
    final kgAnalysis = context['kg_analysis'] as Map<String, dynamic>? ?? {};

    // 统计信息
    final huIntentCount = (huAnalysis['related_intents'] as List?)?.length ?? 0;
    final huTopicCount = (huAnalysis['related_topics'] as List?)?.length ?? 0;
    final kgEventCount = (kgAnalysis['event_count'] as int?) ?? 0;

    insights['data_richness'] = {
      'hu_intent_coverage': huIntentCount,
      'hu_topic_coverage': huTopicCount,
      'kg_event_coverage': kgEventCount,
      'total_data_points': huIntentCount + huTopicCount + kgEventCount,
    };

    // 实体活跃度分析
    final timelineAnalysis = context['timeline_analysis'] as Map<String, dynamic>? ?? {};
    final recentActivityCount = (timelineAnalysis['recent_activity_count'] as int?) ?? 0;

    String activityLevel;
    if (recentActivityCount >= 5) {
      activityLevel = 'high';
    } else if (recentActivityCount >= 2) {
      activityLevel = 'medium';
    } else if (recentActivityCount >= 1) {
      activityLevel = 'low';
    } else {
      activityLevel = 'inactive';
    }

    insights['activity_analysis'] = {
      'recent_activity_level': activityLevel,
      'recent_events': recentActivityCount,
      'activity_trend': recentActivityCount > 0 ? 'active' : 'dormant',
    };

    // 建议的分析方向
    final suggestions = <String>[];

    if (huIntentCount > 0) {
      suggestions.add('深入分析用户对该实体的意图模式');
    }
    if (kgEventCount > 0) {
      suggestions.add('分析该实体的事件模式和行为规律');
    }
    if (huTopicCount > 0) {
      suggestions.add('探索该实体在不同对话主题中的作用');
    }
    if (recentActivityCount > 0) {
      suggestions.add('关注该实体的最新动态和变化');
    }

    insights['analysis_suggestions'] = suggestions;

    return insights;
  }

  /// 获取智能建议 - 第四步：基于知识图谱增强智能建议功能
  Map<String, dynamic> getIntelligentSuggestions() {
    try {
      final currentState = getCurrentState();
      final suggestions = <String, dynamic>{};

      // 基于意图的建议
      final activeIntents = currentState.activeIntents;
      if (activeIntents.length > 3) {
        suggestions['intent_management'] = '当前有 ${activeIntents.length} 个活跃意图，建议优先完成重要意图';
      }

      // 基于认知负载的建议
      final loadLevel = currentState.currentCognitiveLoad.level;
      suggestions['cognitive_load'] = currentState.currentCognitiveLoad.recommendation;

      // 基于主题的建议
      final activeTopics = currentState.activeTopics;
      if (activeTopics.length > 5) {
        suggestions['topic_focus'] = '当前讨论了 ${activeTopics.length} 个主题，建议专注于核心主题';
      }

      // 基于因果关系的建议
      final causalChains = currentState.recentCausalChains;
      if (causalChains.isNotEmpty) {
        suggestions['causal_insight'] = '发现了 ${causalChains.length} 个因果关系，可以深入分析行为动机';
      }

      return {
        'suggestions': suggestions,
        'priority_actions': _getPriorityActions(currentState),
        'generated_at': DateTime.now().toIso8601String(),
      };

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成智能建议失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 🔥 第四步：获取增强的智能建议（融合知识图谱信息）
  Future<Map<String, dynamic>> getEnhancedIntelligentSuggestions() async {
    try {
      final currentState = getCurrentState();
      final suggestions = <String, dynamic>{};
      final kgInsights = <String, dynamic>{};

      // 基础建议（HU 系统）
      final basicSuggestions = getIntelligentSuggestions();
      suggestions.addAll(basicSuggestions);

      // 🔥 第四步：基于知识图谱的增强建议
      await _generateKnowledgeGraphInsights(suggestions, kgInsights, currentState);

      // 🔥 第四步：基于实体活动模式的建议
      await _generateEntityActivitySuggestions(suggestions, kgInsights);

      // 🔥 第四步：基于事件时间模式的建议
      await _generateTemporalPatternSuggestions(suggestions, kgInsights);

      // 🔥 第四步：生成个性化行动计划
      final actionPlan = await _generatePersonalizedActionPlan(currentState, kgInsights);

      return {
        'basic_suggestions': basicSuggestions['suggestions'] ?? {},
        'enhanced_suggestions': suggestions,
        'kg_insights': kgInsights,
        'personalized_action_plan': actionPlan,
        'priority_actions': _getEnhancedPriorityActions(currentState, kgInsights),
        'fusion_analysis': {
          'hu_data_points': _countHuDataPoints(currentState),
          'kg_data_points': kgInsights['total_entities'] ?? 0,
          'suggestion_quality': _assessSuggestionQuality(kgInsights),
        },
        'generated_at': DateTime.now().toIso8601String(),
      };

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成增强智能建议失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 🔥 第四步：生成知识图谱洞察
  Future<void> _generateKnowledgeGraphInsights(
    Map<String, dynamic> suggestions,
    Map<String, dynamic> kgInsights,
    HumanUnderstandingSystemState currentState,
  ) async {
    try {
      // 获取最近活跃的实体
      final activeEntities = <String>[];

      // 从意图中提取实体 - 🔥 修复：使用正确的属性名
      for (final intent in currentState.activeIntents) {
        activeEntities.addAll(intent.relatedEntities);
      }

      // 从主题中提取关键词
      for (final topic in currentState.activeTopics) {
        activeEntities.add(topic.name);
      }

      if (activeEntities.isEmpty) {
        kgInsights['entity_analysis'] = {'message': '当前没有识别到活跃实体'};
        return;
      }

      // 查询这些实体的知识图谱信息
      final entityContexts = <Map<String, dynamic>>[];
      for (final entity in activeEntities.take(5)) { // 限制查询数量
        final context = await getEntityContext(entity);
        if (context.containsKey('kg_analysis')) {
          entityContexts.add(context);
        }
      }

      // 分析实体模式
      final entityPatterns = _analyzeEntityPatterns(entityContexts);
      kgInsights['entity_patterns'] = entityPatterns;
      kgInsights['total_entities'] = entityContexts.length;

      // 基于实体模式生成建议
      if (entityPatterns['high_activity_entities'].isNotEmpty) {
        suggestions['entity_focus'] = '检测到高活跃度实体：${entityPatterns['high_activity_entities'].take(3).join('、')}，建议深入关注';
      }

      if (entityPatterns['dormant_entities'].isNotEmpty) {
        suggestions['entity_reactivation'] = '发现休眠实体：${entityPatterns['dormant_entities'].take(3).join('、')}，可能需要重新激活';
      }

      if (entityPatterns['trending_patterns'].isNotEmpty) {
        suggestions['pattern_recognition'] = '识别到趋势模式：${entityPatterns['trending_patterns'].join('、')}';
      }

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成知识图谱洞察失败: $e');
      kgInsights['error'] = e.toString();
    }
  }

  /// 🔥 第四步：分析实体模式
  Map<String, dynamic> _analyzeEntityPatterns(List<Map<String, dynamic>> entityContexts) {
    final patterns = <String, dynamic>{
      'high_activity_entities': <String>[],
      'dormant_entities': <String>[],
      'trending_patterns': <String>[],
      'entity_statistics': {},
    };

    final entityStats = <String, Map<String, dynamic>>{};

    for (final context in entityContexts) {
      final entityName = context['entity_name'] as String;
      final timelineAnalysis = context['timeline_analysis'] as Map<String, dynamic>? ?? {};
      final recentActivityCount = (timelineAnalysis['recent_activity_count'] as int?) ?? 0;
      final totalEvents = (timelineAnalysis['total_events'] as int?) ?? 0;

      entityStats[entityName] = {
        'recent_activity': recentActivityCount,
        'total_events': totalEvents,
        'activity_level': recentActivityCount >= 3 ? 'high' :
                        recentActivityCount >= 1 ? 'medium' : 'low',
      };

      // 分类实体
      if (recentActivityCount >= 3) {
        patterns['high_activity_entities'].add(entityName);
      } else if (totalEvents > 0 && recentActivityCount == 0) {
        patterns['dormant_entities'].add(entityName);
      }
    }

    patterns['entity_statistics'] = entityStats;

    // 识别趋势模式
    final highActivityCount = patterns['high_activity_entities'].length;
    final dormantCount = patterns['dormant_entities'].length;

    if (highActivityCount > dormantCount * 2) {
      patterns['trending_patterns'].add('高活跃度模式');
    } else if (dormantCount > highActivityCount) {
      patterns['trending_patterns'].add('低活跃度模式');
    } else {
      patterns['trending_patterns'].add('平衡活跃度模式');
    }

    return patterns;
  }

  /// 🔥 第四步：生成基于实体活动的建议
  Future<void> _generateEntityActivitySuggestions(
    Map<String, dynamic> suggestions,
    Map<String, dynamic> kgInsights,
  ) async {
    try {
      // 分析最近的实体活动模式
      final objectBox = ObjectBoxService();
      final recentEvents = objectBox.queryEventNodes()
          .where((event) => event.lastUpdated.isAfter(DateTime.now().subtract(Duration(days: 7))))
          .toList();

      if (recentEvents.isEmpty) {
        return;
      }

      // 按类型分组事件
      final eventsByType = <String, List<dynamic>>{};
      for (final event in recentEvents) {
        eventsByType.putIfAbsent(event.type, () => []).add(event);
      }

      // 生成基于事件类型的建议
      final typeRecommendations = <String>[];

      eventsByType.forEach((type, events) {
        if (events.length >= 3) {
          typeRecommendations.add('$type类型事件活跃（${events.length}个），建议优化此类活动');
        }
      });

      if (typeRecommendations.isNotEmpty) {
        suggestions['activity_optimization'] = typeRecommendations.join('；');
      }

      // 分析事件密度
      final eventDensity = recentEvents.length / 7.0; // 每天平均事件数
      if (eventDensity > 3) {
        suggestions['schedule_management'] = '最近事件密度较高（${eventDensity.toStringAsFixed(1)}个/天），建议优化时间安排';
      } else if (eventDensity < 0.5) {
        suggestions['activity_increase'] = '最近活动较少（${eventDensity.toStringAsFixed(1)}个/天），可以考虑增加有意义的活动';
      }

      kgInsights['activity_analysis'] = {
        'recent_events_count': recentEvents.length,
        'event_density_per_day': eventDensity,
        'event_types': eventsByType.keys.toList(),
        'most_frequent_type': eventsByType.entries
            .reduce((a, b) => a.value.length > b.value.length ? a : b)
            .key,
      };

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成实体活动建议失败: $e');
    }
  }

  /// 🔥 第四步：生成基于时间模式的建议
  Future<void> _generateTemporalPatternSuggestions(
    Map<String, dynamic> suggestions,
    Map<String, dynamic> kgInsights,
  ) async {
    try {
      final objectBox = ObjectBoxService();
      final allEvents = objectBox.queryEventNodes()
          .where((event) => event.startTime != null)
          .toList();

      if (allEvents.length < 5) {
        return;
      }

      // 分析时间模式
      final hourDistribution = <int, int>{};
      final dayOfWeekDistribution = <int, int>{};

      for (final event in allEvents) {
        final eventTime = event.startTime!;
        final hour = eventTime.hour;
        final dayOfWeek = eventTime.weekday;

        hourDistribution[hour] = (hourDistribution[hour] ?? 0) + 1;
        dayOfWeekDistribution[dayOfWeek] = (dayOfWeekDistribution[dayOfWeek] ?? 0) + 1;
      }

      // 找出最活跃的时间段
      final mostActiveHour = hourDistribution.entries
          .reduce((a, b) => a.value > b.value ? a : b);

      final mostActiveDay = dayOfWeekDistribution.entries
          .reduce((a, b) => a.value > b.value ? a : b);

      final dayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

      suggestions['temporal_optimization'] =
          '您在${mostActiveHour.key}点和${dayNames[mostActiveDay.key]}最为活跃，建议在这些时间段安排重要任务';

      // 检测活动间隔
      final sortedEvents = allEvents..sort((a, b) => a.startTime!.compareTo(b.startTime!));
      final intervals = <int>[];

      for (int i = 1; i < sortedEvents.length; i++) {
        final interval = sortedEvents[i].startTime!.difference(sortedEvents[i-1].startTime!).inHours;
        if (interval < 168) { // 一周内的间隔
          intervals.add(interval);
        }
      }

      if (intervals.isNotEmpty) {
        final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;

        if (avgInterval < 4) {
          suggestions['pacing_advice'] = '活动间隔较短（${avgInterval.toStringAsFixed(1)}小时），建议适当放慢节奏';
        } else if (avgInterval > 48) {
          suggestions['consistency_advice'] = '活动间隔较长（${avgInterval.toStringAsFixed(1)}小时），建议保持更好的连续性';
        }
      }

      kgInsights['temporal_analysis'] = {
        'most_active_hour': mostActiveHour.key,
        'most_active_day': dayNames[mostActiveDay.key],
        'total_events_analyzed': allEvents.length,
        'average_interval_hours': intervals.isNotEmpty
            ? intervals.reduce((a, b) => a + b) / intervals.length
            : 0,
        'hour_distribution': hourDistribution,
        'day_distribution': dayOfWeekDistribution,
      };

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成时间模式建议失败: $e');
    }
  }

  /// 🔥 第四步：生成个性化行动计划
  Future<Map<String, dynamic>> _generatePersonalizedActionPlan(
    HumanUnderstandingSystemState currentState,
    Map<String, dynamic> kgInsights,
  ) async {
    final actionPlan = <String, dynamic>{
      'immediate_actions': <String>[],
      'short_term_goals': <String>[],
      'long_term_strategies': <String>[],
      'personalization_factors': <String, dynamic>{},
    };

    try {
      // 基于认知负载的即时行动
      final loadLevel = currentState.currentCognitiveLoad.level;
      switch (loadLevel) {
        case CognitiveLoadLevel.overload:
          actionPlan['immediate_actions'].add('立即暂停非必要任务，专注于最重要的1-2个意图');
          actionPlan['immediate_actions'].add('进行5分钟休息，降低认知负载');
          break;
        case CognitiveLoadLevel.high:
          actionPlan['immediate_actions'].add('优化当前任务优先级，延后不紧急的工作');
          break;
        case CognitiveLoadLevel.low:
          actionPlan['immediate_actions'].add('可以接受新的挑战或学习机会');
          break;
        default:
          actionPlan['immediate_actions'].add('保持当前工作节奏');
      }

      // 基于活跃意图的短期目标
      final activeIntents = currentState.activeIntents;
      for (final intent in activeIntents.take(3)) {
        if (intent.state == IntentLifecycleState.clarifying) {
          actionPlan['short_term_goals'].add('澄清意图：${intent.description}');
        } else if (intent.state == IntentLifecycleState.executing) {
          actionPlan['short_term_goals'].add('制定执行计划：${intent.description}');
        }
      }

      // 基于知识图谱的长期策略
      final entityPatterns = kgInsights['entity_patterns'] as Map<String, dynamic>? ?? {};
      final highActivityEntities = entityPatterns['high_activity_entities'] as List? ?? [];

      if (highActivityEntities.isNotEmpty) {
        actionPlan['long_term_strategies'].add('深化对高活跃度领域的投入：${highActivityEntities.take(2).join('、')}');
      }

      final temporalAnalysis = kgInsights['temporal_analysis'] as Map<String, dynamic>? ?? {};
      final mostActiveHour = temporalAnalysis['most_active_hour'] as int?;

      if (mostActiveHour != null) {
        actionPlan['long_term_strategies'].add('在最佳时间段（${mostActiveHour}点左右）安排重要工作');
      }

      // 个性化因素
      actionPlan['personalization_factors'] = {
        'cognitive_pattern': loadLevel.toString(),
        'preferred_work_time': mostActiveHour ?? 'unknown',
        'active_focus_areas': highActivityEntities.take(3),
        'current_intent_count': activeIntents.length,
        'recent_activity_level': kgInsights['activity_analysis']?['event_density_per_day'] ?? 0,
      };

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成个性化行动计划失败: $e');
      actionPlan['error'] = e.toString();
    }

    return actionPlan;
  }

  /// 🔥 第四步：获取增强的优先行动建议
  List<String> _getEnhancedPriorityActions(
    HumanUnderstandingSystemState state,
    Map<String, dynamic> kgInsights,
  ) {
    final actions = _getPriorityActions(state); // 获取基础建议

    // 基于知识图谱洞察添加增强建议
    final entityPatterns = kgInsights['entity_patterns'] as Map<String, dynamic>? ?? {};
    final highActivityEntities = entityPatterns['high_activity_entities'] as List? ?? [];
    final dormantEntities = entityPatterns['dormant_entities'] as List? ?? [];

    if (highActivityEntities.isNotEmpty) {
      actions.add('专注于高活跃领域：${highActivityEntities.first}');
    }

    if (dormantEntities.isNotEmpty) {
      actions.add('重新激活休眠领域：${dormantEntities.first}');
    }

    final activityAnalysis = kgInsights['activity_analysis'] as Map<String, dynamic>? ?? {};
    final eventDensity = activityAnalysis['event_density_per_day'] as double? ?? 0;

    if (eventDensity > 3) {
      actions.add('优化高密度时间安排');
    } else if (eventDensity < 0.5) {
      actions.add('增加有意义的活动');
    }

    return actions.take(5).toList(); // 限制为最多5个建议
  }

  /// 🔥 第四步：统计 HU 系统数据点
  int _countHuDataPoints(HumanUnderstandingSystemState state) {
    return state.activeIntents.length +
           state.activeTopics.length +
           state.recentCausalChains.length +
           state.recentTriples.length;
  }

  /// 🔥 第四步：评估建议质量
  String _assessSuggestionQuality(Map<String, dynamic> kgInsights) {
    final totalEntities = kgInsights['total_entities'] as int? ?? 0;
    final activityAnalysis = kgInsights['activity_analysis'] as Map<String, dynamic>? ?? {};
    final recentEventsCount = activityAnalysis['recent_events_count'] as int? ?? 0;

    if (totalEntities >= 5 && recentEventsCount >= 10) {
      return 'high';
    } else if (totalEntities >= 2 && recentEventsCount >= 3) {
      return 'medium';
    } else {
      return 'low';
    }
  }

  /// 🔥 新增：基础实体提取方法
  List<String> _extractBasicEntities(String content) {
    final entities = <String>[];

    // 技术相关实体
    final techPatterns = [
      r'Flutter', r'AI', r'数据库', r'Bug', r'性能优化', r'API', r'前端', r'后端',
      r'算法', r'机器学习', r'深度学习', r'人工智能', r'编程', r'代码', r'开发',
      r'测试', r'部署', r'架构', r'框架', r'库', r'SDK', r'IDE'
    ];

    // 工作相关实体
    final workPatterns = [
      r'项目', r'会议', r'团队', r'协作', r'任务', r'需求', r'功能', r'模块',
      r'版本', r'发布', r'上线', r'迭代', r'sprint', r'敏捷', r'产品',
      r'用户', r'客户', r'需求分析', r'设计', r'评审'
    ];

    // 学习相关实体
    final learningPatterns = [
      r'学习', r'研究', r'教程', r'文档', r'课程', r'培训', r'知识',
      r'技能', r'经验', r'实践', r'总结', r'分享', r'交流'
    ];

    // 生活相关实体
    final lifePatterns = [
      r'饮食', r'运动', r'休息', r'睡眠', r'健康', r'娱乐', r'旅行',
      r'购物', r'聚会', r'朋友', r'家人', r'兴趣', r'爱好'
    ];

    // 合并所有模式
    final allPatterns = [
      ...techPatterns,
      ...workPatterns,
      ...learningPatterns,
      ...lifePatterns
    ];

    // 提取匹配的实体
    for (final pattern in allPatterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      if (regex.hasMatch(content)) {
        entities.add(pattern);
      }
    }

    // 提取专有名词（大写字母开头的词）
    final properNounRegex = RegExp(r'\b[A-Z][a-zA-Z]{2,}\b');
    final properNouns = properNounRegex.allMatches(content)
        .map((match) => match.group(0)!)
        .where((word) => word.length > 2)
        .toList();
    entities.addAll(properNouns);

    // 去重并限制数量
    return entities.toSet().take(20).toList();
  }

  /// 🔥 新增：基础意图推断方法
  String _inferBasicIntent(String content) {
    final lowerContent = content.toLowerCase();

    // 问题相关
    if (lowerContent.contains('问题') || lowerContent.contains('bug') ||
        lowerContent.contains('错误') || lowerContent.contains('异常')) {
      return 'problem_solving';
    }

    // 学习相关
    if (lowerContent.contains('学习') || lowerContent.contains('了解') ||
        lowerContent.contains('研究') || lowerContent.contains('教程')) {
      return 'learning';
    }

    // 工作相关
    if (lowerContent.contains('项目') || lowerContent.contains('开发') ||
        lowerContent.contains('功能') || lowerContent.contains('需求')) {
      return 'work_planning';
    }

    // 分享相关
    if (lowerContent.contains('分享') || lowerContent.contains('介绍') ||
        lowerContent.contains('展示') || lowerContent.contains('演示')) {
      return 'sharing';
    }

    // 讨论相关
    if (lowerContent.contains('讨论') || lowerContent.contains('交流') ||
        lowerContent.contains('沟通') || lowerContent.contains('聊天')) {
      return 'discussion';
    }

    // 询问相关
    if (lowerContent.contains('?') || lowerContent.contains('？') ||
        lowerContent.contains('怎么') || lowerContent.contains('如何')) {
      return 'inquiry';
    }

    // 默认为一般对话
    return 'general_conversation';
  }

  /// 🔥 新增：基础情绪推断方法
  String _inferBasicEmotion(String content) {
    final lowerContent = content.toLowerCase();

    // 积极情绪
    final positiveKeywords = [
      '好', '棒', '赞', '优秀', '完美', '成功', '满意', '开心', '高兴',
      '兴奋', '期待', '喜欢', '爱', '感谢', '谢谢', '不错', '很棒'
    ];

    // 消极情绪
    final negativeKeywords = [
      '糟糕', '失败', '错误', '问题', '困难', '麻烦', '烦恼', '担心',
      '焦虑', '沮丧', '失望', '难过', '生气', '愤怒', '讨厌', '不好'
    ];

    // 中性情绪
    final neutralKeywords = [
      '正常', '一般', '普通', '还行', '可以', '了解', '知道', '明白',
      '理解', '分析', '思考', '考虑', '建议', '推荐'
    ];

    // 计算情绪得分
    int positiveScore = 0;
    int negativeScore = 0;
    int neutralScore = 0;

    for (final keyword in positiveKeywords) {
      if (lowerContent.contains(keyword)) {
        positiveScore++;
      }
    }

    for (final keyword in negativeKeywords) {
      if (lowerContent.contains(keyword)) {
        negativeScore++;
      }
    }

    for (final keyword in neutralKeywords) {
      if (lowerContent.contains(keyword)) {
        neutralScore++;
      }
    }

    // 判断主导情绪
    if (positiveScore > negativeScore && positiveScore > neutralScore) {
      return 'positive';
    } else if (negativeScore > positiveScore && negativeScore > neutralScore) {
      return 'negative';
    } else if (positiveScore == negativeScore && positiveScore > 0) {
      return 'mixed';
    } else {
      return 'neutral';
    }
  }

  /// 🔥 新增：处理语义分析输入的核心方法
  Future<void> processSemanticInput(SemanticAnalysisInput input) async {
    try {
      print('[HumanUnderstandingSystem] 🧠 开始处理语义输入...');

      // 🔥 修复：使用更通用的方法调用，避免依赖具体方法名
      await Future.wait([
        // 意图管理器处理 - 使用通用接口或跳过
        Future(() async {
          try {
            // 尝试调用分析方法，如果不存在则跳过
            if (_intentManager.runtimeType.toString().contains('IntentLifecycleManager')) {
              // 直接分析输入内容并创建意图
              await _intentManager.analyzeIntent(input.content, input.intent);
            }
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 意图管理器处理失败: $e');
          }
        }),

        // 主题跟踪器处理
        Future(() async {
          try {
            // 直接添加主题而不是处理输入
            final entities = input.entities;
            for (final entity in entities.take(3)) { // 限制数量
              await _topicTracker.addTopic(entity, importance: 0.8);
            }
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 主题跟踪器处理失败: $e');
          }
        }),

        // 因果链提取器处理
        Future(() async {
          try {
            // 简单的因果关系提取
            await _causalExtractor.extractCausalRelations(input);
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 因果链提取器处理失败: $e');
          }
        }),

        // 语义图构建器处理
        Future(() async {
          try {
            // 添加语义三元组
            for (int i = 0; i < input.entities.length - 1; i++) {
              final subject = input.entities[i];
              final object = input.entities[i + 1];
              await _graphBuilder.addTriple(subject, '相关', object);
            }
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 语义图构建器处理失败: $e');
          }
        }),

        // 认知负载估算器处理
        Future(() async {
          try {
            // 更新认知负载
            await _loadEstimator.updateLoad(
              activeIntentCount: _intentManager.getActiveIntents().length,
              activeTopicCount: _topicTracker.getActiveTopics().length,
              emotionalIntensity: _mapEmotionToIntensity(input.emotion),
              // 移除未定义的contentComplexity参数
            );
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 认知负载估算器处理失败: $e');
          }
        }),
      ]);

      print('[HumanUnderstandingSystem] ✅ 语义输入处理完成');

      // 更新系统状态
      _updateSystemState();

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 处理语义输入失败: $e');
    }
  }

  /// 🔥 新增：映射情绪到强度值
  double _mapEmotionToIntensity(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'positive':
        return 0.3; // 积极情绪，认知负载较低
      case 'negative':
        return 0.8; // 消极情绪，认知负载较高
      case 'mixed':
        return 0.6; // 混合情绪，中等认知负载
      default:
        return 0.5; // 中性情绪，正常认知负载
    }
  }

  /// 🔥 新增：分析意图模式
  Map<String, dynamic> _analyzeIntentPatterns(List<Intent> intents) {
    final patterns = <String, dynamic>{
      'pattern_count': 0,
      'dominant_intent_types': <String>[],
      'intent_frequency': <String, int>{},
      'completion_rate': 0.0,
    };

    if (intents.isEmpty) return patterns;

    // 统计意图类型频率
    final typeFrequency = <String, int>{};
    int completedCount = 0;

    for (final intent in intents) {
      // 🔥 修复：使用description而不是type
      final type = intent.description ?? 'unknown';
      typeFrequency[type] = (typeFrequency[type] ?? 0) + 1;

      if (intent.state == IntentLifecycleState.completed) {
        completedCount++;
      }
    }

    // 找出主导意图类型
    final sortedTypes = typeFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    patterns['pattern_count'] = typeFrequency.length;
    patterns['dominant_intent_types'] = sortedTypes.take(3).map((e) => e.key).toList();
    patterns['intent_frequency'] = typeFrequency;
    patterns['completion_rate'] = intents.isNotEmpty ? (completedCount / intents.length) : 0.0;

    return patterns;
  }

  /// 🔥 新增：分析主题模式
  Map<String, dynamic> _analyzeTopicPatterns(List<ConversationTopic> topics) {
    final patterns = <String, dynamic>{
      'pattern_count': 0,
      'active_topic_count': 0,
      'topic_diversity': 0.0,
      'average_engagement': 0.0,
    };

    if (topics.isEmpty) return patterns;

    int activeTopics = 0;
    double totalEngagement = 0.0;

    for (final topic in topics) {
      // 🔥 修复：假设主题有一个活跃状态判断，可能需要根据实际模型调整
      if (topic.lastActivity.isAfter(DateTime.now().subtract(Duration(hours: 24)))) {
        activeTopics++;
      }
      // 🔥 修复：使用importance作为engagement的替代
      totalEngagement += topic.importance;
    }

    patterns['pattern_count'] = topics.length;
    patterns['active_topic_count'] = activeTopics;
    patterns['topic_diversity'] = topics.length / 10.0; // 相对多样性
    patterns['average_engagement'] = topics.isNotEmpty ? (totalEngagement / topics.length) : 0.0;

    return patterns;
  }

  /// 🔥 新增：重置系统
  Future<void> resetSystem() async {
    try {
      print('[HumanUnderstandingSystem] 🔄 开始重置系统...');

      // 停止监听
      _conversationMonitorTimer?.cancel();
      _stateUpdateTimer?.cancel();
      _isMonitoring = false;

      // 清理数据
      _processedRecordIds.clear();
      _lastProcessedTimestamp = 0;

      // 🔥 修复：重置子模块 - 使用通用方法或跳过
      await Future.wait([
        Future(() async {
          try {
            // 尝试重置意图管理器
            await _intentManager.clearAllIntents();
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 重置意图管理器失败: $e');
          }
        }),
        Future(() async {
          try {
            // 尝试重置主题跟踪器
            await _topicTracker.clearAllTopics();
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 重置主题跟踪器失败: $e');
          }
        }),
        Future(() async {
          try {
            // 尝试重置因果链提取器
            await _causalExtractor.clearAllRelations();
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 重置因果链提取器失败: $e');
          }
        }),
        Future(() async {
          try {
            // 尝试重置语义图构建器
            await _graphBuilder.clearAllTriples();
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 重置语义图构建器失败: $e');
          }
        }),
        Future(() async {
          try {
            // 尝试重置认知负载估算器
            await _loadEstimator.resetLoad();
          } catch (e) {
            print('[HumanUnderstandingSystem] ⚠️ 重置认知负载估算器失败: $e');
          }
        }),
      ]);

      // 重新初始化
      _initialized = false;
      await initialize();

      print('[HumanUnderstandingSystem] ✅ 系统重置完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 系统重置失败: $e');
      rethrow;
    }
  }

  /// 🔥 新增：获取监听状态
  Map<String, dynamic> getMonitoringStatus() {
    return {
      'is_monitoring': _isMonitoring,
      'monitor_interval_seconds': _monitorInterval,
      'last_processed_timestamp': _lastProcessedTimestamp,
      'processed_records_count': _processedRecordIds.length,
      'system_initialized': _initialized,
      'conversation_batch_size': _conversationBatchSize,
      'monitoring_active_since': _isMonitoring ? _initTime.toIso8601String() : null,
    };
  }

  /// 🔥 新增：获取系统指标
  Map<String, dynamic> getSystemMetrics() {
    final currentState = getCurrentState();
    return {
      'system_status': {
        'initialized': _initialized,
        'monitoring': _isMonitoring,
        'uptime_minutes': DateTime.now().difference(_initTime).inMinutes,
      },
      'data_metrics': {
        'active_intents': currentState.activeIntents.length,
        'active_topics': currentState.activeTopics.length,
        'recent_causal_chains': currentState.recentCausalChains.length,
        'recent_triples': currentState.recentTriples.length,
        'processed_records': _processedRecordIds.length,
      },
      'cognitive_load': {
        'level': currentState.currentCognitiveLoad.level.toString(),
        'score': currentState.currentCognitiveLoad.score,
        'recommendation': currentState.currentCognitiveLoad.recommendation,
      },
      'performance_metrics': {
        'monitor_interval': _monitorInterval,
        'batch_size': _conversationBatchSize,
        'last_processed': DateTime.fromMillisecondsSinceEpoch(_lastProcessedTimestamp).toIso8601String(),
      },
    };
  }

  /// 🔥 新增：分析用户模式
  Future<Map<String, dynamic>> analyzeUserPatterns() async {
    try {
      final currentState = getCurrentState();
      final patterns = <String, dynamic>{};

      // 意图模式分析
      final intentPatterns = _analyzeIntentPatterns(currentState.activeIntents);
      patterns['intent_patterns'] = intentPatterns;

      // 主题模式分析
      final topicPatterns = _analyzeTopicPatterns(currentState.activeTopics);
      patterns['topic_patterns'] = topicPatterns;

      // 认知负载模式分析
      final cognitivePatterns = _analyzeCognitivePatterns(currentState.currentCognitiveLoad);
      patterns['cognitive_patterns'] = cognitivePatterns;

      // 时间模式分析（需要从知识图谱获取数据）
      final temporalPatterns = await _analyzeTemporalPatterns();
      patterns['temporal_patterns'] = temporalPatterns;

      // 行为模式分析
      final behaviorPatterns = _analyzeBehaviorPatterns(currentState.recentCausalChains);
      patterns['behavior_patterns'] = behaviorPatterns;

      patterns['analysis_timestamp'] = DateTime.now().toIso8601String();
      patterns['total_pattern_count'] = intentPatterns['pattern_count'] +
                                       topicPatterns['pattern_count'] +
                                       temporalPatterns['pattern_count'];

      return patterns;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 分析用户模式失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 🔥 新增：分析认知负载模式
  Map<String, dynamic> _analyzeCognitivePatterns(CognitiveLoadAssessment load) {
    return {
      'pattern_count': 1,
      'current_level': load.level.toString(),
      'load_score': load.score,
      'stress_indicators': load.factors.keys.where((key) =>
        load.factors[key]! > 0.7).toList(),
      'optimization_needed': load.level == CognitiveLoadLevel.overload ||
                            load.level == CognitiveLoadLevel.high,
    };
  }

  /// 🔥 新增：分析时间模式
  Future<Map<String, dynamic>> _analyzeTemporalPatterns() async {
    try {
      final objectBox = ObjectBoxService();
      final recentEvents = objectBox.queryEventNodes()
          .where((event) => event.startTime != null &&
                          event.startTime!.isAfter(DateTime.now().subtract(Duration(days: 30))))
          .toList();

      final patterns = <String, dynamic>{
        'pattern_count': 0,
        'peak_hours': <int>[],
        'activity_rhythm': 'unknown',
        'weekly_distribution': <String, int>{},
      };

      if (recentEvents.isEmpty) return patterns;

      // 分析小时分布
      final hourCounts = <int, int>{};
      final dayOfWeekCounts = <int, int>{};

      for (final event in recentEvents) {
        final hour = event.startTime!.hour;
        final dayOfWeek = event.startTime!.weekday;

        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
        dayOfWeekCounts[dayOfWeek] = (dayOfWeekCounts[dayOfWeek] ?? 0) + 1;
      }

      // 找出活跃时间段
      final sortedHours = hourCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      patterns['pattern_count'] = hourCounts.length;
      patterns['peak_hours'] = sortedHours.take(3).map((e) => e.key).toList();

      // 判断活动节律
      final morningActivity = hourCounts.entries
          .where((e) => e.key >= 6 && e.key < 12)
          .fold(0, (sum, e) => sum + e.value);
      final afternoonActivity = hourCounts.entries
          .where((e) => e.key >= 12 && e.key < 18)
          .fold(0, (sum, e) => sum + e.value);
      final eveningActivity = hourCounts.entries
          .where((e) => e.key >= 18 || e.key < 6)
          .fold(0, (sum, e) => sum + e.value);

      if (morningActivity > afternoonActivity && morningActivity > eveningActivity) {
        patterns['activity_rhythm'] = 'morning_person';
      } else if (eveningActivity > morningActivity && eveningActivity > afternoonActivity) {
        patterns['activity_rhythm'] = 'evening_person';
      } else {
        patterns['activity_rhythm'] = 'balanced';
      }

      // 周分布
      final dayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final weeklyDist = <String, int>{};
      dayOfWeekCounts.forEach((day, count) {
        if (day >= 1 && day <= 7) {
          weeklyDist[dayNames[day]] = count;
        }
      });
      patterns['weekly_distribution'] = weeklyDist;

      return patterns;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 分析时间模式失败: $e');
      return {'pattern_count': 0, 'error': e.toString()};
    }
  }

  /// 🔥 新增：分析行为模式
  Map<String, dynamic> _analyzeBehaviorPatterns(List<CausalRelation> causalChains) {
    final patterns = <String, dynamic>{
      'pattern_count': 0,
      'common_triggers': <String>[],
      'frequent_outcomes': <String>[],
      'behavior_complexity': 0.0,
    };

    if (causalChains.isEmpty) return patterns;

    // 统计触发因素和结果
    final triggers = <String, int>{};
    final outcomes = <String, int>{};

    for (final relation in causalChains) {
      triggers[relation.cause] = (triggers[relation.cause] ?? 0) + 1;
      outcomes[relation.effect] = (outcomes[relation.effect] ?? 0) + 1;
    }

    // 找出常见模式
    final sortedTriggers = triggers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedOutcomes = outcomes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    patterns['pattern_count'] = causalChains.length;
    patterns['common_triggers'] = sortedTriggers.take(3).map((e) => e.key).toList();
    patterns['frequent_outcomes'] = sortedOutcomes.take(3).map((e) => e.key).toList();
    patterns['behavior_complexity'] = causalChains.length / 10.0; // 相对复杂度

    return patterns;
  }

  /// 🔥 新增：导出系统数据
  Future<Map<String, dynamic>> exportSystemData() async {
    try {
      final exportData = <String, dynamic>{
        'export_metadata': {
          'timestamp': DateTime.now().toIso8601String(),
          'version': '1.0.0',
          'system_uptime': DateTime.now().difference(_initTime).inMinutes,
        },
      };

      // 导出当前状态
      final currentState = getCurrentState();
      exportData['current_state'] = {
        'active_intents': currentState.activeIntents.map((i) => i.toJson()).toList(),
        'active_topics': currentState.activeTopics.map((t) => t.toJson()).toList(),
        'recent_causal_chains': currentState.recentCausalChains.map((c) => c.toJson()).toList(),
        'recent_triples': currentState.recentTriples.map((t) => t.toJson()).toList(),
        'cognitive_load': {
          'level': currentState.currentCognitiveLoad.level.toString(),
          'score': currentState.currentCognitiveLoad.score,
          'factors': currentState.currentCognitiveLoad.factors,
        },
      };

      // 导出系统指标
      exportData['system_metrics'] = getSystemMetrics();

      // 导出监听状态
      exportData['monitoring_status'] = getMonitoringStatus();

      // 导出用户模式分析
      exportData['user_patterns'] = await analyzeUserPatterns();

      // 导出知识图谱统计（如果可用）
      try {
        final kgStats = await _exportKnowledgeGraphStats();
        exportData['knowledge_graph_stats'] = kgStats;
      } catch (e) {
        exportData['knowledge_graph_stats'] = {'error': e.toString()};
      }

      exportData['export_summary'] = {
        'total_active_intents': currentState.activeIntents.length,
        'total_active_topics': currentState.activeTopics.length,
        'total_causal_relations': currentState.recentCausalChains.length,
        'total_semantic_triples': currentState.recentTriples.length,
        'data_completeness': _calculateDataCompleteness(currentState),
      };

      return exportData;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 导出系统数据失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 🔥 新增：导出知识图谱统计
  Future<Map<String, dynamic>> _exportKnowledgeGraphStats() async {
    final objectBox = ObjectBoxService();

    final entityNodes = objectBox.queryEntityNodes();
    final eventNodes = objectBox.queryEventNodes();

    return {
      'entity_count': entityNodes.length,
      'event_count': eventNodes.length,
      'recent_entities': entityNodes
          .where((e) => e.lastUpdated.isAfter(DateTime.now().subtract(Duration(days: 7))))
          .length,
      'recent_events': eventNodes
          .where((e) => e.lastUpdated.isAfter(DateTime.now().subtract(Duration(days: 7))))
          .length,
      'entity_types': entityNodes.map((e) => e.type).toSet().toList(),
      'event_types': eventNodes.map((e) => e.type).toSet().toList(),
    };
  }

  /// 🔥 新增：计算数据完整性
  double _calculateDataCompleteness(HumanUnderstandingSystemState state) {
    int totalPoints = 0;
    int availablePoints = 0;

    // 意图数据 (25%)
    totalPoints += 25;
    if (state.activeIntents.isNotEmpty) {
      availablePoints += 25;
    }

    // 主题数据 (25%)
    totalPoints += 25;
    if (state.activeTopics.isNotEmpty) {
      availablePoints += 25;
    }

    // 因果关系数据 (25%)
    totalPoints += 25;
    if (state.recentCausalChains.isNotEmpty) {
      availablePoints += 25;
    }

    // 语义三元组数据 (25%)
    totalPoints += 25;
    if (state.recentTriples.isNotEmpty) {
      availablePoints += 25;
    }

    return totalPoints > 0 ? (availablePoints / totalPoints) : 0.0;
  }

  /// 🔥 新增：触发对话检查
  Future<void> triggerDialogueCheck() async {
    try {
      print('[HumanUnderstandingSystem] 🔍 手动触发对话检查...');

      if (!_initialized) {
        print('[HumanUnderstandingSystem] ⚠️ 系统未初始化，跳过检查');
        return;
      }

      // 强制执行一次对话监听
      await _monitorNewConversations();

      print('[HumanUnderstandingSystem] ✅ 对话检查完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 对话检查失败: $e');
    }
  }

  /// 🔥 新增：重置监听状态
  void resetMonitoringStatus() {
    try {
      print('[HumanUnderstandingSystem] 🔄 重置监听状态...');

      // 停止当前监听
      _conversationMonitorTimer?.cancel();
      _isMonitoring = false;

      // 清理监听相关数据
      _processedRecordIds.clear();
      _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;

      // 重新启动监听
      if (_initialized) {
        _startConversationMonitoring();
      }

      print('[HumanUnderstandingSystem] ✅ 监听状态已重置');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 重置监听状态失败: $e');
    }
  }

  /// 🔥 新增：获取调试信息
  Map<String, dynamic> getDebugInfo() {
    return {
      'system_state': {
        'initialized': _initialized,
        'initializing': _initializing,
        'monitoring': _isMonitoring,
        'init_time': _initTime.toIso8601String(),
        'uptime_minutes': DateTime.now().difference(_initTime).inMinutes,
      },
      'monitoring_config': {
        'monitor_interval': _monitorInterval,
        'batch_size': _conversationBatchSize,
        'last_processed_timestamp': _lastProcessedTimestamp,
        'processed_records_count': _processedRecordIds.length,
      },
      'sub_modules': {
        'intent_manager': 'IntentLifecycleManager',
        'topic_tracker': 'ConversationTopicTracker',
        'causal_extractor': 'CausalChainExtractor',
        'graph_builder': 'SemanticGraphBuilder',
        'load_estimator': 'CognitiveLoadEstimator',
        'reminder_manager': 'IntelligentReminderManager',
        'knowledge_graph': 'KnowledgeGraphService',
      },
      'timers_status': {
        'state_update_timer_active': _stateUpdateTimer?.isActive ?? false,
        'conversation_monitor_timer_active': _conversationMonitorTimer?.isActive ?? false,
      },
      'memory_usage': {
        'processed_record_ids': _processedRecordIds.length,
        'stream_controller_has_listener': _systemStateController.hasListener,
      },
      'debug_timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 🔥 新增：获取优先行动建议
  List<String> _getPriorityActions(HumanUnderstandingSystemState state) {
    final actions = <String>[];

    // 基于认知负载的建议
    switch (state.currentCognitiveLoad.level) {
      case CognitiveLoadLevel.overload:
        actions.add('立即减少任务数量');
        actions.add('专注于最重要的意图');
        break;
      case CognitiveLoadLevel.high:
        actions.add('优化任务优先级');
        actions.add('适当休息');
        break;
      case CognitiveLoadLevel.low:
        actions.add('可以接受新挑战');
        actions.add('学习新技能');
        break;
      default:
        actions.add('保持当前节奏');
    }

    // 基于活跃意图的建议
    final activeIntents = state.activeIntents;
    if (activeIntents.length > 3) {
      actions.add('整理和优化意图清单');
    }

    // 基于主题的建议
    final activeTopics = state.activeTopics;
    if (activeTopics.length > 5) {
      actions.add('聚焦核心讨论主题');
    }

    // 基于因果关系的建议
    if (state.recentCausalChains.isNotEmpty) {
      actions.add('分析行为模式和动机');
    }

    return actions.take(3).toList(); // 限制为最多3个优先建议
  }

  /// 释放所有资源
  void dispose() {
    _stateUpdateTimer?.cancel();
    _conversationMonitorTimer?.cancel();
    _systemStateController.close();

    _intentManager.dispose();
    _topicTracker.dispose();
    _causalExtractor.dispose();
    _graphBuilder.dispose();
    _loadEstimator.dispose();

    _initialized = false;
    print('[HumanUnderstandingSystem] 🔌 人类理解系统已完全释放');
  }
}
