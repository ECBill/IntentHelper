import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:app/services/llm.dart';
import 'package:app/services/enhanced_kg_service.dart'; // 🔥 新增：使用重构后的增强知识图谱服务
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/todo_entity.dart'; // 新增：导入todo模型
import 'package:intl/intl.dart'; // 新增：用于时间格式化

/// 缓存项优先级
enum CacheItemPriority {
  low(1),
  medium(2),
  high(3),
  critical(4),
  userProfile(5); // 用户画像最高优先级，永不被替换

  const CacheItemPriority(this.value);
  final int value;
}

/// 缓存项类
class CacheItem {
  final String key;
  final String content; // 自然语言形式的内容
  final double weight; // 添加weight字段
  final CacheItemPriority priority;
  final Set<String> relatedTopics;
  final DateTime createdAt;
  DateTime lastAccessedAt;
  int accessCount;
  double relevanceScore;
  final String category; // 添加category字段
  final dynamic data; // 添加data字段以兼容旧代码

  CacheItem({
    required this.key,
    required this.content,
    required this.priority,
    required this.relatedTopics,
    required this.createdAt,
    required this.relevanceScore,
    this.category = 'general',
    this.data,
  }) : lastAccessedAt = createdAt,
        accessCount = 1,
        weight = 1.0;

  /// 更新访问信息
  void updateAccess() {
    lastAccessedAt = DateTime.now();
    accessCount++;
  }

  /// 计算缓存项的权重（用于替换算法）
  double calculateWeight() {
    final timeFactor = DateTime.now().difference(lastAccessedAt).inMinutes / 60.0;
    final accessFactor = accessCount.toDouble();
    final priorityFactor = priority.value.toDouble();
    final relevanceFactor = relevanceScore;

    // 综合权重算法：优先级 + 相关性 + 访问频率 - 时间衰减
    return (priorityFactor * 2.0 + relevanceFactor + accessFactor * 0.5) / (timeFactor + 1.0);
  }
}

/// 对话关注点检测器
class ConversationFocusDetector {
  static const int _historyLimit = 20; // 增加历��对话数量
  final Queue<String> _conversationHistory = Queue();
  final Set<String> _currentEntities = {};
  final Set<String> _currentTopics = {};
  String _lastEmotion = 'neutral';
  String _currentIntent = 'general_chat';

  // 新增：���������������智能的检测参数
  int _messagesSinceLastUpdate = 0;
  static const int _forceUpdateThreshold = 2; // 降低阈值，每2条消息就可能触发更新
  DateTime? _lastUpdateTime;
  static const Duration _timeBasedUpdateInterval = Duration(minutes: 3); // 每3分钟强制更新

  /// 检测是否需要触发关注点更新
  bool shouldTriggerUpdate(String newText) {
    print('[FocusDetector] 🔍 检测关注点变化');
    print('[FocusDetector] 📝 新输入: "${newText.substring(0, newText.length > 50 ? 50 : newText.length)}..."');
    print('[FocusDetector] �� 当���状态 - 话题数: ${_currentTopics.length}, 实体数: ${_currentEntities.length}');
    print('[FocusDetector] ⏰ 距离上次更新: ${_messagesSinceLastUpdate} 条消息');

    _messagesSinceLastUpdate++;
    bool shouldUpdate = false;

    // 1. 强制更新机制 - 确保缓存系统能够工作
    if (_shouldForceUpdate()) {
      print('[FocusDetector] ⚡ 触发强制更新 (达到阈值)');
      shouldUpdate = true;
    }

    // 2. 检测关键变化
    if (_detectSignificantChange(newText)) {
      print('[FocusDetector] 🔥 检测到重要变化');
      shouldUpdate = true;
    }

    // 3. 降低更新门槛 - 只要有实质内容就分析
    if (newText.trim().length > 5 && _messagesSinceLastUpdate >= 1) {
      print('[FocusDetector] 📈 内容足够，触发分析');
      shouldUpdate = true;
    }

    if (shouldUpdate) {
      _messagesSinceLastUpdate = 0;
      _lastUpdateTime = DateTime.now();
      print('[FocusDetector] ✅ 将���发关注点更新');
    } else {
      print('[FocusDetector] ❌ 暂不触发更新');
    }

    return shouldUpdate;
  }

  /// 强制更新检查
  bool _shouldForceUpdate() {
    // 基于消息数量的强制更新
    if (_messagesSinceLastUpdate >= _forceUpdateThreshold) {
      print('[FocusDetector] 🔄 消息数量达到阈值: $_messagesSinceLastUpdate >= $_forceUpdateThreshold');
      return true;
    }

    // 基于时间的强制更新
    if (_lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate >= _timeBasedUpdateInterval) {
        print('[FocusDetector] ⏰ 时间间隔达到阈值: ${timeSinceLastUpdate.inMinutes} >= ${_timeBasedUpdateInterval.inMinutes} 分钟');
        return true;
      }
    } else {
      // 如果从未更新过，强制更新
      print('[FocusDetector] 🆕 首次更新');
      return true;
    }

