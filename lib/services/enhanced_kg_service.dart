import 'package:app/services/advanced_kg_retrieval.dart';
import 'package:app/services/smart_kg_service.dart';
import 'package:app/services/conversation_cache.dart';
import 'package:app/models/graph_models.dart';

class EnhancedKGService {
  static final EnhancedKGService _instance = EnhancedKGService._internal();
  factory EnhancedKGService() => _instance;
  EnhancedKGService._internal();

  final ConversationCache _cache = ConversationCache();
  final SmartKGService _smartKG = SmartKGService();
  final AdvancedKGRetrieval _advancedKG = AdvancedKGRetrieval();

  // 初始化服务
  void initialize() {
    _cache.initialize();
  }

  // 处理背景对话（被动监听）
  Future<void> processBackgroundConversation(String conversationText) async {
    try {
      // 更新对话上下文并触发预测性缓存
      await _cache.updateConversationContext(conversationText);

      // 分析对话中的关键信息
      await _analyzeAndCacheKeyInfo(conversationText);

    } catch (e) {
      print('Error processing background conversation: $e');
    }
  }

  // 快速响应用户查询（优先使用缓存）
  Future<Map<String, dynamic>> getQuickResponse(String userQuery) async {
    try {
      // 1. 尝试从缓存获取快速响应
      final cachedResponse = _cache.getQuickResponse(userQuery);

      if (cachedResponse != null && cachedResponse['hasCache'] == true) {
        // 缓存命中，返回快速响应
        return {
          'source': 'cache',
          'responseTime': 'fast',
          'data': cachedResponse,
          'needsFullAnalysis': false,
        };
      }

      // 2. 缓存未命中，执行完整分析但异步更新缓存
      final fullResponse = await _performFullAnalysis(userQuery);

      // 3. 异步更新缓存以备下次使用
      _updateCacheFromAnalysis(userQuery, fullResponse);

      return {
        'source': 'analysis',
        'responseTime': 'normal',
        'data': fullResponse,
        'needsFullAnalysis': true,
      };

    } catch (e) {
      print('Error getting quick response: $e');
      return {'source': 'error', 'error': e.toString()};
    }
  }

  // 分析并缓存关键信息
  Future<void> _analyzeAndCacheKeyInfo(String conversationText) async {
    // 1. 实体识别和关系抽取
    final entities = await _extractEntitiesFromConversation(conversationText);

    // 2. 话题建模
    final topics = await _extractTopicsFromConversation(conversationText);

    // 3. 情感和意图分析
    final sentiment = await _analyzeSentiment(conversationText);
    final intent = await _analyzeIntent(conversationText);

    // 4. 缓存相关的知识图谱信息
    await _cacheRelatedKGInfo(entities, topics, sentiment, intent);
  }

  // 执行完整的分析
  Future<Map<String, dynamic>> _performFullAnalysis(String userQuery) async {
    final analysis = await _smartKG.analyzeUserInput(userQuery);
    final relevantNodes = await _smartKG.getRelevantNodes(analysis);

    final expandedNodes = await _advancedKG.retrieveRelevantNodes(
      seedEntityIds: relevantNodes.map((n) => n.id).toList(),
      userQuery: userQuery,
      intent: analysis.intent.toString().split('.').last,
    );

    return {
      'analysis': analysis,
      'nodes': expandedNodes.map((r) => r.node).toList(),
      'relevanceScores': expandedNodes.map((r) => {
        'nodeId': r.node.id,
        'score': r.score,
        'depth': r.depth,
        'reason': r.reason,
      }).toList(),
    };
  }

  // 从分析结果更新缓存
  void _updateCacheFromAnalysis(String query, Map<String, dynamic> analysis) {
    // 异步更新，不阻塞主流程
    Future.microtask(() async {
      try {
        final nodes = analysis['nodes'] as List<Node>? ?? [];
        final queryTopics = _extractQueryTopics(query);

        for (final node in nodes) {
          final cacheKey = 'analysis_${query.hashCode}_${node.id}';

          _cache.addToCache(
            key: cacheKey,
            data: node,
            priority: CacheItemPriority.high,
            relatedTopics: queryTopics.toSet(),
            relevanceScore: 0.8,
          );
        }
      } catch (e) {
        print('Error updating cache from analysis: $e');
      }
    });
  }

  // 从对话中提取实体
  Future<List<String>> _extractEntitiesFromConversation(String text) async {
    // 使用NLP技术提取命名实体
    final analysis = await _smartKG.analyzeUserInput(text);
    return analysis.entities.map((e) => e.entityName).toList();
  }

  // 从对话中提取话题
  Future<List<String>> _extractTopicsFromConversation(String text) async {
    // 使用话题建模技术
    final analysis = await _smartKG.analyzeUserInput(text);
    return analysis.keywords;
  }

  // 情感分析
  Future<String> _analyzeSentiment(String text) async {
    // 简化版情感分析
    final positiveWords = ['好', '棒', '喜欢', '不错', 'good', 'great', 'like'];
    final negativeWords = ['差', '坏', '讨厌', '不好', 'bad', 'terrible', 'hate'];

    final positive = positiveWords.where((word) => text.contains(word)).length;
    final negative = negativeWords.where((word) => text.contains(word)).length;

    if (positive > negative) return 'positive';
    if (negative > positive) return 'negative';
    return 'neutral';
  }

  // 意图分析
  Future<String> _analyzeIntent(String text) async {
    final analysis = await _smartKG.analyzeUserInput(text);
    return analysis.intent.toString().split('.').last;
  }

  // 缓存相关的知识图谱信息
  Future<void> _cacheRelatedKGInfo(
    List<String> entities,
    List<String> topics,
    String sentiment,
    String intent
  ) async {
    // 基于实体和话题预加载相关信息
    for (final entity in entities) {
      final relatedNodes = await _advancedKG.retrieveRelevantNodes(
        seedEntityIds: [entity],
        userQuery: entity,
        intent: intent,
      );

      for (final relevance in relatedNodes) {
        final cacheKey = 'bg_${entity}_${relevance.node.id}';

        _cache.addToCache(
          key: cacheKey,
          data: relevance.node,
          priority: _determinePriorityFromSentiment(sentiment),
          relatedTopics: topics.toSet(),
          relevanceScore: relevance.score,
        );
      }
    }
  }

  // 根据情感确定优先级
  CacheItemPriority _determinePriorityFromSentiment(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return CacheItemPriority.high;
      case 'negative':
        return CacheItemPriority.critical; // 负面情感可能需要更多支持
      default:
        return CacheItemPriority.medium;
    }
  }

  // 提取查询话题
  List<String> _extractQueryTopics(String query) {
    return RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]+')
        .allMatches(query)
        .map((m) => m.group(0)!)
        .where((word) => word.length > 1)
        .toList();
  }

  // 获取缓存性能统计
  Map<String, dynamic> getCachePerformance() {
    return _cache.getCacheStats();
  }

  // 获取所有缓存项 - 用于调试
  List<CacheItem> getAllCacheItems() {
    return _cache.getAllCacheItems();
  }

  // 清理缓存
  void clearCache() {
    _cache.clearCache();
  }

  // 停止服务
  void dispose() {
    _cache.dispose();
  }
}
