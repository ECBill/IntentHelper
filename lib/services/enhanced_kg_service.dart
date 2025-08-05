import 'package:app/services/advanced_kg_retrieval.dart';
import 'package:app/services/smart_kg_service.dart';
import 'package:app/services/conversation_cache.dart';
import 'package:app/models/graph_models.dart';

/// 增强知识图谱服务 - 专注于知识图谱的检索和分析增强
/// 与ConversationCache配合工作，避免功能重复
class EnhancedKGService {
  static final EnhancedKGService _instance = EnhancedKGService._internal();
  factory EnhancedKGService() => _instance;
  EnhancedKGService._internal();

  final SmartKGService _smartKG = SmartKGService();
  final AdvancedKGRetrieval _advancedKG = AdvancedKGRetrieval();

  bool _initialized = false;

  /// 初始化服务 - 仅初始化知识图谱相关组件
  Future<void> initialize() async {
    if (_initialized) return;

    print('[EnhancedKGService] 🚀 初始化增强知识图谱服务...');

    // 这里可以添加知识图谱特定的初始化逻辑
    // 例如：预加载重要节点、建立索引等

    _initialized = true;
    print('[EnhancedKGService] ✅ 增强知识图谱服务初始化完成');
  }

  /// 执行知识图谱分析并返回结构化结果
  /// 这���核心功能，专注于知识图谱的深度分析
  Future<KGAnalysisResult> performKGAnalysis(String userQuery) async {
    if (!_initialized) {
      await initialize();
    }

    print('[EnhancedKGService] ��� 执行知识图谱分析: "$userQuery"');

    try {
      // 1. 基础分析
      final analysis = await _smartKG.analyzeUserInput(userQuery);

      // 2. 获取相关节点
      final relevantNodes = await _smartKG.getRelevantNodes(analysis);

      // 3. 扩展节点检索
      final expandedNodes = await _advancedKG.retrieveRelevantNodes(
        seedEntityIds: relevantNodes.map((n) => n.id).toList(),
        userQuery: userQuery,
        intent: analysis.intent.toString().split('.').last,
      );

      // 4. 构建结果
      final result = KGAnalysisResult(
        originalQuery: userQuery,
        analysis: analysis,
        nodes: expandedNodes.map((r) => r.node).toList(),
        relevanceData: expandedNodes.map((r) => NodeRelevanceData(
          nodeId: r.node.id,
          score: r.score,
          depth: r.depth,
          reason: r.reason,
        )).toList(),
        timestamp: DateTime.now(),
      );

      print('[EnhancedKGService] ✅ 知识图谱分析完成，找到 ${result.nodes.length} 个相关节点');
      return result;

    } catch (e) {
      print('[EnhancedKGService] ❌ 知识图谱分析失败: $e');
      rethrow;
    }
  }

  /// 基于实体和话题预检索相关知识
  /// 用于支持ConversationCache的背景预加载
  Future<List<CacheItem>> preloadKnowledgeForContext({
    required List<String> entities,
    required List<String> topics,
    required String intent,
    required String sentiment,
  }) async {
    print('[EnhancedKGService] 📚 预加载上下文知识...');

    final cacheItems = <CacheItem>[];

    try {
      for (final entity in entities) {
        final relatedNodes = await _advancedKG.retrieveRelevantNodes(
          seedEntityIds: [entity],
          userQuery: entity,
          intent: intent,
        );

        for (final relevance in relatedNodes) {
          final cacheItem = CacheItem(
            key: 'kg_preload_${entity}_${relevance.node.id}',
            content: '知识图谱预加载: ${relevance.node.name} (${relevance.node.type})，与实体"$entity"相关',
            priority: _determinePriorityFromSentiment(sentiment),
            relatedTopics: topics.toSet(),
            createdAt: DateTime.now(),
            relevanceScore: relevance.score,
            category: 'knowledge_reserve',
            data: {
              'node': relevance.node,
              'preload_reason': '基于实体"$entity"的背景预加载',
              'source_intent': intent,
              'source_sentiment': sentiment,
            },
          );
          cacheItems.add(cacheItem);
        }
      }

      print('[EnhancedKGService] ✅ 预加载完成，生成 ${cacheItems.length} 个缓存项');
      return cacheItems;

    } catch (e) {
      print('[EnhancedKGService] ❌ 预加载知识失败: $e');
      return [];
    }
  }

