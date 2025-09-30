/// 人类理解系统主服务
/// 整合所有子模块，提供统一的类人理解能力

import 'dart:async';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/intent_lifecycle_manager.dart';
import 'package:app/services/conversation_topic_tracker.dart';
import 'package:app/services/causal_chain_extractor.dart';
import 'package:app/services/semantic_graph_builder.dart';
import 'package:app/services/cognitive_load_estimator.dart';
import 'package:app/services/intelligent_reminder_manager.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/services/natural_language_reminder_service.dart';
import 'package:app/services/knowledge_graph_manager.dart'; // 🔥 新增：导入知识图谱管理器

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
  final IntelligentReminderManager _reminderManager = IntelligentReminderManager();
  final NaturalLanguageReminderService _naturalReminderService = NaturalLanguageReminderService();
  final KnowledgeGraphManager _knowledgeGraphManager = KnowledgeGraphManager(); // 🔥 新增：知识图谱管理器实例

  // 🔥 知识图谱数据缓存
  Map<String, dynamic>? _cachedKnowledgeGraphData;
  DateTime? _lastKnowledgeGraphUpdate;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  // 系统状态
  final StreamController<HumanUnderstandingSystemState> _systemStateController = StreamController.broadcast();
  Timer? _stateUpdateTimer;
  Timer? _conversationMonitorTimer;
  bool _initialized = false;
  bool _isMonitoring = false;
  bool _initializing = false;

  // 对话监听相关
  int _lastProcessedTimestamp = 0;
  final Set<int> _processedRecordIds = {};
  static const int _monitorInterval = 5;
  static const int _conversationBatchSize = 5;

  // 记录最近一次主题追踪结果（字符串列表）
  List<String> _lastActiveTopics = [];

  /// 系统状态更新流
  Stream<HumanUnderstandingSystemState> get systemStateUpdates => _systemStateController.stream;

  /// 初始化整个理解系统
  Future<void> initialize() async {
    if (_initialized) {
      print('[HumanUnderstandingSystem] ✅ 系统已初始化');
      return;
    }

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
        _knowledgeGraphManager.initialize(), // 🔥 新增：初始化知识图谱管理器
      ]);

      print('[HumanUnderstandingSystem] ✅ 所有子模块初始化完成');

      // 启动监听机制
      _startConversationMonitoring();
      _startPeriodicStateUpdate();

      _initialized = true;
      _initializing = false;
      print('[HumanUnderstandingSystem] ✅ 人类理解系统核心初始化完成');

      // 延迟处理历史对话
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

  /// 异步处理初始对话
  void _processInitialConversationsAsync() async {
    print('[HumanUnderstandingSystem] 📚 异步检查现有对话数据...');

    try {
      final cutoffTime = DateTime.now().subtract(Duration(minutes: 30)).millisecondsSinceEpoch;
      final recentRecords = ObjectBoxService().getRecordsSince(cutoffTime);

      if (recentRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 暂无最近对话记录');
        _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
        await _createInitialTestData();
        return;
      }

      print('[HumanUnderstandingSystem] 📊 找到 ${recentRecords.length} 条历史对话');
      final limitedRecords = recentRecords.take(3).toList();
      await _processBatchConversations(limitedRecords);
      _markRecordsAsProcessed(limitedRecords);
      _updateProcessedTimestamp();

      print('[HumanUnderstandingSystem] ✅ 历史对话异步处理完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 异步处理历史对话失败: $e');
      _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
      await _createInitialTestData();
    }
  }

  /// 启动对话监听机制
  void _startConversationMonitoring() {
    if (_isMonitoring) {
      print('[HumanUnderstandingSystem] ⚠️ 监听已在运行中');
      return;
    }

    print('[HumanUnderstandingSystem] 👂 启动对话监听机制...');
    _conversationMonitorTimer = Timer.periodic(Duration(seconds: _monitorInterval), (timer) {
      _monitorNewConversations();
    });

    _isMonitoring = true;
    print('[HumanUnderstandingSystem] ✅ 对话监听已启动');
  }

  /// 监听新对话
  Future<void> _monitorNewConversations() async {
    if (!_initialized || !_isMonitoring) return;

    try {
      final newRecords = ObjectBoxService().getRecordsSince(_lastProcessedTimestamp);
      if (newRecords.isEmpty) return;

      print('[HumanUnderstandingSystem] 📊 发现 ${newRecords.length} 条新对话记录');

      final unprocessedRecords = newRecords.where((record) {
        return record.id != 0 && !_processedRecordIds.contains(record.id);
      }).toList();

      if (unprocessedRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 所有记录已处理过');
        return;
      }

      print('[HumanUnderstandingSystem] 🔄 处理 ${unprocessedRecords.length} 条新记录');
      unprocessedRecords.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
      final recentRecords = unprocessedRecords.take(_conversationBatchSize).toList();

      final meaningfulRecords = _filterMeaningfulRecords(recentRecords);
      if (meaningfulRecords.isEmpty) {
        print('[HumanUnderstandingSystem] ℹ️ 没有实质性对话内容');
        _markRecordsAsProcessed(recentRecords);
        return;
      }

      await _processBatchConversations(meaningfulRecords);
      _markRecordsAsProcessed(recentRecords);
      _updateProcessedTimestamp();

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 监听新对话失败: $e');
    }
  }

  /// 过滤有意义的记录
  List<dynamic> _filterMeaningfulRecords(List<dynamic> records) {
    return records.where((record) {
      final content = record.content?.toString() ?? '';
      if (content.trim().isEmpty) return false;
      if (content.length < 2) return false;
      if (_isSystemMessage(content)) return false;
      return true;
    }).toList();
  }

  /// 判断是否为系统消息
  bool _isSystemMessage(String content) {
    final systemPatterns = [
      '录音开始', '录音结束', '系统启动', '连接成功', '断开连接',
      '开始录音', '停止录音', '[系统]', '检测到', '正在处理'
    ];
    return systemPatterns.any((pattern) => content.contains(pattern));
  }

  /// 标记记录为已处理
  void _markRecordsAsProcessed(List<dynamic> records) {
    for (final record in records) {
      if (record.id != 0) {
        _processedRecordIds.add(record.id);
      }
    }

    if (_processedRecordIds.length > 500) {
      final sortedIds = _processedRecordIds.toList()..sort();
      _processedRecordIds.clear();
      _processedRecordIds.addAll(sortedIds.skip(250));
    }
  }

  /// 更新处理时间戳
  void _updateProcessedTimestamp() {
    _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 批量处理对话记录
  Future<void> _processBatchConversations(List<dynamic> records) async {
    print('[HumanUnderstandingSystem] 📦 开始批量处理 ${records.length} 条对话...');

    try {
      final conversationContext = _buildConversationContext(records);
      if (conversationContext.trim().isEmpty) {
        print('[HumanUnderstandingSystem] ⚠️ 对话上下文为空，跳过处理');
        return;
      }

      print('[HumanUnderstandingSystem] 📝 对话上下文长度: ${conversationContext.length}');
      final semanticInput = _createSemanticAnalysisFromContext(conversationContext, records);
      await processSemanticInput(semanticInput);
      print('[HumanUnderstandingSystem] ✅ 批量对话处理完成');

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 批量处理对话失败: $e');
    }
  }

  /// 构建对话上下文
  String _buildConversationContext(List<dynamic> records) {
    final contextBuilder = StringBuffer();

    for (final record in records) {
      final role = record.role ?? 'unknown';
      final content = record.content ?? '';
      final createdAt = record.createdAt;

      if (content.trim().isNotEmpty) {
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

  /// 从对话上下文创建语义分析输入
  SemanticAnalysisInput _createSemanticAnalysisFromContext(String context, List<dynamic> records) {
    final allContent = records
        .map((r) => r.content?.toString() ?? '')
        .where((content) => content.trim().isNotEmpty)
        .join(' ');

    final entities = _extractBasicEntities(allContent);
    final intent = _inferBasicIntent(allContent);
    final emotion = _inferBasicEmotion(allContent);

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

  /// 创建初始测试数据
  Future<void> _createInitialTestData() async {
    print('[HumanUnderstandingSystem] 🧪 创建初始测试数据...');

    try {
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
        await Future.delayed(Duration(milliseconds: 100));
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

    // 直接获取知识图谱数据
    final knowledgeGraphData = _knowledgeGraphManager.getLastResult() ?? {};
    final intentTopicRelations = _generateIntentTopicRelations();

    return HumanUnderstandingSystemState(
      activeIntents: _intentManager.getActiveIntents(),
      activeTopics: _topicTracker.getActiveTopics(),
      recentCausalChains: _causalExtractor.getRecentCausalRelations(limit: 5),
      recentTriples: _graphBuilder.getRecentTriples(limit: 10),
      currentCognitiveLoad: currentLoad,
      knowledgeGraphData: knowledgeGraphData,
      intentTopicRelations: intentTopicRelations,
      systemMetrics: {
        'request_type': 'current_state',
        'system_initialized': _initialized,
      },
    );
  }


  /// 格式化事件日期
  String _formatEventDate(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      return '今天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}周前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  /// 生成意图主题关系映射
  Map<String, List<Intent>> _generateIntentTopicRelations() {
    try {
      final activeIntents = _intentManager.getActiveIntents();
      final activeTopics = _topicTracker.getActiveTopics();
      final relations = <String, List<Intent>>{};

      for (final topic in activeTopics) {
        final relatedIntents = <Intent>[];

        for (final intent in activeIntents) {
          final hasEntityMatch = intent.relatedEntities.any((entity) =>
              topic.keywords.any((keyword) =>
              entity.toLowerCase().contains(keyword.toLowerCase()) ||
                  keyword.toLowerCase().contains(entity.toLowerCase())
              )
          );

          final hasCategoryMatch = intent.category == topic.category;
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

  /// 处理新的语义分析输入
  Future<HumanUnderstandingSystemState> processSemanticInput(SemanticAnalysisInput analysis) async {
    if (_initializing) {
      print('[HumanUnderstandingSystem] ⚠️ 系统正在初始化中，跳过语义输入处理');
      return _createDefaultState('initializing');
    }

    if (!_initialized) {
      print('[HumanUnderstandingSystem] ⚠️ 系统未初始化，跳过语义输入处理');
      return _createDefaultState('not_initialized');
    }

    print('[HumanUnderstandingSystem] 🧠 处理语义输入: "${analysis.content.substring(0, analysis.content.length > 50 ? 50 : analysis.content.length)}..."');

    try {
      final stopwatch = Stopwatch()..start();

      // 基础处理
      final results = await Future.wait([
        _intentManager.processSemanticAnalysis(analysis),
        _topicTracker.processConversation(analysis),
        _causalExtractor.extractCausalRelations(analysis),
        _reminderManager.processSemanticAnalysis(analysis),
        _naturalReminderService.processSemanticAnalysis(analysis),
      ]);

      // 🔥 新增：主题追踪后自动同步知识图谱
      await _knowledgeGraphManager.updateActiveTopics(
        _topicTracker.getActiveTopics().map((t) => t.name).toList(),
      );

      final intents = results[0] as List<Intent>;
      final topics = results[1] as List<ConversationTopic>;
      final causalRelations = results[2] as List<CausalRelation>;

      // 构建语义图谱
      final triples = await _graphBuilder.buildSemanticGraph(
        analysis,
        intents,
        topics,
        causalRelations,
      );

      // 评估认知负载
      final cognitiveLoad = await _loadEstimator.assessCognitiveLoad(
        activeIntents: _intentManager.getActiveIntents(),
        activeTopics: _topicTracker.getActiveTopics(),
        backgroundTopics: _topicTracker.getBackgroundTopics(),
        currentEmotion: analysis.emotion,
        topicSwitchRate: _topicTracker.calculateTopicSwitchRate(),
        lastConversationContent: analysis.content,
        additionalContext: analysis.additionalContext,
      );

      // 生成系统状态快照
      final reminderStats = _naturalReminderService.getStatistics();
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
          'reminder_statistics': reminderStats,
          'analysis_timestamp': analysis.timestamp.toIso8601String(),
        },
      );

      _systemStateController.add(systemState);

      // 🔥 修复：不再在每次语义处理后清除缓存，改为智能更新策略
      // 只有在有新的实体或事件生成时才清除缓存
      if (intents.isNotEmpty || topics.isNotEmpty || causalRelations.isNotEmpty || triples.isNotEmpty) {
        print('[HumanUnderstandingSystem] 🔄 检测到新的语义数据，将在下次请求时更新知识图谱缓存');
        // 不立即清除，而是标记为需要更新
        _lastKnowledgeGraphUpdate = null; // 这将在下次调用时触发重新生成
      }

      stopwatch.stop();
      print('[HumanUnderstandingSystem] ✅ 语义处理完成 (${stopwatch.elapsedMilliseconds}ms)');

      return systemState;

    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 处理语义输入失败: $e');
      return _createDefaultState('error');
    }
  }

  /// 创建默认状态
  HumanUnderstandingSystemState _createDefaultState(String status) {
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
      systemMetrics: {'status': status},
    );
  }

  /// 基础实体提取
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

  /// 基础意图推断
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

  /// 基础情绪推断
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

  /// 搜索相关信息
  Future<Map<String, dynamic>> searchRelevantInfo(String query) async {
    try {
      final results = <String, dynamic>{};

      final relatedIntents = _intentManager.searchIntents(query);
      results['intents'] = relatedIntents.map((i) => i.toJson()).toList();

      final relatedTopics = _topicTracker.searchTopics(query);
      results['topics'] = relatedTopics.map((t) => t.toJson()).toList();

      final relatedCausal = _causalExtractor.searchCausalRelations(query);
      results['causal_relations'] = relatedCausal.map((c) => c.toJson()).toList();

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
      _stateUpdateTimer?.cancel();
      _conversationMonitorTimer?.cancel();

      _intentManager.dispose();
      _topicTracker.dispose();
      _causalExtractor.dispose();
      _graphBuilder.dispose();
      _loadEstimator.dispose();

      _initialized = false;

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

  /// 获取智能建议
  Map<String, dynamic> getIntelligentSuggestions() {
    try {
      final currentState = getCurrentState();
      final suggestions = <String, dynamic>{};

      final activeIntents = currentState.activeIntents;
      if (activeIntents.length > 3) {
        suggestions['intent_management'] = '当前有 ${activeIntents.length} 个活跃意图，建议优先完成重要意图';
      }

      suggestions['cognitive_load'] = currentState.currentCognitiveLoad.recommendation;

      final activeTopics = currentState.activeTopics;
      if (activeTopics.length > 5) {
        suggestions['topic_focus'] = '当前讨论了 ${activeTopics.length} 个主题，建议专注于核心主题';
      }

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

    if (state.currentCognitiveLoad.level == CognitiveLoadLevel.overload) {
      actions.add('立即减少活跃任务数量');
    } else if (state.currentCognitiveLoad.level == CognitiveLoadLevel.high) {
      actions.add('优先处理紧急重要的意图');
    }

    final clarifyingIntents = state.activeIntents.where(
            (intent) => intent.state == IntentLifecycleState.clarifying
    ).toList();
    if (clarifyingIntents.isNotEmpty) {
      actions.add('澄清 ${clarifyingIntents.length} 个需要明确的意图');
    }

    final highRelevanceTopics = state.activeTopics.where(
            (topic) => topic.relevanceScore > 0.8
    ).toList();
    if (highRelevanceTopics.isNotEmpty) {
      actions.add('深入讨论高相关性主题：${highRelevanceTopics.map((t) => t.name).take(2).join('、')}');
    }

    return actions;
  }

  /// 获取监听状态
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

  /// 手动触发对话检查
  Future<void> triggerConversationCheck() async {
    print('[HumanUnderstandingSystem] 🔄 手动触发对话检查...');
    await _monitorNewConversations();
  }

  /// 重置监听状态
  void resetMonitoringState() {
    print('[HumanUnderstandingSystem] 🔄 重置监听状态...');
    _processedRecordIds.clear();
    _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
    print('[HumanUnderstandingSystem] ✅ 监听状态已重置');
  }

  /// 手动触发对话检查（dashboard调用）
  Future<void> triggerDialogueCheck() async {
    print('[HumanUnderstandingSystem] 🔄 手动触发对话检查（来自Dashboard）...');
    await _monitorNewConversations();
  }

  /// 重置监听状态（dashboard调用）
  Future<void> resetMonitoringStatus() async {
    print('[HumanUnderstandingSystem] 🔄 重置监听状态（来自Dashboard）...');
    resetMonitoringState();
  }

  /// 获取调试信息
  Map<String, dynamic> getDebugInfo() {
    final recentRecords = ObjectBoxService().getRecordsSince(_lastProcessedTimestamp - 3600000);

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

  /// 释放所有资源
  void dispose() {
    print('[HumanUnderstandingSystem] 🔄 开始释放人类理解系统资源...');

    try {
      _stateUpdateTimer?.cancel();
      _stateUpdateTimer = null;

      _conversationMonitorTimer?.cancel();
      _conversationMonitorTimer = null;

      if (!_systemStateController.isClosed) {
        _systemStateController.close();
      }

      _intentManager.dispose();
      _topicTracker.dispose();
      _causalExtractor.dispose();
      _graphBuilder.dispose();
      _loadEstimator.dispose();
      _reminderManager.dispose();
      _naturalReminderService.dispose();

      _cachedKnowledgeGraphData = null;
      _lastKnowledgeGraphUpdate = null;
      _processedRecordIds.clear();

      _initialized = false;
      _isMonitoring = false;
      _initializing = false;

      print('[HumanUnderstandingSystem] ✅ 人类理解系统资源释放完成');
    } catch (e) {
      print('[HumanUnderstandingSystem] ❌ 释放资源时出现错误: $e');
    }
  }

  // 保证为 public 方法
  void refreshKnowledgeGraphCache() {
    _knowledgeGraphManager.refreshCache();
    if (_lastActiveTopics.isNotEmpty) {
      _knowledgeGraphManager.updateActiveTopics(_lastActiveTopics);
    }
  }

  /// 供UI层同步当前展示的主题（如dashboard主动调用）
  void setActiveTopicsFromUI(List<String> topics) {
    _lastActiveTopics = List.from(topics);
  }

  // 提供只读访问器，便于外部安全获取主题追踪器和知识图谱管理器
  ConversationTopicTracker get topicTracker => _topicTracker;
  KnowledgeGraphManager get knowledgeGraphManager => _knowledgeGraphManager;
}
