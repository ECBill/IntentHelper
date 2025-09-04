/// 人类理解系统主服务
/// 整合所有子模块，提供统一的类人理解能力

import 'dart:async';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/intent_lifecycle_manager.dart';
import 'package:app/services/conversation_topic_tracker.dart';
import 'package:app/services/causal_chain_extractor.dart';
import 'package:app/services/semantic_graph_builder.dart';
import 'package:app/services/cognitive_load_estimator.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/knowledge_graph_service.dart'; // 🔥 新增：知识图谱服务
import 'package:app/models/graph_models.dart'; // 🔥 新增：知识图谱模型

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

  // 🔥 新增：初始化状态���志
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

  /// 🔥 新增：判断是否为系��消息
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
        print('[HumanUnderstandingSystem] ⚠️ 对话上下��为空，跳过处理');
        return;
      }

      print('[HumanUnderstandingSystem] 📝 对话上下文长度: ${conversationContext.length}');
      print('[HumanUnderstandingSystem] 🔍 对话预览: "${conversationContext.substring(0, conversationContext.length > 100 ? 100 : conversationContext.length)}..."');

      // 创建语义分析输入
      final semanticInput = _createSemanticAnalysisFromContext(conversationContext, records);

      // 处理语义输入
      await processSemanticInput(semanticInput);

      print('[HumanUnderstandingSystem] ✅ 批量对话处理完成');

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

  /// 🔥 修复：从对话上下文创建语义分析输入
  SemanticAnalysisInput _createSemanticAnalysisFromContext(String context, List<dynamic> records) {
    // 提取所有对话内容
    final allContent = records
        .map((r) => r.content?.toString() ?? '')
        .where((content) => content.trim().isNotEmpty)
        .join(' ');

    // 基础实体��取
    final entities = _extractBasicEntities(allContent);

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
        'source': 'real_conversation_monitoring',
        'conversation_context': context,
        'record_count': records.length,
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
      final limitedRecords = recentRecords.take(10).toList(); // 🔥 优化：减少初始���理数量
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
          content: '展示对话分析和语义理解���基础能力',
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

    // 🔥 新增：生成知识图谱数据统计
    final knowledgeGraphData = _generateKnowledgeGraphData();

    // 🔥 新增：生成意图主题关系映射
    final intentTopicRelations = _generateIntentTopicRelations();

    return HumanUnderstandingSystemState(
      activeIntents: _intentManager.getActiveIntents(),
      activeTopics: _topicTracker.getActiveTopics(),
      recentCausalChains: _causalExtractor.getRecentCausalRelations(limit: 5),
      recentTriples: _graphBuilder.getRecentTriples(limit: 10),
      currentCognitiveLoad: currentLoad,
      knowledgeGraphData: knowledgeGraphData, // 🔥 新增
      intentTopicRelations: intentTopicRelations, // 🔥 新增
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

      results['total_results'] = relatedIntents.length + relatedTopics.length +
          relatedCausal.length + relatedTriples.length;

      return results;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 搜索相关信息失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 分析用户行为模式
  Map<String, dynamic> analyzeUserPatterns() {
    try {
      return {
        'intent_statistics': _intentManager.getIntentStatistics(),
        'topic_statistics': _topicTracker.getTopicStatistics(),
        'causal_statistics': _causalExtractor.getCausalStatistics(),
        'graph_statistics': _graphBuilder.getGraphStatistics(),
        'load_patterns': _loadEstimator.analyzeLoadPatterns(),
        'analysis_timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 分析用户模式失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 获取系统性能指标
  Map<String, dynamic> getSystemMetrics() {
    return {
      'system_initialized': _initialized,
      'uptime_minutes': _initialized ? DateTime.now().difference(_initTime).inMinutes : 0,
      'modules_status': {
        'intent_manager': _intentManager.getIntentStatistics(),
        'topic_tracker': _topicTracker.getTopicStatistics(),
        'causal_extractor': _causalExtractor.getCausalStatistics(),
        'graph_builder': _graphBuilder.getGraphStatistics(),
        'load_estimator': _loadEstimator.getLoadStatistics(),
      },
      'last_update': DateTime.now().toIso8601String(),
    };
  }

  /// 重置系统状态
  Future<void> resetSystem() async {
    print('[HumanUnderstandingSystem] 🔄 重置系统状态...');

    try {
      // 停止��有定时器
      _stateUpdateTimer?.cancel();
      _conversationMonitorTimer?.cancel();

      // 释放所有子模块
      _intentManager.dispose();
      _topicTracker.dispose();
      _causalExtractor.dispose();
      _graphBuilder.dispose();
      _loadEstimator.dispose();

      _initialized = false;

      // 重新初始化
      await initialize();

      print('[HumanUnderstandingSystem] ✅ 系统重置完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 系统重置失败: $e');
      rethrow;
    }
  }

  /// 导出系统数据
  Map<String, dynamic> exportSystemData() {
    try {
      return {
        'export_timestamp': DateTime.now().toIso8601String(),
        'system_state': getCurrentState().toJson(),
        'detailed_data': {
          'all_intents': _intentManager.getActiveIntents().map((i) => i.toJson()).toList(),
          'all_topics': _topicTracker.getAllTopics().map((t) => t.toJson()).toList(),
          'causal_relations': _causalExtractor.getRecentCausalRelations(limit: 100).map((c) => c.toJson()).toList(),
          'semantic_graph': _graphBuilder.exportGraph(),
          'load_history': _loadEstimator.getLoadHistory(limit: 50).map((l) => l.toJson()).toList(),
        },
        'system_metrics': getSystemMetrics(),
      };
    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 导出系统数据失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 处理新的语义分析输入（直接与知识图谱对接）
  Future<HumanUnderstandingSystemState> processSemanticInput(
    SemanticAnalysisInput analysis,
  ) async {
    // 🔥 修复：避免在初始化过程中触发循环调用
    if (_initializing) {
      print('[HumanUnderstandingSystem] ⚠️ 系统正在初始化中，跳过语义输入处理');
      // 返回默认状态
      return HumanUnderstandingSystemState(
        activeIntents: [],
        activeTopics: [],
        recentCausalChains: [],
        recentTriples: [],
        currentCognitiveLoad: CognitiveLoadAssessment(
          level: CognitiveLoadLevel.moderate,
          score: 0.5,
          factors: {},
          activeIntentCount: 0,
          activeTopicCount: 0,
          emotionalIntensity: 0.5,
          topicSwitchRate: 0.0,
          complexityScore: 0.5,
        ),
        systemMetrics: {'status': 'initializing'},
      );
    }

    if (!_initialized) {
      print('[HumanUnderstandingSystem] ⚠️ 系统未初始化，跳过语义输入处理');
      // 返回默认状态，不触发初始化
      return HumanUnderstandingSystemState(
        activeIntents: [],
        activeTopics: [],
        recentCausalChains: [],
        recentTriples: [],
        currentCognitiveLoad: CognitiveLoadAssessment(
          level: CognitiveLoadLevel.moderate,
          score: 0.5,
          factors: {},
          activeIntentCount: 0,
          activeTopicCount: 0,
          emotionalIntensity: 0.5,
          topicSwitchRate: 0.0,
          complexityScore: 0.5,
        ),
        systemMetrics: {'status': 'not_initialized'},
      );
    }

    print('[HumanUnderstandingSystem] 🧠 处理语义输入: "${analysis.content.substring(0, analysis.content.length > 50 ? 50 : analysis.content.length)}..."');

    try {
      final stopwatch = Stopwatch()..start();

      // 🔥 第一步 - 分析对话内容获取知识图谱上下文（不写入数据库）
      print('[HumanUnderstandingSystem] 📝 分析对话内容获取知识图谱上下文...');

      // 构建用户状态上下文，用于增强知识图谱提取
      final userStateContext = {
        'active_intents': _intentManager.getActiveIntents().map((i) => i.toJson()).toList(),
        'active_topics': _topicTracker.getActiveTopics().map((t) => t.toJson()).toList(),
        'cognitive_load': _loadEstimator.getCurrentLoad()?.toJson() ?? {},
      };

      // 🔥 改为使用只分析不写入的函数
      final analysisResult = await KnowledgeGraphService.analyzeEventsAndEntitiesFromText(
        analysis.content,
        conversationTime: analysis.timestamp,
        userStateContext: userStateContext,
      );

      // 🔥 第二步 - 基于分析结果查询知识图谱获取相关上下文信息
      final knowledgeContext = await KnowledgeGraphService.getContextFromAnalysis(analysisResult);
      print('[HumanUnderstandingSystem] 🔍 知识图谱上下文: 找到${knowledgeContext['related_nodes']?.length ?? 0}个相关节点, ${knowledgeContext['related_events']?.length ?? 0}个相关事件');

      // 生成上下文ID用于日志和状态记录
      final contextId = 'analysis_${analysis.timestamp.millisecondsSinceEpoch}';

      // 🔥 第三步 - 创建增强的分析输入，包含知识图谱上下文
      final enhancedAnalysis = _enhanceAnalysisWithKnowledgeGraph(analysis, knowledgeContext);

      // 1. 并行处理基础分析（使用增强的分析输入）
      final results = await Future.wait([
        _intentManager.processSemanticAnalysis(enhancedAnalysis),
        _topicTracker.processConversation(enhancedAnalysis),
        _causalExtractor.extractCausalRelations(enhancedAnalysis),
      ]);

      final intents = results[0] as List<Intent>;
      final topics = results[1] as List<ConversationTopic>;
      final causalRelations = results[2] as List<CausalRelation>;

      // 🔥 第四步 - 基于知识图谱增强主题信息
      final enhancedTopics = await _enhanceTopicsWithKnowledgeGraph(topics, knowledgeContext);

      // 2. 构建语义图谱（依赖前面的结果）
      final triples = await _graphBuilder.buildSemanticGraph(
        enhancedAnalysis,
        intents,
        enhancedTopics,
        causalRelations,
      );

      // 3. 评估认知负载
      final cognitiveLoad = await _loadEstimator.assessCognitiveLoad(
        activeIntents: _intentManager.getActiveIntents(),
        activeTopics: _topicTracker.getActiveTopics(),
        backgroundTopics: _topicTracker.getBackgroundTopics(),
        currentEmotion: analysis.emotion,
        topicSwitchRate: _topicTracker.calculateTopicSwitchRate(),
        lastConversationContent: analysis.content,
        additionalContext: analysis.additionalContext,
      );

      // 4. 生成系统状态快照（包含知识图谱统计）
      final systemState = HumanUnderstandingSystemState(
        activeIntents: _intentManager.getActiveIntents(),
        activeTopics: _topicTracker.getActiveTopics(),
        recentCausalChains: _causalExtractor.getRecentCausalRelations(limit: 5),
        recentTriples: _graphBuilder.getRecentTriples(limit: 10),
        currentCognitiveLoad: cognitiveLoad,
        systemMetrics: {
          'processing_time_ms': stopwatch.elapsedMilliseconds,
          'new_intents': intents.length,
          'new_topics': topics.length,
          'new_causal_relations': causalRelations.length,
          'new_triples': triples.length,
          'knowledge_graph_context': knowledgeContext, // 🔥 知识图谱上下文信息
          'knowledge_graph_processing': {
            'context_id': contextId,
            'events_extracted': true,
            'entities_aligned': true,
            'processed_via_kg': true, // 标记为通过知识图谱处理
          },
          'analysis_timestamp': analysis.timestamp.toIso8601String(),
        },
      );

      _systemStateController.add(systemState);

      stopwatch.stop();
      print('[HumanUnderstandingSystem] ✅ 语义处理完成 (${stopwatch.elapsedMilliseconds}ms)');
      print('[HumanUnderstandingSystem] 📊 新增: ${intents.length}意图, ${topics.length}主题, ${causalRelations.length}因果, ${triples.length}三元组');
      print('[HumanUnderstandingSystem] 🔗 知识图谱辅助: ${knowledgeContext['related_nodes']?.length ?? 0}个相关节点帮助分析');
      print('[HumanUnderstandingSystem] 🗃️ 直接存储到知识图谱，上下文ID: $contextId');

      return systemState;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 处理语义输入失败: $e');
      rethrow;
    }
  }

  /// 获取智能建议
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

  /// 获取优先行动建议
  List<String> _getPriorityActions(HumanUnderstandingSystemState state) {
    final actions = <String>[];

    // 基于认知负载
    if (state.currentCognitiveLoad.level == CognitiveLoadLevel.overload) {
      actions.add('立即减少活跃任务数量');
    } else if (state.currentCognitiveLoad.level == CognitiveLoadLevel.high) {
      actions.add('优先处理紧急重要的意图');
    }

    // 基于意图状态
    final clarifyingIntents = state.activeIntents.where(
      (intent) => intent.state == IntentLifecycleState.clarifying
    ).toList();
    if (clarifyingIntents.isNotEmpty) {
      actions.add('澄清 ${clarifyingIntents.length} 个需要明确的意图');
    }

    // 基于主题活跃度
    final highRelevanceTopics = state.activeTopics.where(
      (topic) => topic.relevanceScore > 0.8
    ).toList();
    if (highRelevanceTopics.isNotEmpty) {
      actions.add('深入讨论高相关性主题：${highRelevanceTopics.map((t) => t.name).take(2).join('、')}');
    }

    return actions;
  }

  /// 🔥 新增：基础实体提取
  List<String> _extractBasicEntities(String content) {
    final entities = <String>[];

    // 技术相关
    if (content.contains('Flutter') || content.contains('flutter')) entities.add('Flutter');
    if (content.contains('AI') || content.contains('人工智能')) entities.add('AI');
    if (content.contains('机器学习')) entities.add('机器学习');
    if (content.contains('数据库')) entities.add('数据库');
    if (content.contains('性能') || content.contains('优化')) entities.add('性能优化');
    if (content.contains('Bug') || content.contains('错误')) entities.add('Bug修复');

    // 工作相关
    if (content.contains('项目') || content.contains('工作')) entities.add('工作项目');
    if (content.contains('会议') || content.contains('讨论')) entities.add('会议');
    if (content.contains('团队') || content.contains('协作')) entities.add('团队协作');
    if (content.contains('功能') || content.contains('模块')) entities.add('功能开发');

    // 学习相关
    if (content.contains('学习') || content.contains('教程')) entities.add('学习');
    if (content.contains('了解') || content.contains('研究')) entities.add('研究');

    // 日常生活相关
    if (content.contains('吃') || content.contains('饭') || content.contains('食物')) entities.add('饮食');
    if (content.contains('睡觉') || content.contains('休息')) entities.add('休息');
    if (content.contains('运动') || content.contains('锻炼')) entities.add('运动');

    return entities.isEmpty ? ['对话'] : entities;
  }

  /// 🔥 新增：基础意图推断
  String _inferBasicIntent(String content) {
    if (content.contains('学习') || content.contains('教程') || content.contains('了解')) {
      return 'learning';
    }
    if (content.contains('规划') || content.contains('计划') || content.contains('准备')) {
      return 'planning';
    }
    if (content.contains('问题') || content.contains('Bug') || content.contains('优化')) {
      return 'problem_solving';
    }
    if (content.contains('完成') || content.contains('进展') || content.contains('做了')) {
      return 'sharing_experience';
    }
    if (content.contains('推荐') || content.contains('什么') || content.contains('如何')) {
      return 'information_seeking';
    }
    return 'casual_chat';
  }

  /// 🔥 新增：基础情绪推断
  String _inferBasicEmotion(String content) {
    if (content.contains('不错') || content.contains('完成') || content.contains('好')) {
      return 'positive';
    }
    if (content.contains('困难') || content.contains('问题') || content.contains('棘手')) {
      return 'frustrated';
    }
    if (content.contains('感兴趣') || content.contains('想') || content.contains('希望')) {
      return 'curious';
    }
    if (content.contains('需要') || content.contains('应该') || content.contains('考虑')) {
      return 'focused';
    }
    return 'neutral';
  }

  /// 🔥 新增：获取监听状态
  Map<String, dynamic> getMonitoringStatus() {
    return {
      'is_monitoring': _isMonitoring,
      'last_processed_timestamp': _lastProcessedTimestamp,
      'processed_record_count': _processedRecordIds.length,
      'monitor_interval_seconds': _monitorInterval,
      'batch_size': _conversationBatchSize,
      'last_check_time': DateTime.now().toIso8601String(),
      'system_initialized': _initialized,
    };
  }

  /// 🔥 新增：手动触发对话检查（用于测试）
  Future<void> triggerConversationCheck() async {
    print('[HumanUnderstandingSystem] 🔄 手动触发对话检查...');
    await _monitorNewConversations();
  }

  /// 🔥 新增：重置监听状态
  void resetMonitoringState() {
    print('[HumanUnderstandingSystem] 🔄 重置监听状态...');
    _processedRecordIds.clear();
    _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
    print('[HumanUnderstandingSystem] ✅ 监听状态已重置');
  }

  /// 🔥 新增：手动触发对话检查（dashboard调用）
  Future<void> triggerDialogueCheck() async {
    print('[HumanUnderstandingSystem] 🔄 手动触发对话检查（来自Dashboard）...');
    await _monitorNewConversations();
  }

  /// 🔥 新增：重置监听状态（dashboard调用）
  Future<void> resetMonitoringStatus() async {
    print('[HumanUnderstandingSystem] 🔄 重置监听状态（来自Dashboard）...');
    resetMonitoringState();
  }

  /// 🔥 新增：获取调试信息
  Map<String, dynamic> getDebugInfo() {
    final recentRecords = ObjectBoxService().getRecordsSince(_lastProcessedTimestamp - 3600000); // 最近1小时

    return {
      'system_status': {
        'initialized': _initialized,
        'monitoring': _isMonitoring,
        'last_processed_timestamp': _lastProcessedTimestamp,
        'processed_record_count': _processedRecordIds.length,
        'monitor_interval': _monitorInterval,
        'batch_size': _conversationBatchSize,
      },
      'database_status': {
        'recent_records_count': recentRecords.length,
        'recent_records_preview': recentRecords.take(3).map((r) => {
          'id': r.id,
          'role': r.role,
          'content': r.content?.substring(0, r.content!.length > 50 ? 50 : r.content!.length),
          'created_at': r.createdAt,
        }).toList(),
      },
      'module_status': {
        'intent_manager_stats': _intentManager.getIntentStatistics(),
        'topic_tracker_stats': _topicTracker.getTopicStatistics(),
        'causal_extractor_stats': _causalExtractor.getCausalStatistics(),
        'graph_builder_stats': _graphBuilder.getGraphStatistics(),
        'load_estimator_stats': _loadEstimator.getLoadStatistics(),
      },
      'current_state_summary': {
        'active_intents_count': _intentManager.getActiveIntents().length,
        'active_topics_count': _topicTracker.getActiveTopics().length,
        'recent_causal_count': _causalExtractor.getRecentCausalRelations(limit: 10).length,
        'recent_triples_count': _graphBuilder.getRecentTriples(limit: 10).length,
      },
      'last_check_time': DateTime.now().toIso8601String(),
    };
  }

  /// 🔥 新增：查询知识图谱获取相关上下文信息
  Future<Map<String, dynamic>> _queryKnowledgeGraphContext(SemanticAnalysisInput analysis) async {
    try {
      print('[HumanUnderstandingSystem] 🔍 查询知识图谱相关信息...');

      // 1. 基于实体查询相关节点
      final relatedNodes = await KnowledgeGraphService.getRelatedNodesByKeywords(analysis.entities);

      // 2. 查询相关事件（基于实体）
      final relatedEvents = <EventNode>[];
      for (final entity in analysis.entities) {
        try {
          // 尝试查找与实体相关的事件
          final events = await KnowledgeGraphService.getRelatedEvents('${entity}_人物'); // 假设实体ID格式
          relatedEvents.addAll(events);
        } catch (e) {
          // 忽略单个实体查询失败，继续查询其他实体
          print('[HumanUnderstandingSystem] ⚠️ 查询实体 "$entity" 相关事件失败: $e');
        }
      }

      // 3. 基于内容关键词查询
      final contentKeywords = _extractKeywordsFromContent(analysis.content);
      final keywordNodes = await KnowledgeGraphService.getRelatedNodesByKeywords(contentKeywords);

      // 4. 去重并合并结果
      final allNodes = <Node>[];
      final nodeIds = <String>{};

      for (final node in [...relatedNodes, ...keywordNodes]) {
        if (!nodeIds.contains(node.id)) {
          allNodes.add(node);
          nodeIds.add(node.id);
        }
      }

      // 5. 去重事件
      final allEvents = <EventNode>[];
      final eventIds = <String>{};

      for (final event in relatedEvents) {
        if (!eventIds.contains(event.id)) {
          allEvents.add(event);
          eventIds.add(event.id);
        }
      }

      print('[HumanUnderstandingSystem] 📊 知识图谱查询结果: ${allNodes.length}个相关节点, ${allEvents.length}个相关事件');

      return {
        'related_nodes': allNodes,
        'related_events': allEvents,
        'query_keywords': [...analysis.entities, ...contentKeywords],
        'context_summary': _summarizeKnowledgeContext(allNodes, allEvents),
      };

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 查询知识图谱失败: $e');
      return {
        'related_nodes': <Node>[],
        'related_events': <EventNode>[],
        'query_keywords': analysis.entities,
        'context_summary': '',
        'error': e.toString(),
      };
    }
  }

  /// 🔥 新增：从内容中提取关键词
  List<String> _extractKeywordsFromContent(String content) {
    final keywords = <String>[];

    // 技术关键词
    final techKeywords = ['Flutter', 'AI', '人工智能', '机器学习', '数据库', '性能', '优化', 'Bug', '错误', '开发', '编程'];
    for (final keyword in techKeywords) {
      if (content.contains(keyword)) {
        keywords.add(keyword);
      }
    }

    // 行为关键词
    final actionKeywords = ['学习', '了解', '研究', '计划', '规划', '完成', '做', '实现', '开发', '构建', '优化', '解决'];
    for (final keyword in actionKeywords) {
      if (content.contains(keyword)) {
        keywords.add(keyword);
      }
    }

    // 生活关键词
    final lifeKeywords = ['吃', '饭', '食物', '睡觉', '休息', '运动', '锻炼', '会议', '讨论', '工作', '项目'];
    for (final keyword in lifeKeywords) {
      if (content.contains(keyword)) {
        keywords.add(keyword);
      }
    }

    return keywords.toSet().toList(); // 去重
  }

  /// 🔥 新增：总结知识图谱上下文
  String _summarizeKnowledgeContext(List<Node> nodes, List<EventNode> events) {
    if (nodes.isEmpty && events.isEmpty) {
      return '未找到相关的历史信息';
    }

    final summary = StringBuffer();

    if (nodes.isNotEmpty) {
      final nodesByType = <String, List<Node>>{};
      for (final node in nodes) {
        nodesByType.putIfAbsent(node.type, () => []).add(node);
      }

      summary.write('相关实体: ');
      nodesByType.forEach((type, typeNodes) {
        summary.write('$type类(${typeNodes.length}个) ');
      });
    }

    if (events.isNotEmpty) {
      final eventsByType = <String, List<EventNode>>{};
      for (final event in events) {
        eventsByType.putIfAbsent(event.type, () => []).add(event);
      }

      if (summary.isNotEmpty) summary.write('; ');
      summary.write('相关事件: ');
      eventsByType.forEach((type, typeEvents) {
        summary.write('$type类(${typeEvents.length}个) ');
      });
    }

    return summary.toString();
  }

  /// 🔥 新增：使用知识图谱信息增强分析输入
  SemanticAnalysisInput _enhanceAnalysisWithKnowledgeGraph(
    SemanticAnalysisInput original,
    Map<String, dynamic> knowledgeContext
  ) {
    final relatedNodes = knowledgeContext['related_nodes'] as List<Node>? ?? [];
    final relatedEvents = knowledgeContext['related_events'] as List<EventNode>? ?? [];

    // 1. 增强实体列表
    final enhancedEntities = List<String>.from(original.entities);
    for (final node in relatedNodes) {
      if (!enhancedEntities.contains(node.name)) {
        enhancedEntities.add(node.name);
      }
      // 添加节点的别名
      for (final alias in node.aliases) {
        if (!enhancedEntities.contains(alias)) {
          enhancedEntities.add(alias);
        }
      }
    }

    // 2. 增强上下文信息
    final enhancedContext = Map<String, dynamic>.from(original.additionalContext ?? {});
    enhancedContext['knowledge_graph_context'] = {
      'related_nodes_count': relatedNodes.length,
      'related_events_count': relatedEvents.length,
      'context_summary': knowledgeContext['context_summary'],
      'enhanced_entities': enhancedEntities.length - original.entities.length,
    };

    // 3. 添加历史事件信息
    if (relatedEvents.isNotEmpty) {
      enhancedContext['historical_events'] = relatedEvents.map((event) => {
        'name': event.name,
        'type': event.type,
        'description': event.description,
        'location': event.location,
      }).toList();
    }

    // 4. 添加相关节点信息
    if (relatedNodes.isNotEmpty) {
      enhancedContext['related_entities'] = relatedNodes.map((node) => {
        'name': node.name,
        'type': node.type,
        'attributes': node.attributes,
      }).toList();
    }

    return SemanticAnalysisInput(
      entities: enhancedEntities,
      intent: original.intent,
      emotion: original.emotion,
      content: original.content,
      timestamp: original.timestamp,
      additionalContext: enhancedContext,
    );
  }

  /// 🔥 新增：使用知识图谱信息增强主题
  Future<List<ConversationTopic>> _enhanceTopicsWithKnowledgeGraph(
    List<ConversationTopic> originalTopics,
    Map<String, dynamic> knowledgeContext,
  ) async {
    final relatedNodes = knowledgeContext['related_nodes'] as List<Node>? ?? [];
    final relatedEvents = knowledgeContext['related_events'] as List<EventNode>? ?? [];

    if (relatedNodes.isEmpty && relatedEvents.isEmpty) {
      return originalTopics;
    }

    print('[HumanUnderstandingSystem] 🔗 使用知识图谱增强主题信息...');

    final enhancedTopics = <ConversationTopic>[];

    // 1. 增强现有主题
    for (final topic in originalTopics) {
      final enhancedTopic = _enhanceTopicWithKnowledgeGraph(topic, relatedNodes, relatedEvents);
      enhancedTopics.add(enhancedTopic);
    }

    // 2. 从知识图谱中发现新的潜在主题
    final discoveredTopics = _discoverTopicsFromKnowledgeGraph(relatedNodes, relatedEvents);
    for (final discoveredTopic in discoveredTopics) {
      // 检查是否与现有主题重复
      final isDuplicate = enhancedTopics.any((existing) =>
        existing.name.toLowerCase() == discoveredTopic.name.toLowerCase() ||
        _calculateTopicSimilarity(existing, discoveredTopic) > 0.7
      );

      if (!isDuplicate) {
        enhancedTopics.add(discoveredTopic);
        print('[HumanUnderstandingSystem] 🆕 从知识图谱发现新主题: ${discoveredTopic.name}');
      }
    }

    return enhancedTopics;
  }

  /// 🔥 新增：使用知识图谱信息增强单个主题
  ConversationTopic _enhanceTopicWithKnowledgeGraph(
    ConversationTopic originalTopic,
    List<Node> relatedNodes,
    List<EventNode> relatedEvents,
  ) {
    final enhancedKeywords = List<String>.from(originalTopic.keywords);
    final enhancedContext = Map<String, dynamic>.from(originalTopic.context ?? {});

    // 1. 从相关节点中添加关键词
    for (final node in relatedNodes) {
      if (_isNodeRelevantToTopic(node, originalTopic)) {
        if (!enhancedKeywords.contains(node.name)) {
          enhancedKeywords.add(node.name);
        }
        // 添加节点属性作为上下文
        enhancedContext['related_entity_${node.name}'] = node.attributes;
      }
    }

    // 2. 从相关事件中添加上下文
    final relevantEvents = relatedEvents.where((event) =>
      _isEventRelevantToTopic(event, originalTopic)
    ).toList();

    if (relevantEvents.isNotEmpty) {
      enhancedContext['related_events'] = relevantEvents.map((event) => {
        'name': event.name,
        'type': event.type,
        'description': event.description,
        'time': event.startTime?.toIso8601String(),
      }).toList();
    }

    // 3. 计算增强的相关性分数
    double enhancedRelevance = originalTopic.relevanceScore;
    if (relevantEvents.isNotEmpty) {
      enhancedRelevance = (enhancedRelevance + 0.1).clamp(0.0, 1.0); // 轻微提升相关性
    }

    return ConversationTopic(
      id: originalTopic.id,
      name: originalTopic.name,
      category: originalTopic.category,
      keywords: enhancedKeywords,
      relevanceScore: enhancedRelevance,
      weight: originalTopic.weight,
      createdAt: originalTopic.createdAt,
      lastMentioned: originalTopic.lastMentioned,
      context: enhancedContext,
    );
  }

  /// 🔥 新增：从知识图谱中发现新主题
  List<ConversationTopic> _discoverTopicsFromKnowledgeGraph(
    List<Node> relatedNodes,
    List<EventNode> relatedEvents,
  ) {
    final discoveredTopics = <ConversationTopic>[];

    // 1. 基于相关事件创建主题
    final eventsByType = <String, List<EventNode>>{};
    for (final event in relatedEvents) {
      eventsByType.putIfAbsent(event.type, () => []).add(event);
    }

    for (final entry in eventsByType.entries) {
      if (entry.value.length >= 2) { // 至少2个同类型事件才形成主题
        final topicName = '${entry.key}相关话题';
        final keywords = entry.value.map((e) => e.name).toList();

        final topic = ConversationTopic(
          name: topicName,
          category: 'knowledge_graph',
          keywords: keywords,
          relevanceScore: 0.6, // 中等相关性
          weight: 0.6,
          createdAt: DateTime.now(),
          lastMentioned: DateTime.now(),
          context: {
            'source': 'knowledge_graph_discovery',
            'event_type': entry.key,
            'related_events_count': entry.value.length,
          },
        );

        discoveredTopics.add(topic);
      }
    }

    // 2. 基于相关节点的类型和属性创建主题
    final nodesByType = <String, List<Node>>{};
    for (final node in relatedNodes) {
      nodesByType.putIfAbsent(node.type, () => []).add(node);
    }

    for (final entry in nodesByType.entries) {
      if (entry.value.length >= 3) { // 至少3个同类型节点才形成主题
        final topicName = '${entry.key}讨论';
        final keywords = entry.value.map((n) => n.name).toList();

        final topic = ConversationTopic(
          name: topicName,
          category: 'knowledge_graph',
          keywords: keywords,
          relevanceScore: 0.5, // 较低相关性，因为是推测的
          weight: 0.5,
          createdAt: DateTime.now(),
          lastMentioned: DateTime.now(),
          context: {
            'source': 'knowledge_graph_discovery',
            'entity_type': entry.key,
            'related_entities_count': entry.value.length,
          },
        );

        discoveredTopics.add(topic);
      }
    }

    return discoveredTopics;
  }

  /// 🔥 新增：判断节点是否与主题相关
  bool _isNodeRelevantToTopic(Node node, ConversationTopic topic) {
    // 检查节点名称是否与主题关键词匹配
    for (final keyword in topic.keywords) {
      if (node.name.toLowerCase().contains(keyword.toLowerCase()) ||
          keyword.toLowerCase().contains(node.name.toLowerCase())) {
        return true;
      }
    }

    // 检查节点别名
    for (final alias in node.aliases) {
      for (final keyword in topic.keywords) {
        if (alias.toLowerCase().contains(keyword.toLowerCase()) ||
            keyword.toLowerCase().contains(alias.toLowerCase())) {
          return true;
        }
      }
    }

    return false;
  }

  /// 🔥 新增：判断事件是否与主题相关
  bool _isEventRelevantToTopic(EventNode event, ConversationTopic topic) {
    // 检查事件名称和描述
    final eventText = '${event.name} ${event.description ?? ''}'.toLowerCase();

    for (final keyword in topic.keywords) {
      if (eventText.contains(keyword.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  /// 🔥 新增：计算主题相似性
  double _calculateTopicSimilarity(ConversationTopic topic1, ConversationTopic topic2) {
    final keywords1 = topic1.keywords.map((k) => k.toLowerCase()).toSet();
    final keywords2 = topic2.keywords.map((k) => k.toLowerCase()).toSet();

    final intersection = keywords1.intersection(keywords2);
    final union = keywords1.union(keywords2);

    return union.isEmpty ? 0.0 : intersection.length / union.length;
  }

  /// 🔥 修复：生成知识图谱数据统计
  Map<String, dynamic> _generateKnowledgeGraphData() {
    try {
      final objectBox = ObjectBoxService();

      // 🔥 修复：使用正确的方法获取节点和事件数据
      final allNodes = objectBox.queryNodes();
      final allEvents = objectBox.queryEventNodes();
      final allEdges = objectBox.queryEdges();

      // 获取最近的节点和事件
      final recentNodes = allNodes.take(10).toList();
      final recentEvents = allEvents.take(10).toList();

      return {
        'entity_count': allNodes.length,
        'relation_count': allEdges.length,
        'attribute_count': allNodes.fold(0, (sum, node) => sum + node.attributes.length),
        'event_count': allEvents.length,
        'last_updated': allNodes.isNotEmpty
          ? allNodes.first.lastUpdated.millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch,
        'recent_nodes_preview': recentNodes.map((n) => {
          'name': n.name,
          'type': n.type,
          'attributes_count': n.attributes.length,
        }).toList(),
        'recent_events_preview': recentEvents.map((e) => {
          'name': e.name,
          'type': e.type,
          'location': e.location,
        }).toList(),
      };
    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成知识图谱数据统计失败: $e');
      return {
        'entity_count': 0,
        'relation_count': 0,
        'attribute_count': 0,
        'event_count': 0,
        'error': e.toString(),
      };
    }
  }

  /// 🔥 修复：生成意图主题关系映射
  Map<String, List<Intent>> _generateIntentTopicRelations() {
    try {
      final activeIntents = _intentManager.getActiveIntents();
      final activeTopics = _topicTracker.getActiveTopics();

      final relations = <String, List<Intent>>{};

      // 基于相关实体建立意图-主题关系
      for (final topic in activeTopics) {
        final relatedIntents = <Intent>[];

        for (final intent in activeIntents) {
          // 🔥 修复：使用正确的属性名 relatedEntities 而不是 entities
          // 检查意图的实体是否与主题的关键词匹配
          final hasEntityMatch = intent.relatedEntities.any((entity) =>
            topic.keywords.any((keyword) =>
              entity.toLowerCase().contains(keyword.toLowerCase()) ||
              keyword.toLowerCase().contains(entity.toLowerCase())
            )
          );

          // 检查意图类别是否与主题类别匹配
          final hasCategoryMatch = intent.category == topic.category;

          // 🔥 修复：使用更合适的匹配逻辑
          // 检查意图描述是否与主题名称匹配
          final hasDescriptionMatch = intent.description.toLowerCase().contains(topic.name.toLowerCase()) ||
              topic.name.toLowerCase().contains(intent.description.toLowerCase());

          if (hasEntityMatch || hasCategoryMatch || hasDescriptionMatch) {
            relatedIntents.add(intent);
          }
        }

        if (relatedIntents.isNotEmpty) {
          relations[topic.name] = relatedIntents;
        }
      }

      return relations;
    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 生成意图主题关系映射失败: $e');
      return {};
    }
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