    return false;
  }

  /// 检测重要变化
  bool _detectSignificantChange(String text) {
    // 1. 检测问题或请求
    final questionWords = ['什么', '怎么', '为什么', '如何', '?', '？'];
    if (questionWords.any((word) => text.contains(word))) {
      print('[FocusDetector] ❓ 检测到问题');
      return true;
    }

    // 2. 检测情绪词汇
    final emotionWords = ['喜欢', '讨厌', '开心', '难过', '生气', '担心', '兴奋'];
    if (emotionWords.any((word) => text.contains(word))) {
      print('[FocusDetector] 😊 检测到情绪表达');
      return true;
    }

    // 3. 检测重要实体
    final entities = _extractQuickEntities(text);
    if (entities.isNotEmpty) {
      print('[FocusDetector] 👤 检测到实体: $entities');
      return true;
    }

    return false;
  }

  /// 快速提取实体
  Set<String> _extractQuickEntities(String text) {
    final entities = <String>{};

    // 简单的实体识��
    final patterns = [
      RegExp(r'[张王李赵刘陈杨黄][一-龯]{1,2}'), // 中文人名
      RegExp(r'[A-Z][a-z]+'), // 英文名词
      RegExp(r'[\u4e00-\u9fa5]*(?:公司|大学|学校|医院)'), // 机构名
    ];

    for (final pattern in patterns) {
      entities.addAll(pattern.allMatches(text).map((m) => m.group(0)!));
    }

    return entities;
  }

  /// 添加对话到历史
  void addConversation(String text) {
    print('[FocusDetector] 📝 添加对话到历史');
    print('[FocusDetector] ��� 内容: "${text.substring(0, text.length > 100 ? 100 : text.length)}..."');

    _conversationHistory.addLast(text);
    if (_conversationHistory.length > _historyLimit) {
      _conversationHistory.removeFirst(); // 🔥 移除unused variable警告
      print('[FocusDetector] 🗑️ 移��旧对话');
    }
    print('[FocusDetector] 📚 当前历史对话数量: ${_conversationHistory.length}');
  }

  /// 获取最近的对话上下文
  String getRecentContext() {
    final context = _conversationHistory.join('\n');
    print('[FocusDetector] 📖 获取上下文 - 长度: ${context.length} 字符');
    print('[FocusDetector] 📋 上下文内容预览: "${context.substring(0, context.length > 200 ? 200 : context.length)}..."');
    return context;
  }

  /// 更新当前关注点
  void updateCurrentFocus(Map<String, dynamic> analysis) {
    // 🔥 修复：支持新的分析结构，包含显式和隐式实体
    final topics = List<String>.from(analysis['topics'] ?? []);
    final explicitEntities = List<String>.from(analysis['explicit_entities'] ?? []);
    final implicitEntities = List<String>.from(analysis['implicit_entities'] ?? []);
    final allEntities = [...explicitEntities, ...implicitEntities];
    final intent = analysis['intent'] ?? 'general_chat';
    final emotion = analysis['emotion'] ?? 'neutral';

    _currentTopics.clear();
    _currentTopics.addAll(topics);
    _currentEntities.clear();
    _currentEntities.addAll(allEntities);
    _currentIntent = intent;
    _lastEmotion = emotion;

    print('[FocusDetector] 🎯 更新关注点:');
    print('[FocusDetector] 📋 话题: $_currentTopics');
    print('[FocusDetector] 👥 显式实体: $explicitEntities');
    print('[FocusDetector] 🧠 隐式实体: $implicitEntities');
    print('[FocusDetector] 💭 意图: $_currentIntent');
    print('[FocusDetector] 😊 情绪: $_lastEmotion');
  }

  /// 获取��前关注点摘要
  List<String> getCurrentFocusSummary() {
    final summary = <String>[];

    if (_currentTopics.isNotEmpty) {
      summary.add('当前话题: ${_currentTopics.join(', ')}');
    }

    if (_currentEntities.isNotEmpty) {
      summary.add('涉及实体: ${_currentEntities.join(', ')}');
    }

    summary.add('用户意图: $_currentIntent');
    summary.add('情绪状态: $_lastEmotion');

    if (summary.isEmpty) {
      summary.add('暂无特定关注点');
    }

    return summary;
  }
}

/// 对话缓存服务
class ConversationCache {
  static final ConversationCache _instance = ConversationCache._internal();
  factory ConversationCache() => _instance;
  ConversationCache._internal();

  // 配置参数
  static const int _maxCacheSize = 200;
  static const int _userProfileReserved = 20;
  static const double _cacheHitThreshold = 0.7;

  // 核心组件
  final Map<String, CacheItem> _cache = {};
  final ConversationFocusDetector _focusDetector = ConversationFocusDetector();
  final EnhancedKGService _enhancedKG = EnhancedKGService(); // 🔥 新增：集成增强知识���谱服务

  late LLM _llm;
  bool _initialized = false;
  bool _initializing = false;
  Timer? _periodicUpdateTimer;
  final Set<String> _processedConversations = {}; // 🔥 防止重复处理

  /// 初始化缓存服务
  Future<void> initialize() async {
    if (_initialized) {
      print('[ConversationCache] ✅ 缓存服务已初始化，跳过');
      return;
    }

    if (_initializing) {
      print('[ConversationCache] ⏳ 缓存服务正在初始化中，等待完成...');
      // 等待初始化完成
      while (_initializing && !_initialized) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return;
    }

    _initializing = true;
    print('[ConversationCache] 🚀 开始初始化缓存服务...');

    try {
      // 🔥 优化：并行初始化LLM和知识图谱服务
      await Future.wait([
        _initializeLLM(),
        _enhancedKG.initialize(),
      ]);

      print('[ConversationCache] 🧠 LLM和知识图谱服务已初始化');

      // 加载初始缓存
      await _loadInitialCache();

      // 启动定期更新
      _startPeriodicUpdate();

      _initialized = true;
      _initializing = false;
      print('[ConversationCache] ✅ 缓存服���初始化完成');
      print('[ConversationCache] 📊 缓存统计: ${getCacheStats()}');
    } catch (e) {
      _initializing = false;
      print('[ConversationCache] ❌ 初始化失败: $e');
      rethrow;
    }
  }

