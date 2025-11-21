import 'package:app/models/graph_models.dart';
import 'package:app/models/constraint_models.dart';
import 'package:app/services/knowledge_graph_service.dart';

/// 多约束检索服务
/// 核心功能：
/// 1. 在 embedding 检索基础上应用多层约束过滤和评分
/// 2. 支持硬约束（必须满足）和软约束（评分加权）
/// 3. 提供灵活的约束组合和权重配置
class MultiConstraintRetrievalService {
  static final MultiConstraintRetrievalService _instance = 
      MultiConstraintRetrievalService._internal();
  factory MultiConstraintRetrievalService() => _instance;
  MultiConstraintRetrievalService._internal();

  /// 检索并评分事件节点
  /// 
  /// [topic] 查询主题文本
  /// [context] 检索上下文（包含约束条件）
  /// [constraints] 要应用的约束列表
  /// [topK] 返回的候选数量
  /// [similarityThreshold] embedding 相似度阈值
  Future<List<ScoredNode>> retrieveAndScore({
    required String topic,
    required RetrievalContext context,
    List<Constraint> constraints = const [],
    int topK = 30,
    double similarityThreshold = 0.2,
  }) async {
    // 1. 基于 embedding 的向量检索（获取候选集）
    final candidates = await KnowledgeGraphService.searchEventsByText(
      topic,
      topK: topK,
      similarityThreshold: similarityThreshold,
    );

    if (candidates.isEmpty) {
      return [];
    }

    // 2. 应用约束并评分
    final scoredNodes = <ScoredNode>[];

    for (final candidate in candidates) {
      final eventNode = candidate['event'] as EventNode;
      final embeddingSimilarity = candidate['similarity'] ?? 
                                   candidate['cosine_similarity'] ?? 
                                   0.0;

      // 创建初始评分节点
      final scoredNode = ScoredNode(
        node: eventNode,
        embeddingScore: embeddingSimilarity as double,
        matchedTopic: topic,
      );

      // 3. 应用硬约束（必须全部通过）
      bool passedHardConstraints = true;
      for (final constraint in constraints.where((c) => c.isHard)) {
        final result = constraint.evaluate(eventNode, context);
        if (!result.passes) {
          passedHardConstraints = false;
          break;
        }
      }

      if (!passedHardConstraints) {
        continue; // 跳过未通过硬约束的节点
      }

      // 4. 应用软约束（累积评分）
      for (final constraint in constraints.where((c) => !c.isHard)) {
        final result = constraint.evaluate(eventNode, context);
        scoredNode.constraintScores[constraint.name] = result.scoreContribution;
      }

      // 5. 计算综合得分
      scoredNode.computeCompositeScore();

      scoredNodes.add(scoredNode);
    }

    // 6. 按综合得分排序
    scoredNodes.sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

    return scoredNodes;
  }

  /// 批量检索多个主题
  Future<List<ScoredNode>> retrieveMultipleTopics({
    required List<String> topics,
    required RetrievalContext context,
    List<Constraint> constraints = const [],
    int topKPerTopic = 20,
    int finalTopK = 20,
    double similarityThreshold = 0.2,
  }) async {
    final allScoredNodes = <String, ScoredNode>{}; // 使用 Map 去重

    for (final topic in topics) {
      final topicResults = await retrieveAndScore(
        topic: topic,
        context: context,
        constraints: constraints,
        topK: topKPerTopic,
        similarityThreshold: similarityThreshold,
      );

      // 合并结果，保留较高分的版本
      for (final scoredNode in topicResults) {
        final nodeId = scoredNode.node.id;
        if (!allScoredNodes.containsKey(nodeId) ||
            allScoredNodes[nodeId]!.compositeScore < scoredNode.compositeScore) {
          allScoredNodes[nodeId] = scoredNode;
        }
      }
    }

    // 按得分排序并取前 N
    final sortedResults = allScoredNodes.values.toList()
      ..sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

    return sortedResults.take(finalTopK).toList();
  }

  /// 增量更新评分节点池
  /// 
  /// 将新检索的节点与现有池合并，保持总数不超过 maxPoolSize
  /// 
  /// [existingPool] 现有的评分节点池
  /// [newNodes] 新检索到的评分节点
  /// [maxPoolSize] 池的最大容量
  /// [recomputeScores] 是否重新计算所有节点的综合得分
  List<ScoredNode> mergeAndPrune({
    required List<ScoredNode> existingPool,
    required List<ScoredNode> newNodes,
    int maxPoolSize = 20,
    bool recomputeScores = false,
  }) {
    final nodeMap = <String, ScoredNode>{};

    // 1. 添加现有节点
    for (final node in existingPool) {
      nodeMap[node.node.id] = node;
    }

    // 2. 合并新节点
    for (final newNode in newNodes) {
      final nodeId = newNode.node.id;
      
      if (nodeMap.containsKey(nodeId)) {
        // 节点已存在，选择策略：
        // - 如果新节点得分更高，替换
        // - 否则更新时间戳但保留旧得分
        final existing = nodeMap[nodeId]!;
        if (newNode.compositeScore > existing.compositeScore) {
          nodeMap[nodeId] = newNode;
        } else {
          // 更新最后访问时间
          existing.lastUpdated = DateTime.now();
        }
      } else {
        // 新节点，直接添加
        nodeMap[nodeId] = newNode;
      }
    }

    // 3. 可选：重新计算所有得分（考虑时效性衰减）
    if (recomputeScores) {
      for (final node in nodeMap.values) {
        node.computeCompositeScore();
      }
    }

    // 4. 排序并裁剪到最大容量
    final sortedNodes = nodeMap.values.toList()
      ..sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

    return sortedNodes.take(maxPoolSize).toList();
  }

  /// 创建默认约束集（适用于一般场景）
  List<Constraint> createDefaultConstraints({
    DateTime? targetTime,
    String? targetLocation,
    List<String> targetEntityIds = const [],
  }) {
    final constraints = <Constraint>[
      // 软约束：时间接近度
      TemporalProximityConstraint(
        targetTime: targetTime,
        maxDistance: Duration(days: 30),
        weight: 0.3,
      ),
      // 软约束：地点相似度
      if (targetLocation != null && targetLocation.isNotEmpty)
        LocationSimilarityConstraint(
          targetLocation: targetLocation,
          weight: 0.3,
        ),
      // 软约束：新鲜度奖励
      FreshnessBoostConstraint(
        recentWindow: Duration(hours: 48),
        weight: 0.2,
      ),
    ];

    return constraints;
  }

  /// 创建严格约束集（用于精确查询）
  List<Constraint> createStrictConstraints({
    required DateTime startTime,
    required DateTime endTime,
    String? requiredLocation,
    List<String> requiredEntityIds = const [],
  }) {
    final constraints = <Constraint>[
      // 硬约束：时间窗口
      TimeWindowConstraint(
        startTime: startTime,
        endTime: endTime,
      ),
      // 硬约束：地点匹配
      if (requiredLocation != null && requiredLocation.isNotEmpty)
        LocationMatchConstraint(
          requiredLocation: requiredLocation,
        ),
      // 硬约束：实体存在
      if (requiredEntityIds.isNotEmpty)
        EntityPresenceConstraint(
          requiredEntityIds: requiredEntityIds,
        ),
    ];

    return constraints;
  }
}
