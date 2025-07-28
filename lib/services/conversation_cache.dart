import 'dart:async';
import 'dart:collection';
import 'package:app/services/advanced_kg_retrieval.dart';
import 'package:app/services/smart_kg_service.dart';
import 'package:app/models/graph_models.dart';

// 缓存项的重要性等级
enum CacheItemPriority {
  critical,   // 用户直接相关的核心信息
  high,       // 当前话题的重要信息
  medium,     // 相关但非核心的信息
  low,        // 可能有用的背景信息
}

// 缓存项
class CacheItem {
  final String key;
  final dynamic data;
  final CacheItemPriority priority;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final Set<String> relatedTopics;
  final double relevanceScore;
  int accessCount;

  CacheItem({
    required this.key,
    required this.data,
    required this.priority,
    required this.relatedTopics,
    required this.relevanceScore,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    this.accessCount = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastAccessedAt = lastAccessedAt ?? DateTime.now();

  // 计算缓存项的综合权重
  double get weight {
    final now = DateTime.now();
    final ageInMinutes = now.difference(createdAt).inMinutes;
    final lastAccessInMinutes = now.difference(lastAccessedAt).inMinutes;

    // 优先级权重
    final priorityWeight = switch (priority) {
      CacheItemPriority.critical => 1.0,
      CacheItemPriority.high => 0.8,
      CacheItemPriority.medium => 0.6,
      CacheItemPriority.low => 0.4,
    };

    // 时间衰减（越新越重要）
    final ageDecay = 1.0 / (1.0 + ageInMinutes / 60.0); // 1小时衰减50%

    // 访问热度
    final accessHeat = (accessCount + 1) / 10.0;

    // 最近访问奖励
    final recentAccessBonus = lastAccessInMinutes < 5 ? 1.2 : 1.0;

    return relevanceScore * priorityWeight * ageDecay * accessHeat * recentAccessBonus;
  }

  CacheItem copyWith({DateTime? lastAccessed, int? newAccessCount}) {
    return CacheItem(
      key: key,
      data: data,
      priority: priority,
      relatedTopics: relatedTopics,
      relevanceScore: relevanceScore,
      createdAt: createdAt,
      lastAccessedAt: lastAccessed ?? lastAccessedAt,
      accessCount: newAccessCount ?? accessCount,
    );
  }
}

// 对话上下文信息
class ConversationContext {
  final List<String> currentTopics;
  final List<String> participants;
  final DateTime startTime;
  final Map<String, double> topicIntensity; // 话题热度
  final Set<String> mentionedEntities;

  ConversationContext({
    required this.currentTopics,
    required this.participants,
    required this.startTime,
    required this.topicIntensity,
    required this.mentionedEntities,
  });
}

// 智能对话缓存系统
class ConversationCache {
  static final ConversationCache _instance = ConversationCache._internal();
  factory ConversationCache() => _instance;
  ConversationCache._internal();

  // 缓存存储
  final Map<String, CacheItem> _cache = {};
  final Queue<String> _accessOrder = Queue<String>();

  // 配置参数
  static const int maxCacheSize = 500;
  static const int maxAccessOrderSize = 100;
  static const Duration cacheExpiration = Duration(hours: 2);
  static const Duration contextUpdateInterval = Duration(seconds: 30);

  // 当前对话上下文
  ConversationContext? _currentContext;
  Timer? _updateTimer;

  // 服务依赖
  final SmartKGService _smartKGService = SmartKGService();
  final AdvancedKGRetrieval _advancedKGRetrieval = AdvancedKGRetrieval();

  // 启动缓存系统
  void initialize() {
    _startContextUpdater();
    _startCacheCleaner();
  }

  // 停止缓存系统
  void dispose() {
    _updateTimer?.cancel();
  }

  // 更新对话上下文
  Future<void> updateConversationContext(String conversationText) async {
    try {
      // 1. 分析对话内容
      final analysis = await _smartKGService.analyzeUserInput(conversationText);

      // 2. 提取话题和实体
      final topics = analysis.keywords;
      final entities = analysis.entities.map((e) => e.entityName).toSet();

      // 3. 计算话题强度
      final topicIntensity = <String, double>{};
      for (final topic in topics) {
        topicIntensity[topic] = _calculateTopicIntensity(topic, conversationText);
      }

      // 4. 更新上下文
      _currentContext = ConversationContext(
        currentTopics: topics,
        participants: _extractParticipants(conversationText),
        startTime: DateTime.now(),
        topicIntensity: topicIntensity,
        mentionedEntities: entities,
      );

      // 5. 触发预测性缓存更新
      await _updatePredictiveCache();

    } catch (e) {
      print('Error updating conversation context: $e');
    }
  }

  // 预测性缓存更新
  Future<void> _updatePredictiveCache() async {
    if (_currentContext == null) return;

    try {
      // 1. 基于当前话题预加载相关信息
      await _preloadTopicRelatedInfo();

      // 2. 基于用户历史预加载个人信息
      await _preloadUserPersonalInfo();

      // 3. 基于对话流预加载可能的问题答案
      await _preloadPotentialQuestions();

    } catch (e) {
      print('Error updating predictive cache: $e');
    }
  }

  // 预加载话题相关信息
  Future<void> _preloadTopicRelatedInfo() async {
    final context = _currentContext!;

    for (final topic in context.currentTopics) {
      final intensity = context.topicIntensity[topic] ?? 0.0;

      // 只处理高热度话题
      if (intensity > 0.5) {
        // 获取话题相关的知识图谱信息
        final relatedNodes = await _getTopicRelatedNodes(topic);

        for (final node in relatedNodes) {
          final cacheKey = 'topic_${topic}_node_${node.id}';
          final priority = _determinePriority(intensity, node);

          _addToCache(
            key: cacheKey,
            data: node,
            priority: priority,
            relatedTopics: {topic},
            relevanceScore: intensity,
          );
        }
      }
    }
  }

  // 预加载用户个人信息
  Future<void> _preloadUserPersonalInfo() async {
    final context = _currentContext!;

    // 基于提到的实体加载用户相关信息
    for (final entity in context.mentionedEntities) {
      final userRelatedInfo = await _getUserRelatedInfo(entity);

      for (final info in userRelatedInfo) {
        final cacheKey = 'user_${entity}_${info.id}';

        _addToCache(
          key: cacheKey,
          data: info,
          priority: CacheItemPriority.critical,
          relatedTopics: context.currentTopics.toSet(),
          relevanceScore: 0.9,
        );
      }
    }
  }

  // 预加载潜在问题的答案
  Future<void> _preloadPotentialQuestions() async {
    final context = _currentContext!;

    // 基于当前话题生成可能的问题
    final potentialQuestions = _generatePotentialQuestions(context);

    for (final question in potentialQuestions) {
      final answer = await _prepareQuestionAnswer(question, context);

      if (answer != null) {
        final cacheKey = 'qa_${question.hashCode}';

        _addToCache(
          key: cacheKey,
          data: {
            'question': question,
            'answer': answer,
            'context': context.currentTopics,
          },
          priority: CacheItemPriority.high,
          relatedTopics: context.currentTopics.toSet(),
          relevanceScore: 0.8,
        );
      }
    }
  }

  // 快速获取缓存的信息
  Map<String, dynamic>? getQuickResponse(String userQuery) {
    try {
      // 1. 分析用户查询
      final queryTopics = _extractQueryTopics(userQuery);

      // 2. 寻找最匹配的缓存项
      final matchingItems = _findMatchingCacheItems(queryTopics);

      if (matchingItems.isNotEmpty) {
        // 3. 组合缓存信息生成快速响应
        return _buildQuickResponse(matchingItems, userQuery);
      }

    } catch (e) {
      print('Error getting quick response: $e');
    }

    return null;
  }

  // 添加到缓存 - 公共方法
  void addToCache({
    required String key,
    required dynamic data,
    required CacheItemPriority priority,
    required Set<String> relatedTopics,
    required double relevanceScore,
  }) {
    _addToCache(
      key: key,
      data: data,
      priority: priority,
      relatedTopics: relatedTopics,
      relevanceScore: relevanceScore,
    );
  }

  // 清理所有缓存 - 公共方法
  void clearCache() {
    _cache.clear();
    _accessOrder.clear();
  }

  // 添加到缓存
  void _addToCache({
    required String key,
    required dynamic data,
    required CacheItemPriority priority,
    required Set<String> relatedTopics,
    required double relevanceScore,
  }) {
    final item = CacheItem(
      key: key,
      data: data,
      priority: priority,
      relatedTopics: relatedTopics,
      relevanceScore: relevanceScore,
    );

    _cache[key] = item;
    _updateAccessOrder(key);

    // 清理过量缓存
    if (_cache.length > maxCacheSize) {
      _evictOldItems();
    }
  }

  // 获取缓存项并更新访问信息
  CacheItem? _getCacheItem(String key) {
    final item = _cache[key];
    if (item != null) {
      // 更新访问信息
      _cache[key] = item.copyWith(
        lastAccessed: DateTime.now(),
        newAccessCount: item.accessCount + 1,
      );
      _updateAccessOrder(key);
    }
    return _cache[key];
  }

  // 更新访问顺序
  void _updateAccessOrder(String key) {
    _accessOrder.remove(key);
    _accessOrder.addLast(key);

    if (_accessOrder.length > maxAccessOrderSize) {
      _accessOrder.removeFirst();
    }
  }

  // 清理过期和低权重的缓存项
  void _evictOldItems() {
    final now = DateTime.now();
    final itemsToRemove = <String>[];

    // 找出过期或权重过低的项
    for (final entry in _cache.entries) {
      final item = entry.value;

      // 检查是否过期
      if (now.difference(item.createdAt) > cacheExpiration) {
        itemsToRemove.add(entry.key);
        continue;
      }

      // 检查权重是否过低
      if (item.weight < 0.1) {
        itemsToRemove.add(entry.key);
      }
    }

    // 如果还是太多，按权重排序删除最低的
    if (_cache.length - itemsToRemove.length > maxCacheSize) {
      final sortedItems = _cache.entries
          .where((e) => !itemsToRemove.contains(e.key))
          .toList()
        ..sort((a, b) => a.value.weight.compareTo(b.value.weight));

      final additionalToRemove = _cache.length - itemsToRemove.length - maxCacheSize;
      for (int i = 0; i < additionalToRemove; i++) {
        itemsToRemove.add(sortedItems[i].key);
      }
    }

    // 移除选中的项
    for (final key in itemsToRemove) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }
  }

  // 启动定期上下文更新器
  void _startContextUpdater() {
    _updateTimer = Timer.periodic(contextUpdateInterval, (timer) {
      _performPeriodicMaintenance();
    });
  }

  // 启动缓存清理器
  void _startCacheCleaner() {
    Timer.periodic(const Duration(minutes: 10), (timer) {
      _evictOldItems();
    });
  }

  // 定期维护
  void _performPeriodicMaintenance() {
    // 1. 清理过期缓存
    _evictOldItems();

    // 2. 更新话题热度衰减
    _updateTopicHeatDecay();

    // 3. 预测即将需要的信息
    _predictUpcomingNeeds();
  }

  // 辅助方法实现
  double _calculateTopicIntensity(String topic, String text) {
    final mentions = text.toLowerCase().split(' ').where((word) =>
        word.contains(topic.toLowerCase())).length;
    return (mentions / text.split(' ').length).clamp(0.0, 1.0);
  }

  List<String> _extractParticipants(String text) {
    // 简化版本，实际可以更复杂
    final pronouns = ['我', '你', '他', '她', 'I', 'you', 'he', 'she'];
    return pronouns.where((p) => text.contains(p)).toList();
  }

  Future<List<Node>> _getTopicRelatedNodes(String topic) async {
    // 使用现有的知识图谱服务
    return await _advancedKGRetrieval.retrieveRelevantNodes(
      seedEntityIds: [topic],
      userQuery: topic,
      intent: 'query',
    ).then((relevances) => relevances.map((r) => r.node).toList());
  }

  Future<List<Node>> _getUserRelatedInfo(String entity) async {
    // 查询与用户相关的实体信息
    return await _advancedKGRetrieval.retrieveRelevantNodes(
      seedEntityIds: [entity],
      userQuery: 'user related $entity',
      intent: 'query',
    ).then((relevances) => relevances.map((r) => r.node).toList());
  }

  CacheItemPriority _determinePriority(double intensity, Node node) {
    if (intensity > 0.8) return CacheItemPriority.critical;
    if (intensity > 0.6) return CacheItemPriority.high;
    if (intensity > 0.4) return CacheItemPriority.medium;
    return CacheItemPriority.low;
  }

  List<String> _generatePotentialQuestions(ConversationContext context) {
    final questions = <String>[];

    for (final topic in context.currentTopics) {
      questions.addAll([
        '什么是$topic？',
        '$topic怎么样？',
        '你觉得$topic如何？',
        '关于$topic有什么建议吗？',
      ]);
    }

    for (final entity in context.mentionedEntities) {
      questions.addAll([
        '$entity的详细信息',
        '$entity的价格',
        '$entity好用吗？',
      ]);
    }

    return questions;
  }

  Future<String?> _prepareQuestionAnswer(String question, ConversationContext context) async {
    // 使用现有系统生成答案的预备信息
    // 这里简化处理，实际应该调用完整的问答系统
    return 'Prepared answer for: $question based on ${context.currentTopics}';
  }

  List<String> _extractQueryTopics(String query) {
    return RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]+')
        .allMatches(query)
        .map((m) => m.group(0)!)
        .where((word) => word.length > 1)
        .toList();
  }