  /// 🔥 新增：独立的LLM初始化方法
  Future<void> _initializeLLM() async {
    // 获取当前时间用于系统提示词
    final currentTime = DateTime.now();
    final timeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final formattedTime = timeFormatter.format(currentTime);

    _llm = await LLM.create('gpt-3.5-turbo',
        systemPrompt: '''你是一个专业的对话分析专家，擅长精细化实体识别、语义分析和待办事项检测。

当前时间：$formattedTime

分析用户对话时需要识别以下类型的实体和概念：

1. 显式实体（直接出现在文本中）：
   - 具体物品：食物、物品、工具、设备等
   - 人物：姓名、称谓、角色等
   - 地点：具体地址、场所、区域等
   - 时间：具体时间、时段等
   - 活动：具体行为、动作等

2. 隐式实体（需要语义推断）：
   - 生活场景：从具体行为推断出的生活情境（如"晚餐"、"食物"、"休闲"）
   - 工作内容：从描述推断的工作类型（如"软件开发"、"问题调试"、"产品优化"）
   - 情感状态：从描述推断的情绪和感受
   - 兴趣爱好：从行为模式推断的兴趣点
   - 技能领域：从工作或学习内容推断的专业领域

3. 关联概念：
   - 相关的上下级概念
   - 同类别的相关事物
   - 可能的后续行为或需求

4. 待办事项检测：
   分析对话中是否包含需要创建待办事项的内容，包括：
   - 明确的任务和行动计划
   - 需要完成的工作或学习目标
   - 约定的会议或活动
   - 需要购买或准备的物品
   - 需要联系或回复的人
   - 有时间要求的任务
   
   如果检测到待办事项，请提取：
   - 任务描述：具体要做什么
   - 详细说明：任务的背景或要求
   - 截止时间：基于对话内容推断合理的完成时间（使用当前时间作为参考）

输出严格的JSON格式：
{
  "explicit_entities": ["直接出现的实体1", "实体2"],
  "implicit_entities": ["推断出的概念1", "概念2"],
  "topics": ["主要话题1", "话题2"],
  "intent": "用户意图",
  "emotion": "情��������",
  "focus_summary": "详细的关注点总结",
  "semantic_analysis": {
    "life_scenes": ["生活场景"],
    "work_context": ["工作相关"],
    "interests": ["兴趣相关"],
    "needs": ["可能的���求"]
  },
  "todos": [
    {
      "task": "任务描述",
      "details": "详细说明",
      "deadline": "yyyy-MM-dd HH:mm",
      "priority": "high|medium|low"
    }
  ]
}

意图类型：information_seeking, problem_solving, sharing_experience, learning, planning, casual_chat
情绪类型：positive, negative, neutral, excited, satisfied, frustrated, curious, relaxed

请注意，因为对话内容是源自本地的语音识别模型，精度可能只有60%左右，请你在阅读对话时尝试补充、修改以及同音词替换等手段，从而还原出对话真实的内容，对于实在无法理解或者不符合日常对话的片段，请忽略它。
请确保分析要细致入微，宁可多识别一些相关概念，也不要遗漏重要信息。对于待办事项的检测要准确，不是百分百确定的情况不需要创建。''');
  }

  /// 启动定期更新
  void _startPeriodicUpdate() {
    _periodicUpdateTimer = Timer.periodic(Duration(minutes: 5), (timer) { // ��� 延长间隔到5分钟
      print('[ConversationCache] ⏰ 定期检查新对话...');
      _loadRecentConversationsBackground(); // 🔥 使用专门的后台方法
    });
  }

  /// 🔥 新增：后台加载最近对话（避免循环）
  Future<void> _loadRecentConversationsBackground() async {
    if (!_initialized) return;

    try {
      print('[ConversationCache] 📚 后台加载最近对话...');

      // 获取最近30分钟的对话记录
      final cutoffTime = DateTime.now().subtract(Duration(minutes: 30)).millisecondsSinceEpoch;
      final recentRecords = ObjectBoxService().getRecordsSince(cutoffTime);

      if (recentRecords.isEmpty) {
        print('[ConversationCache] ℹ️ 没有找到最近的对话记录');
        return;
      }

      print('[ConversationCache] 📊 找到 ${recentRecords.length} 条最近对话');

      // ��� 直接处理对话，避免调用processBackgroundConversation
      for (final record in recentRecords.take(5)) { // ��少处理数量
        final content = record.content ?? '';
        if (content.trim().isNotEmpty) {
          final contentHash = content.hashCode.toString();
          if (!_processedConversations.contains(contentHash)) {
            print('[ConversationCache] 🔄 处理新对话: "${content.substring(0, content.length > 30 ? 30 : content.length)}..."');
            _processedConversations.add(contentHash);
            _focusDetector.addConversation(content);

            // 直接触发分析，不通过processBackgroundConversation
            if (_focusDetector.shouldTriggerUpdate(content)) {
              await _analyzeAndUpdateCache();
            }
          }
        }
      }

      // ���理旧的处理记录，防止内存泄漏
      if (_processedConversations.length > 100) {
        _processedConversations.clear();
      }
    } catch (e) {
      print('[ConversationCache] ❌ 后台加载��话失败: $e');
    }
  }

  /// 🔥 修复���移除循环调用的_loadRecentConversations方法
  // 这个方法已被_loadRecentConversationsBackground替代
  // Future<void> _loadRecentConversations() async {
  //   await _loadRecentConversationsBackground();
  // }

  /// 处理背景对话（实时监听）
  Future<void> processBackgroundConversation(String conversationText) async {
    print('[ConversationCache] 🚀 开始处理背景对话');
    print('[ConversationCache] 📝 输入文本: "${conversationText.substring(0, conversationText.length > 100 ? 100 : conversationText.length)}..."');
    print('[ConversationCache] 📏 文本长度: ${conversationText.length}');

    if (conversationText.trim().isEmpty) {
      print('[ConversationCache] ⚠️ 输入文本为空，跳过处理');
      return;
    }

    // 🔥 修复：检查是否正在初始化，避免循环
    if (_initializing) {
      print('[ConversationCache] ⏳ 正在初始化中，稍后处理...');
      return;
    }

    if (!_initialized) {
      print('[ConversationCache] 🔄 缓存未初始化，先初始化...');
      await initialize();
    }

    try {
      // ���� 防止重复处理相同内容
      final contentHash = conversationText.hashCode.toString();
      if (_processedConversations.contains(contentHash)) {
        print('[ConversationCache] ⚠️ 对话已处理过，跳过');
        return;
      }

      _processedConversations.add(contentHash);

      // 添加到对话历史
      _focusDetector.addConversation(conversationText);

      // 检测是否需要触发关注点更新
      if (_focusDetector.shouldTriggerUpdate(conversationText)) {
        print('[ConversationCache] 🔄 触发关注点分析和缓存更新');
        await _analyzeAndUpdateCache();
      } else {
        print('[ConversationCache] ℹ️ 暂不触发缓存��新');
      }
    } catch (e) {
      print('[ConversationCache] ❌ 处理背景对话失败: $e');
    }
  }

