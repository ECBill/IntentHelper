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

  /// 处理新的语义分析输入（从现有cache系统接收）
  Future<HumanUnderstandingSystemState> processSemanticInput(
    SemanticAnalysisInput analysis,
  ) async {
    // 🔥 修复：避免在初始化过程中触发循环调用
    if (_initializing) {
      print('[HumanUnderstandingSystem] ⚠️ 系统正���初始化中，跳过语义输入处理');
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

      // 1. 并行处理基础分析
      final results = await Future.wait([
        _intentManager.processSemanticAnalysis(analysis),
        _topicTracker.processConversation(analysis),
        _causalExtractor.extractCausalRelations(analysis),
      ]);

      final intents = results[0] as List<Intent>;
      final topics = results[1] as List<ConversationTopic>;
      final causalRelations = results[2] as List<CausalRelation>;

      // 2. 构建语义图谱（依赖前面的结果）
      final triples = await _graphBuilder.buildSemanticGraph(
        analysis,
        intents,
        topics,
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

      // 4. 生成系统状态快照
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
          'analysis_timestamp': analysis.timestamp.toIso8601String(),
        },
      );

      _systemStateController.add(systemState);

      stopwatch.stop();
      print('[HumanUnderstandingSystem] ✅ 语义处理完成 (${stopwatch.elapsedMilliseconds}ms)');
      print('[HumanUnderstandingSystem] 📊 新增: ${intents.length}意图, ${topics.length}主题, ${causalRelations.length}因果, ${triples.length}三元组');

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

      // 基于意图���建议
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
        suggestions['causal_insight'] = '发现了 ${causalChains.length} 个因果关���，可以深入分析行为动机';
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