  List<CacheItem> _findMatchingCacheItems(List<String> queryTopics) {
    final matchingItems = <CacheItem>[];

    for (final item in _cache.values) {
      final overlap = item.relatedTopics.intersection(queryTopics.toSet());
      if (overlap.isNotEmpty) {
        matchingItems.add(item);
      }
    }

    // 按权重排序
    matchingItems.sort((a, b) => b.weight.compareTo(a.weight));
    return matchingItems.take(10).toList();
  }

  Map<String, dynamic> _buildQuickResponse(List<CacheItem> items, String query) {
    final relevantNodes = <Node>[];
    final qaItems = <Map<String, dynamic>>[];

    for (final item in items) {
      if (item.data is Node) {
        relevantNodes.add(item.data as Node);
      } else if (item.data is Map && item.data['question'] != null) {
        qaItems.add(item.data as Map<String, dynamic>);
      }
    }

    return {
      'hasCache': true,
      'relevantNodes': relevantNodes,
      'precomputedQA': qaItems,
      'cacheHitCount': items.length,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void _updateTopicHeatDecay() {
    // 话题热度随时间衰减的逻辑
  }

  void _predictUpcomingNeeds() {
    // 预测即将需要的信息的逻辑
  }

  // 获取所有缓存项 - 用于调试
  List<CacheItem> getAllCacheItems() {
    final items = _cache.values.toList();
    // 按权重排序，权重高的在前面
    items.sort((a, b) => b.weight.compareTo(a.weight));
    return items;
  }

  // 获取缓存项详细信息 - 用于调试
  Map<String, dynamic> getCacheItemDetails(String key) {
    final item = _cache[key];
    if (item == null) return {};

    return {
      'key': item.key,
      'priority': item.priority.toString(),
      'weight': item.weight,
      'createdAt': item.createdAt.toIso8601String(),
      'lastAccessedAt': item.lastAccessedAt.toIso8601String(),
      'accessCount': item.accessCount,
      'relatedTopics': item.relatedTopics.toList(),
      'relevanceScore': item.relevanceScore,
      'dataType': item.data.runtimeType.toString(),
    };
  }

  // 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    var totalWeight = 0.0;
    var priorityCounts = <CacheItemPriority, int>{};
    var ageDistribution = <String, int>{};

    for (final item in _cache.values) {
      totalWeight += item.weight;
      priorityCounts[item.priority] = (priorityCounts[item.priority] ?? 0) + 1;

      final ageInMinutes = now.difference(item.createdAt).inMinutes;
      final ageGroup = ageInMinutes < 5 ? 'fresh' :
                      ageInMinutes < 30 ? 'recent' :
                      ageInMinutes < 60 ? 'old' : 'stale';
      ageDistribution[ageGroup] = (ageDistribution[ageGroup] ?? 0) + 1;
    }

    return {
      'totalItems': _cache.length,
      'totalWeight': totalWeight,
      'averageWeight': _cache.isNotEmpty ? totalWeight / _cache.length : 0,
      'priorityCounts': priorityCounts.map((k, v) => MapEntry(k.toString(), v)),
      'ageDistribution': ageDistribution,
      'currentTopics': _currentContext?.currentTopics ?? [],
      'lastUpdate': _currentContext?.startTime?.toIso8601String(),
    };
  }
}