  /// 分析并更新缓存
  Future<void> _analyzeAndUpdateCache() async {
    try {
      print('[ConversationCache] 🧠 开始智能分析...');

      // 获取最近对话上下文
      final context = _focusDetector.getRecentContext();
      if (context.isEmpty) {
        print('[ConversationCache] ⚠️ 上下文为空，跳过分析');
        return;
      }

      print('[ConversationCache] 📤 发送给LLM分析，内容长度: ${context.length}');

      // 🔥 优化：并行执行LLM分析和知识图谱分析
      final futures = await Future.wait([
        _performLLMAnalysis(context),
        _performKGAnalysis(context),
      ]);

      final llmAnalysis = futures[0] as Map<String, dynamic>;
      final kgResult = futures[1] as KGAnalysisResult?;

      print('[ConversationCache] 🔍 LLM分析结果: ${llmAnalysis.toString().substring(0, 200)}...');
      if (kgResult != null) {
        print('[ConversationCache] 🕸️ 知识图谱分析找到 ${kgResult.nodes.length} 个相关节点');
      }

      // 更新关注点检测器的状态
      _focusDetector.updateCurrentFocus(llmAnalysis);

      // 将分析结果添��到缓存
      await _addAnalysisToCache(llmAnalysis, context);

      // �� 新增：如果有知识图谱结果，也添加到缓存
      if (kgResult != null) {
        await _addKGResultToCache(kgResult);
      }

      print('[ConversationCache] ✅ 智能分���和缓存更新完成');

    } catch (e) {
      print('[ConversationCache] ❌ 分析和更新缓存失败: $e');
      // 添加基本的分析结果，确保有内容
      final context = _focusDetector.getRecentContext();
      final fallbackAnalysis = _createFallbackAnalysis(context);
      _focusDetector.updateCurrentFocus(fallbackAnalysis);
      await _addAnalysisToCache(fallbackAnalysis, context);
    }
  }

  /// 🔥 新增：执行LLM分析
  Future<Map<String, dynamic>> _performLLMAnalysis(String context) async {
    final analysisResult = await _llm.createRequest(content: '''
请分析以下对话内容，提取用户的关注点：

对话内容：
$context

请按照要求的JSON格式输出分析结果。
''');

    return _parseAnalysisResult(analysisResult);
  }

  /// 🔥 新增：执行知识图谱分析
  Future<KGAnalysisResult?> _performKGAnalysis(String context) async {
    try {
      // 使用增强知识图谱服��进行分析
      return await _enhancedKG.performKGAnalysis(context);
    } catch (e) {
      print('[ConversationCache] ⚠️ 知识图谱分析失败: $e');
      return null;
    }
  }

  /// 🔥 新增：将知识图谱结果添加到缓存
  Future<void> _addKGResultToCache(KGAnalysisResult kgResult) async {
    print('[ConversationCache] 🕸️ 将知识图谱结果添加到缓存...');

    // 为每个���到的节���创建缓存项
    for (final relevanceData in kgResult.relevanceData) {
      final node = kgResult.nodes.firstWhere(
            (n) => n.id == relevanceData.nodeId,
        orElse: () => kgResult.nodes.first,
      );

      final kgCacheItem = CacheItem(
        key: 'kg_node_${node.id}_${DateTime.now().millisecondsSinceEpoch}',
        content: '知识图谱节点: ${node.name} (${node.type})。相关性: ${relevanceData.reason}',
        priority: _determineKGPriority(relevanceData.score),
        relatedTopics: _extractTopicsFromKGAnalysis(kgResult.analysis),
        createdAt: DateTime.now(),
        relevanceScore: relevanceData.score,
        category: 'knowledge_reserve',
        data: {
          'node': node,
          'kg_analysis': kgResult.analysis,
          'relevance_data': relevanceData,
          'source_query': kgResult.originalQuery,
        },
      );
      _addToCache(kgCacheItem);
    }

    // 创建知识图谱分析摘要缓存项
    final kgSummaryItem = CacheItem(
      key: 'kg_summary_${DateTime.now().millisecondsSinceEpoch}',
      content: '知识图谱分析摘要: 基于查询"${kgResult.originalQuery}"找到${kgResult.nodes.length}个相关节点',
      priority: CacheItemPriority.high,
      relatedTopics: _extractTopicsFromKGAnalysis(kgResult.analysis),
      createdAt: DateTime.now(),
      relevanceScore: 0.9,
      category: 'knowledge_reserve',
      data: {
        'kg_result': kgResult,
        'summary_type': 'kg_analysis',
      },
    );
    _addToCache(kgSummaryItem);

    print('[ConversationCache] ✅ 知识图谱结果已添加到缓存');
  }

  /// 🔥 新增：确定知识图谱节点的优���级
  CacheItemPriority _determineKGPriority(double relevanceScore) {
    if (relevanceScore >= 0.8) return CacheItemPriority.high;
    if (relevanceScore >= 0.6) return CacheItemPriority.medium;
    return CacheItemPriority.low;
  }

  /// 🔥 新增：从知识图谱分析中提取话题
  Set<String> _extractTopicsFromKGAnalysis(dynamic analysis) {
    final topics = <String>{};

    if (analysis != null) {
      // 尝试从分析结果中提取话题
      if (analysis is Map) {
        final keywords = analysis['keywords'] as List?;
        if (keywords != null) {
          topics.addAll(keywords.map((k) => k.toString()));
        }

        final entities = analysis['entities'] as List?;
        if (entities != null) {
          topics.addAll(entities.map((e) => e.toString()));
        }
      }
    }

    return topics.isEmpty ? {'知识图谱'} : topics;
  }

  /// 加载初始缓存
  Future<void> _loadInitialCache() async {
    print('[ConversationCache] 📚 加载初始缓存...');

    // 添加基本的框架信息
    final frameworkItems = [
      {
        'content': '用户是一个独特的个体，有自己的兴趣爱好和专业背景',
        'topics': {'个���特征', '��趣爱好'},
        'category': 'personal_info'
      },
      {
        'content': '用户通过对话表达需求、分享想法和解决问题',
        'topics': {'交流', '对话'},
        'category': 'conversation_grasp'
      },
    ];

    for (int i = 0; i < frameworkItems.length; i++) {
      final entry = frameworkItems[i];
      final item = CacheItem(
        key: 'framework_$i',
        content: entry['content'] as String,
        priority: CacheItemPriority.userProfile,
        relatedTopics: entry['topics'] as Set<String>,
        createdAt: DateTime.now(),
        relevanceScore: 1.0,
        category: entry['category'] as String,
      );
      _addToCache(item);
    }

    print('[ConversationCache] ✅ 初���缓存加载完成');
  }