  /// 获取节点的详细信息和关联
  Future<NodeDetailInfo?> getNodeDetails(String nodeId) async {
    try {
      // 这里可以实现更详细的节点信息获取逻辑
      print('[EnhancedKGService] 🔍 获取节点详情: $nodeId');

      // 示例实现 - 实际需要根据具体的知识图谱API调整
      final relatedNodes = await _advancedKG.retrieveRelevantNodes(
        seedEntityIds: [nodeId],
        userQuery: nodeId,
        intent: 'detail_query',
      );

      if (relatedNodes.isNotEmpty) {
        final targetNode = relatedNodes.first.node;
        return NodeDetailInfo(
          node: targetNode,
          connections: relatedNodes.map((r) => r.node).toList(),
          detailLevel: 'comprehensive',
        );
      }

      return null;
    } catch (e) {
      print('[EnhancedKGService] ❌ 获取节点详情失败: $e');
      return null;
    }
  }

  /// 批量分析多个查询的相似性
  Future<List<QuerySimilarity>> analyzeQuerySimilarities(List<String> queries) async {
    final similarities = <QuerySimilarity>[];

    for (int i = 0; i < queries.length; i++) {
      for (int j = i + 1; j < queries.length; j++) {
        final similarity = await _calculateQuerySimilarity(queries[i], queries[j]);
        similarities.add(QuerySimilarity(
          query1: queries[i],
          query2: queries[j],
          similarity: similarity,
        ));
      }
    }

    return similarities;
  }

  /// 计算两个查询的相似性
  Future<double> _calculateQuerySimilarity(String query1, String query2) async {
    try {
      // 简化的相似性计算 - 可以用更复杂的语义相似性算法
      final analysis1 = await _smartKG.analyzeUserInput(query1);
      final analysis2 = await _smartKG.analyzeUserInput(query2);

      // 基于关键词重叠计算相似性
      final keywords1 = analysis1.keywords.toSet();
      final keywords2 = analysis2.keywords.toSet();

      if (keywords1.isEmpty && keywords2.isEmpty) return 1.0;
      if (keywords1.isEmpty || keywords2.isEmpty) return 0.0;

      final intersection = keywords1.intersection(keywords2);
      final union = keywords1.union(keywords2);

      return intersection.length / union.length;
    } catch (e) {
      print('[EnhancedKGService] ❌ 计算查询相似性失败: $e');
      return 0.0;
    }
  }