  /// 快速响应查询
  Map<String, dynamic>? getQuickResponse(String userQuery) {
    if (!_initialized) return null;

    print('[ConversationCache] 🔍 搜索缓存响应: $userQuery');

    final queryKeywords = _extractQueryKeywords(userQuery);
    final relevantItems = <CacheItem>[];

    // 搜索相关缓存项
    for (final item in _cache.values) {
      final relevance = _calculateRelevance(queryKeywords, item);
      if (relevance >= _cacheHitThreshold) {
        item.updateAccess();
        item.relevanceScore = relevance;
        relevantItems.add(item);
      }
    }

    if (relevantItems.isEmpty) {
      print('[ConversationCache] ❌ 缓存未命中');
      return null;
    }

    // 按相关性排序
    relevantItems.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    print('[ConversationCache] ✅ 缓存命中，找到 ${relevantItems.length} 个相关项');

    return {
      'hasCache': true,
      'content': relevantItems.map((item) => item.content).toList(),
      'relevanceScores': relevantItems.map((item) => item.relevanceScore).toList(),
      'cacheHitCount': relevantItems.length,
    };
  }

  /// 添加项到缓存
  void _addToCache(CacheItem item) {
    _cache[item.key] = item;
    print('[ConversationCache] ➕ 添加缓存项: ${item.key} (${item.category})');
    _cleanupCache();
  }

  /// 清理缓存
  void _cleanupCache() {
    if (_cache.length <= _maxCacheSize) return;

    print('[ConversationCache] 🧹 开始清理缓存，当前大小: ${_cache.length}');

    final regularItems = _cache.values.where((item) => item.priority != CacheItemPriority.userProfile).toList();
    final maxRegularItems = _maxCacheSize - _userProfileReserved;

    if (regularItems.length > maxRegularItems) {
      regularItems.sort((a, b) => a.calculateWeight().compareTo(b.calculateWeight()));
      final itemsToRemove = regularItems.take(regularItems.length - maxRegularItems);

      for (final item in itemsToRemove) {
        _cache.remove(item.key);
        print('[ConversationCache] ➖ 移除缓存���: ${item.key}');
      }
    }

    print('[ConversationCache] ✅ 缓存清理完成，当前大小: ${_cache.length}');
  }

  /// 提取查询关键词
  Set<String> _extractQueryKeywords(String query) {
    final keywords = RegExp(r'[\u4e00-\u9fa5A-Za-z]{2,}')
        .allMatches(query)
        .map((m) => m.group(0)!)
        .where((word) => word.length > 1)
        .toSet();
    return keywords;
  }

  /// 计算查询与缓存��的相关性
  double _calculateRelevance(Set<String> queryKeywords, CacheItem cacheItem) {
    if (queryKeywords.isEmpty) return 0.0;

    final contentKeywords = _extractQueryKeywords(cacheItem.content);
    final keywordOverlap = queryKeywords.intersection(contentKeywords);
    final keywordScore = keywordOverlap.length / queryKeywords.length;

    final topicOverlap = queryKeywords.intersection(cacheItem.relatedTopics);
    final topicScore = topicOverlap.length / queryKeywords.length;

    final finalScore = (keywordScore * 0.6 + topicScore * 0.4) * cacheItem.relevanceScore;
    return finalScore;
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    final totalItems = _cache.length;
    final categories = <String, int>{};

    for (final item in _cache.values) {
      categories[item.category] = (categories[item.category] ?? 0) + 1;
    }

    return {
      'totalItems': totalItems,
      'categories': categories,
      'isActive': _initialized,
      'lastUpdate': _focusDetector._lastUpdateTime?.toIso8601String(),
    };
  }

  /// 解析LLM分析结果
  Map<String, dynamic> _parseAnalysisResult(String result) {
    print('[ConversationCache] 🧠 解析LLM分析结果...');

    try {
      // 尝试找到JSON部分
      final jsonStart = result.indexOf('{');
      final jsonEnd = result.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
        final jsonStr = result.substring(jsonStart, jsonEnd + 1);
        final parsed = jsonDecode(jsonStr);
        print('[ConversationCache] ✅ JSON解析成功');
        return parsed;
      }
    } catch (e) {
      print('[ConversationCache] ⚠️ JSON解析失败: $e');
    }

    // 备用解析
    print('[ConversationCache] 🔄 使用备用解析策略');
    return _createFallbackAnalysis(result);
  }

  /// 创建备用分析结果
  Map<String, dynamic> _createFallbackAnalysis(String context) {
    print('[ConversationCache] 🔄 创建备用分析结果');

    final quickTopics = <String>[];
    final quickEntities = <String>[];

    // 简单的关键词提取
    if (context.contains('学习') || context.contains('教程')) quickTopics.add('学习');
    if (context.contains('工作') || context.contains('项目')) quickTopics.add('工作');
    if (context.contains('问题') || context.contains('怎么')) quickTopics.add('问题解决');

    // 简单的实体提取
    final namePattern = RegExp(r'[张王李赵刘陈杨黄][一-龯]{1,2}');
    quickEntities.addAll(namePattern.allMatches(context).map((m) => m.group(0)!));

    return {
      'topics': quickTopics.isEmpty ? ['对话'] : quickTopics,
      'entities': quickEntities,
      'intent': 'general_chat',
      'emotion': 'neutral',
      'focus_summary': '基于对话内容的快速分���',
    };
  }

  /// 将分析��果添加到缓存
  Future<void> _addAnalysisToCache(Map<String, dynamic> analysis, String context) async {
    print('[ConversationCache] 💾 将分析结果添加到缓存...');

    final topics = List<String>.from(analysis['topics'] ?? []);
    final explicitEntities = List<String>.from(analysis['explicit_entities'] ?? []);
    final implicitEntities = List<String>.from(analysis['implicit_entities'] ?? []);
    final intent = analysis['intent'] ?? 'general_chat';
    final emotion = analysis['emotion'] ?? 'neutral';
    final focusSummary = analysis['focus_summary'] ?? '';
    final semanticAnalysis = analysis['semantic_analysis'] as Map<String, dynamic>? ?? {};

    // 🔥 新增：提��并处理todo信息
    final todos = analysis['todos'] as List<dynamic>? ?? [];
    await _processTodos(todos, context);

    // 🔥 新增：提取生活场景
    final lifeScenes = List<String>.from(semanticAnalysis['life_scenes'] ?? []);
    // 🔥 新增：提取工作内容
    final workContext = List<String>.from(semanticAnalysis['work_context'] ?? []);
    // 🔥 新增：提取兴趣爱好
    final interests = List<String>.from(semanticAnalysis['interests'] ?? []);
    // 🔥 新增：提取潜在需求
    final needs = List<String>.from(semanticAnalysis['needs'] ?? []);

    // 创建详细的关注点摘要缓存项
    final summaryItem = CacheItem(
      key: 'focus_summary_${DateTime.now().millisecondsSinceEpoch}',
      content: '用户当前关注: $focusSummary。���题包括: ${topics.join(', ')}。意图: $intent，情绪: $emotion。'
          '显式实体: ${explicitEntities.join(', ')}，隐式概念: ${implicitEntities.join(', ')}',
      priority: CacheItemPriority.high,
      relatedTopics: {...topics, ...explicitEntities, ...implicitEntities}.toSet(),
      createdAt: DateTime.now(),
      relevanceScore: 0.9,
      category: 'personal_info',
      data: analysis,
    );
    _addToCache(summaryItem);

    // 🔥 新增：为显式实体创建缓存项
    for (final entity in explicitEntities) {
      final entityItem = CacheItem(
        key: 'explicit_entity_${entity}_${DateTime.now().millisecondsSinceEpoch}',
        content: '用户明确提到了 "$entity"，这是一个重要的显式实体，表明用户的直接关注点',
        priority: CacheItemPriority.high,
        relatedTopics: {entity, ...topics}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.95,
        category: 'conversation_grasp',
        data: {'entity': entity, 'type': 'explicit', 'context': context},
      );
      _addToCache(entityItem);
    }

    // 🔥 新增：为隐式实体��建缓存���
    for (final entity in implicitEntities) {
      final entityItem = CacheItem(
        key: 'implicit_entity_${entity}_${DateTime.now().millisecondsSinceEpoch}',
        content: '从用户对话中推断出 "$entity" 相关概念，这反��了用户的潜在关注领域',
        priority: CacheItemPriority.medium,
        relatedTopics: {entity, ...topics}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.85,
        category: 'conversation_grasp',
        data: {'entity': entity, 'type': 'implicit', 'context': context},
      );
      _addToCache(entityItem);
    }

    // 🔥 新增：为生活场景创建缓存项
    for (final scene in lifeScenes) {
      final sceneItem = CacheItem(
        key: 'life_scene_${scene}_${DateTime.now().millisecondsSinceEpoch}',
        content: '用户当前处于 "$scene" 生活场景中，���有助于理解用户的当前状态和需求',
        priority: CacheItemPriority.medium,
        relatedTopics: {scene, '生活场景', ...topics}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.8,
        category: 'personal_info',
        data: {'scene': scene, 'type': 'life_context', 'context': context},
      );
      _addToCache(sceneItem);
    }

    // 🔥 新增：为工作内容创建缓存项
    for (final work in workContext) {
      final workItem = CacheItem(
        key: 'work_context_${work}_${DateTime.now().millisecondsSinceEpoch}',
        content: '用户涉及 "$work" 相关的工作内容，表明用户在这个领域有活跃的需求',
        priority: CacheItemPriority.high,
        relatedTopics: {work, '工作', ...topics}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.9,
        category: 'personal_info',
        data: {'work': work, 'type': 'work_context', 'context': context},
      );
      _addToCache(workItem);
    }

    // 🔥 新增：为兴趣爱好创建缓存项
    for (final interest in interests) {
      final interestItem = CacheItem(
        key: 'interest_${interest}_${DateTime.now().millisecondsSinceEpoch}',
        content: '用户对 "$interest" 表现出兴��，这是了解用户偏好的重要信息',
        priority: CacheItemPriority.medium,
        relatedTopics: {interest, '兴趣爱好', ...topics}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.8,
        category: 'personal_info',
        data: {'interest': interest, 'type': 'user_interest', 'context': context},
      );
      _addToCache(interestItem);
    }

    // 🔥 新增：为潜在需求创建缓存项
    for (final need in needs) {
      final needItem = CacheItem(
        key: 'need_${need}_${DateTime.now().millisecondsSinceEpoch}',
        content: '用户���能需要 "$need" 相关���帮助或信息，这是主动服务的机会',
        priority: CacheItemPriority.high,
        relatedTopics: {need, '用户需求', ...topics}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.9,
        category: 'conversation_grasp',
        data: {'need': need, 'type': 'potential_need', 'context': context},
      );
      _addToCache(needItem);
    }

    // 为每个话题创建缓存项
    for (final topic in topics) {
      final topicItem = CacheItem(
        key: 'topic_${topic}_${DateTime.now().millisecondsSinceEpoch}',
        content: '用户对 "$topic" 表现出关注，讨论内容包括相关的问题和需求',
        priority: CacheItemPriority.medium,
        relatedTopics: {topic, ...explicitEntities, ...implicitEntities}.toSet(),
        createdAt: DateTime.now(),
        relevanceScore: 0.8,
        category: 'conversation_grasp',
        data: {'topic': topic, 'context': context},
      );
      _addToCache(topicItem);
    }

    // 为意图创建缓存项
    final intentItem = CacheItem(
      key: 'intent_${intent}_${DateTime.now().millisecondsSinceEpoch}',
      content: '用户意图识别为: $intent，表明用户希望进行相应类型的交互',
      priority: CacheItemPriority.medium,
      relatedTopics: {...topics, ...explicitEntities}.toSet(),
      createdAt: DateTime.now(),
      relevanceScore: 0.8,
      category: 'intent_understanding',
      data: {'intent': intent, 'emotion': emotion},
    );
    _addToCache(intentItem);

    print('[ConversationCache] ✅ 分析结果已添加到缓存');
    print('[ConversationCache] 📊 当前缓存大小: ${_cache.length}');
    print('[ConversationCache] 🎯 新增实体: 显式${explicitEntities.length}个, 隐式${implicitEntities.length}个');
    print('[ConversationCache] 🏠 生活场景: ${lifeScenes.length}个, 工作内容: ${workContext.length}个');
    print('[ConversationCache] 💖 兴趣: ${interests.length}个, 需求: ${needs.length}个');
    print('[ConversationCache] ✅ Todo处理: 检测到${todos.length}个待办事项');
  }

  /// 🔥 新增：处理todo任务的防重复机制
  final Set<String> _processedTodos = {};

  /// 🔥 新增：处理检测到的todo任务
  Future<void> _processTodos(List<dynamic> todos, String context) async {
    if (todos.isEmpty) {
      print('[ConversationCache] ℹ️ 未检测到待办事项');
      return;
    }

    print('[ConversationCache] 📝 开始处理${todos.length}个待办事项...');

    final todoEntities = <TodoEntity>[];

    for (final todoData in todos) {
      try {
        if (todoData is! Map<String, dynamic>) continue;

        final task = todoData['task']?.toString() ?? '';
        final details = todoData['details']?.toString() ?? '';
        final deadlineStr = todoData['deadline']?.toString() ?? '';
        final priority = todoData['priority']?.toString() ?? 'medium';

        if (task.isEmpty) continue;

        // 防重复检查：使用任务描述的hash作为唯一标识
        final todoHash = '${task.toLowerCase().replaceAll(RegExp(r'\s+'), '')}_${deadlineStr}';
        if (_processedTodos.contains(todoHash)) {
          print('[ConversationCache] ⚠️ 跳过重复任务: $task');
          continue;
        }

        // 解析截止时间
        DateTime? deadline;
        try {
          if (deadlineStr.isNotEmpty) {
            deadline = DateFormat('yyyy-MM-dd HH:mm').parse(deadlineStr);
          }
        } catch (e) {
          print('[ConversationCache] ⚠️ 时间解析失败，使用默认时间: $deadlineStr');
          // 如果解析失败，设置为24小时后
          deadline = DateTime.now().add(Duration(hours: 24));
        }

        // 根据优先级设置状态
        Status todoStatus = Status.pending;

        // 创建TodoEntity
        final todoEntity = TodoEntity(
          task: task,
          detail: details,
          deadline: deadline?.millisecondsSinceEpoch,
          status: todoStatus,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        todoEntities.add(todoEntity);
        _processedTodos.add(todoHash);

        print('[ConversationCache] ✅ 创建待办事项: $task (截止: ${deadline?.toString() ?? "未设置"})');

      } catch (e) {
        print('[ConversationCache] ❌ 处理待办事项失败: $e');
      }
    }

    // 批量保存到数据库
    if (todoEntities.isNotEmpty) {
      try {
        ObjectBoxService().createTodos(todoEntities);
        print('[ConversationCache] 💾 已保存${todoEntities.length}个待办事项到数据库');

        // 为每个创建的todo添加缓存项
        for (final todo in todoEntities) {
          final todoItem = CacheItem(
            key: 'todo_${todo.task}_${DateTime.now().millisecondsSinceEpoch}',
            content: '创建了待办事项: "${todo.task}"。详情: ${todo.detail}。截止时间: ${todo.deadline != null ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.deadline!)) : "未设置"}',
            priority: CacheItemPriority.high,
            relatedTopics: {'待办事项', 'todo', todo.task!}.toSet(),
            createdAt: DateTime.now(),
            relevanceScore: 0.9,
            category: 'todo_management',
            data: {
              'todo_id': todo.id,
              'task': todo.task,
              'details': todo.detail,
              'deadline': todo.deadline,
              'status': todo.status.toString(),
              'source_context': context,
            },
          );
          _addToCache(todoItem);
        }

      } catch (e) {
        print('[ConversationCache] ❌ 保存待办事项到数据库失败: $e');
      }
    }

    // 清理旧的处理记录，防止内存泄漏
    if (_processedTodos.length > 200) {
      _processedTodos.clear();
      print('[ConversationCache] 🧹 清理待办事项处理记录');
    }
  }

  /// 获取当前个人关注总结
  List<String> getCurrentPersonalFocusSummary() {
    print('[ConversationCache] 📋 获取当前个人关注总结');

    // 首先从关注点检测器获取当前状态
    final currentFocus = _focusDetector.getCurrentFocusSummary();
    if (currentFocus.isNotEmpty) {
      print('[ConversationCache] ✅ 返回当前关注点: $currentFocus');
      return currentFocus;
    }

    // 如果没有当前关注点，从缓存中提取
    final recentItems = _cache.values
        .where((item) => item.category == 'personal_info' || item.category == 'conversation_grasp')
        .toList()
      ..sort((a, b) => b.lastAccessedAt.compareTo(a.lastAccessedAt));

    if (recentItems.isEmpty) {
      print('[ConversationCache] ⚠️ 没有找到关注点信息');
      return ['当前没有特别关注的话题'];
    }

    final topics = recentItems.take(5).expand((item) => item.relatedTopics).toSet();
    final result = topics.isEmpty ? ['等待分析用户关注点'] : topics.toList();

    print('[ConversationCache] 📊 从缓存提取关注点: $result');
    return result;
  }

  /// 获取个人信息用于生成
  Map<String, dynamic> getRelevantPersonalInfoForGeneration() {
    final personalInfo = _cache.values
        .where((item) => item.category == 'personal_info')
        .map((item) => item.content)
        .toList();

    final focusContexts = _cache.values
        .where((item) => item.category == 'conversation_grasp')
        .map((item) => {
      'description': item.content,
      'type': 'conversation_analysis',
      'intensity': item.relevanceScore,
      'keywords': item.relatedTopics.toList(),
    })
        .toList();

    return {
      'personal_nodes': [],
      'user_events': [],
      'user_relationships': [],
      'focus_contexts': focusContexts,
      'total_personal_info_items': personalInfo.length,
      'active_focuses_count': focusContexts.length,
    };
  }

  /// 根据类别获取缓存项
  List<CacheItem> getCacheItemsByCategory(String category) {
    return _cache.values
        .where((item) => item.category == category)
        .toList();
  }

  /// 获取最近的摘要
  List<ConversationSummary> getRecentSummaries({int limit = 5}) {
    final recentItems = _cache.values
        .where((item) => item.category == 'conversation_grasp')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return recentItems.take(limit).map((item) => ConversationSummary(
      timestamp: item.createdAt,
      content: item.content,
      keyTopics: item.relatedTopics.toList(),
    )).toList();
  }

  /// 获取用户个人上下文
  UserPersonalContext getUserPersonalContext() {
    final userProfileItems = _cache.values
        .where((item) => item.category == 'personal_info')
        .toList();

    return UserPersonalContext(
      personalInfo: userProfileItems.map((item) => item.content).toList(),
      preferences: _extractUserPreferences(),
      interests: _extractUserInterests(),
    );
  }

  /// 提取用户偏好
  List<String> _extractUserPreferences() {
    final allTopics = _cache.values
        .expand((item) => item.relatedTopics)
        .toList();

    final topicFrequency = <String, int>{};
    for (final topic in allTopics) {
      topicFrequency[topic] = (topicFrequency[topic] ?? 0) + 1;
    }

    final sortedTopics = topicFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedTopics.take(5).map((e) => e.key).toList();
  }

  /// 提取用户兴趣
  List<String> _extractUserInterests() {
    return _extractUserPreferences(); // 简化实现
  }

  /// 获取主动交互建议
  Map<String, dynamic> getProactiveInteractionSuggestions() {
    final currentFocus = _focusDetector.getCurrentFocusSummary();
    final suggestions = currentFocus.isEmpty
        ? ['有什么我可以帮助您的吗？']
        : ['继续讨论您关心的话题？', '需要更多相关信息吗？'];

    return {
      'suggestions': suggestions,
      'currentTopics': _focusDetector._currentTopics.toList(),
      'hasActiveContext': _focusDetector._currentTopics.isNotEmpty,
      'summaryReady': _cache.isNotEmpty,
      'reminders': [],
      'helpOpportunities': [],
    };
  }

  /// 获取当前对话上下文
  ConversationContext getCurrentConversationContext() {
    final recentContext = _focusDetector.getRecentContext();
    final currentTopics = _focusDetector._currentTopics.toList();
    final activeEntities = _focusDetector._currentEntities.toList();

    final topicIntensity = <String, double>{};
    for (final topic in currentTopics) {
      final count = _cache.values
          .where((item) => item.relatedTopics.contains(topic))
          .length;
      topicIntensity[topic] = _cache.length > 0 ? count / _cache.length : 0.0;
    }

    return ConversationContext(
      recentMessages: recentContext.split('\n').where((msg) => msg.isNotEmpty).toList(),
      currentTopics: currentTopics,
      activeEntities: activeEntities,
      state: _cache.isNotEmpty ? 'active' : 'idle',
      primaryIntent: _focusDetector._currentIntent,
      userEmotion: _focusDetector._lastEmotion,
      startTime: DateTime.now().subtract(Duration(minutes: 30)),
      participants: ['user', 'assistant'],
      topicIntensity: topicIntensity,
      unfinishedTasks: [],
    );
  }

  /// 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    return _cache.values.toList();
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
    print('[ConversationCache] 🗑️ 缓存已清空');
  }

  /// 获取缓存项详细信息
  Map<String, dynamic> getCacheItemDetails(String key) {
    final item = _cache[key];
    if (item == null) {
      return {'error': '缓存项不存在'};
    }

    return {
      'key': item.key,
      'content': item.content,
      'priority': item.priority.toString(),
      'category': item.category,
      'weight': item.weight,
      'relatedTopics': item.relatedTopics.toList(),
      'createdAt': item.createdAt.toIso8601String(),
      'lastAccessedAt': item.lastAccessedAt.toIso8601String(),
      'accessCount': item.accessCount,
      'relevanceScore': item.relevanceScore,
      'data': item.data,
    };
  }

  /// 添加缓存项的公共方法 - 供外部服务调用
  void addCacheItem(CacheItem item) {
    _addToCache(item);
  }

  /// 释放资源
  void dispose() {
    _periodicUpdateTimer?.cancel();
    _cache.clear();
    _initialized = false;
    print('[ConversationCache] 🔌 资源已释放');
  }
}