  /// 根据情感确定优先级
  CacheItemPriority _determinePriorityFromSentiment(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return CacheItemPriority.high;
      case 'negative':
        return CacheItemPriority.critical;
      case 'excited':
        return CacheItemPriority.high;
      case 'frustrated':
        return CacheItemPriority.high;
      case 'confused':
        return CacheItemPriority.medium;
      default:
        return CacheItemPriority.medium;
    }
  }

  /// 智能推荐相关节点
  Future<List<NodeRecommendation>> recommendNodes({
    required String currentContext,
    required List<String> userInterests,
    int maxRecommendations = 5,
  }) async {
    print('[EnhancedKGService] 💡 推荐相关节点...');

    try {
      final recommendations = <NodeRecommendation>[];

      // 基于用户兴趣和当前上下文推荐节点
      for (final interest in userInterests.take(3)) {
        final relatedNodes = await _advancedKG.retrieveRelevantNodes(
          seedEntityIds: [interest],
          userQuery: currentContext,
          intent: 'recommendation',
        );

        for (final relevance in relatedNodes.take(2)) {
          recommendations.add(NodeRecommendation(
            node: relevance.node,
            relevanceScore: relevance.score,
            reason: '基于您对"$interest"的兴趣推荐',
            confidence: relevance.score * 0.8, // 推荐置信度略低于直接相关性
          ));
        }
      }

      // 按相关性排序并限制数量
      recommendations.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
      final finalRecommendations = recommendations.take(maxRecommendations).toList();

      print('[EnhancedKGService] ✅ 推荐了 ${finalRecommendations.length} 个节点');
      return finalRecommendations;

    } catch (e) {
      print('[EnhancedKGService] ❌ 节点推荐失败: $e');
      return [];
    }
  }

  /// 分析用户查询的复杂度
  Future<QueryComplexity> analyzeQueryComplexity(String query) async {
    try {
      final analysis = await _smartKG.analyzeUserInput(query);

      int complexityScore = 0;
      final factors = <String>[];

      // 基于关键词数量
      if (analysis.keywords.length > 5) {
        complexityScore += 2;
        factors.add('多关键词');
      }

      // 基于实体数量
      if (analysis.entities.length > 3) {
        complexityScore += 2;
        factors.add('多实体');
      }

      // 基于���图���杂性
      final intent = analysis.intent.toString().split('.').last;
      if (['planning', 'analysis', 'comparison'].contains(intent)) {
        complexityScore += 3;
        factors.add('复杂意图');
      }

      // 基于查询长度
      if (query.length > 100) {
        complexityScore += 1;
        factors.add('长查询');
      }

      QueryComplexityLevel level;
      if (complexityScore >= 6) {
        level = QueryComplexityLevel.high;
      } else if (complexityScore >= 3) {
        level = QueryComplexityLevel.medium;
      } else {
        level = QueryComplexityLevel.low;
      }

      return QueryComplexity(
        level: level,
        score: complexityScore,
        factors: factors,
        estimatedProcessingTime: _estimateProcessingTime(level),
      );

    } catch (e) {
      print('[EnhancedKGService] ❌ 查询复杂度分析失败: $e');
      return QueryComplexity(
        level: QueryComplexityLevel.low,
        score: 0,
        factors: [],
        estimatedProcessingTime: Duration(seconds: 1),
      );
    }
  }

  Duration _estimateProcessingTime(QueryComplexityLevel level) {
    switch (level) {
      case QueryComplexityLevel.high:
        return Duration(seconds: 5);
      case QueryComplexityLevel.medium:
        return Duration(seconds: 3);
      case QueryComplexityLevel.low:
        return Duration(seconds: 1);
    }
  }

  /// 批量处理关注点，为缓存系统提供支持
  Future<Map<String, KGAnalysisResult>> batchAnalyzeFocusPoints(
      List<String> focusPoints,
      ) async {
    print('[EnhancedKGService] 📊 批量分析关注点: ${focusPoints.length} 个');

    final results = <String, KGAnalysisResult>{};

    try {
      // 并行处理多个关注点，但���制并发数
      final futures = <Future<void>>[];
      const maxConcurrent = 3;

      for (int i = 0; i < focusPoints.length; i += maxConcurrent) {
        final batch = focusPoints.skip(i).take(maxConcurrent);
        final batchFutures = batch.map((focus) => _processSingleFocus(focus, results));
        await Future.wait(batchFutures);
      }

      print('[EnhancedKGService] ✅ 批量分析完成，处理了 ${results.length} 个关注点');
      return results;

    } catch (e) {
      print('[EnhancedKGService] ❌ 批量分析失败: $e');
      return results;
    }
  }

  Future<void> _processSingleFocus(
      String focus,
      Map<String, KGAnalysisResult> results,
      ) async {
    try {
      final result = await performKGAnalysis(focus);
      results[focus] = result;
    } catch (e) {
      print('[EnhancedKGService] ⚠️ 处理关注点"$focus"失败: $e');
    }
  }

  /// 清理和优��知识图谱缓存
  Future<void> optimizeKGCache() async {
    print('[EnhancedKGService] 🧹 优化知识图谱缓存...');

    try {
      // 这里可以实现缓存优化逻辑
      // 例如：清理过期的节点信息、重建索引等
      await Future.delayed(Duration(milliseconds: 500)); // 模拟优化过程

      print('[EnhancedKGService] ✅ 知识图谱缓存优化完成');
    } catch (e) {
      print('[EnhancedKGService] ❌ 缓存优化失败: $e');
    }
  }

  /// 获取知识图谱统计信息
  Map<String, dynamic> getKGStats() {
    return {
      'initialized': _initialized,
      'service_name': 'EnhancedKGService',
      'version': '1.0.0',
      'last_optimization': DateTime.now().toIso8601String(),
      'supported_operations': [
        'performKGAnalysis',
        'preloadKnowledgeForContext',
        'getNodeDetails',
        'recommendNodes',
        'batchAnalyzeFocusPoints',
      ],
    };
  }

  /// 获取服务状态
  Map<String, dynamic> getServiceStatus() {
    return {
      'initialized': _initialized,
      'smart_kg_available': true, // 可以检查_smartKG的状态
      'advanced_kg_available': true, // 可以检查_advancedKG的状态
      'service_type': 'enhanced_kg',
    };
  }

  /// 释放资源
  void dispose() {
    _initialized = false;
    print('[EnhancedKGService] 🔌 增强知识图谱服务已释放');
  }
}