/// 对话摘要类
class ConversationSummary {
  final DateTime timestamp;
  final String content;
  final List<String> keyTopics;

  ConversationSummary({
    required this.timestamp,
    required this.content,
    required this.keyTopics,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'content': content,
      'keyTopics': keyTopics,
    };
  }
}

/// 对话上下文类
class ConversationContext {
  final List<String> recentMessages;
  final List<String> currentTopics;
  final List<String> activeEntities;
  final String state;
  final String primaryIntent;
  final String userEmotion;
  final DateTime startTime;
  final List<String> participants;
  final Map<String, double> topicIntensity;
  final List<String> unfinishedTasks;

  ConversationContext({
    required this.recentMessages,
    required this.currentTopics,
    required this.activeEntities,
    this.state = 'active',
    this.primaryIntent = 'information_seeking',
    this.userEmotion = 'neutral',
    DateTime? startTime,
    this.participants = const ['user', 'assistant'],
    this.topicIntensity = const {},
    this.unfinishedTasks = const [],
  }) : startTime = startTime ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'recentMessages': recentMessages,
      'currentTopics': currentTopics,
      'activeEntities': activeEntities,
      'state': state,
      'primaryIntent': primaryIntent,
      'userEmotion': userEmotion,
      'startTime': startTime.toIso8601String(),
      'participants': participants,
      'topicIntensity': topicIntensity,
      'unfinishedTasks': unfinishedTasks,
    };
  }
}

/// 用户个人上下文类
class UserPersonalContext {
  final List<String> personalInfo;
  final List<String> preferences;
  final List<String> interests;

  UserPersonalContext({
    required this.personalInfo,
    required this.preferences,
    required this.interests,
  });

  Map<String, dynamic> toJson() {
    return {
      'personalInfo': personalInfo,
      'preferences': preferences,
      'interests': interests,
    };
  }
}