/// 知识图谱分析结果
class KGAnalysisResult {
  final String originalQuery;
  final dynamic analysis; // SmartKGService的分析结果
  final List<Node> nodes;
  final List<NodeRelevanceData> relevanceData;
  final DateTime timestamp;

  KGAnalysisResult({
    required this.originalQuery,
    required this.analysis,
    required this.nodes,
    required this.relevanceData,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'originalQuery': originalQuery,
      'analysis': analysis,
      'nodes': nodes.map((n) => {
        'id': n.id,
        'name': n.name,
        'type': n.type,
        'canonicalName': n.canonicalName,
      }).toList(),
      'relevanceData': relevanceData.map((r) => r.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// 节点相关性数据
class NodeRelevanceData {
  final String nodeId;
  final double score;
  final int depth;
  final String reason;

  NodeRelevanceData({
    required this.nodeId,
    required this.score,
    required this.depth,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'score': score,
      'depth': depth,
      'reason': reason,
    };
  }
}

/// 节点详细信息
class NodeDetailInfo {
  final Node node;
  final List<Node> connections;
  final String detailLevel;

  NodeDetailInfo({
    required this.node,
    required this.connections,
    required this.detailLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'node': {
        'id': node.id,
        'name': node.name,
        'type': node.type,
        'canonicalName': node.canonicalName,
      },
      'connections': connections.map((n) => {
        'id': n.id,
        'name': n.name,
        'type': n.type,
        'canonicalName': n.canonicalName,
      }).toList(),
      'detailLevel': detailLevel,
    };
  }
}

/// 查询相似性
class QuerySimilarity {
  final String query1;
  final String query2;
  final double similarity;

  QuerySimilarity({
    required this.query1,
    required this.query2,
    required this.similarity,
  });

  Map<String, dynamic> toJson() {
    return {
      'query1': query1,
      'query2': query2,
      'similarity': similarity,
    };
  }
}

/// 节点推荐
class NodeRecommendation {
  final Node node;
  final double relevanceScore;
  final String reason;
  final double confidence;

  NodeRecommendation({
    required this.node,
    required this.relevanceScore,
    required this.reason,
    required this.confidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'node': {
        'id': node.id,
        'name': node.name,
        'type': node.type,
        'canonicalName': node.canonicalName,
      },
      'relevanceScore': relevanceScore,
      'reason': reason,
      'confidence': confidence,
    };
  }
}

/// 查询复杂度级别
enum QueryComplexityLevel {
  low,
  medium,
  high,
}

/// 查询复杂度
class QueryComplexity {
  final QueryComplexityLevel level;
  final int score;
  final List<String> factors;
  final Duration estimatedProcessingTime;

  QueryComplexity({
    required this.level,
    required this.score,
    required this.factors,
    required this.estimatedProcessingTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'level': level.toString().split('.').last,
      'score': score,
      'factors': factors,
      'estimatedProcessingTime': estimatedProcessingTime.inMilliseconds,
    };
  }
}
