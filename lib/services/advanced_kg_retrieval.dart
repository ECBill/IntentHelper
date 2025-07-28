import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';
import 'dart:math';

// 节点相关性评分结果
class NodeRelevance {
  final Node node;
  final double score;
  final int depth;
  final String reason;
  final List<String> path; // 从起始节点到当前节点的路径

  NodeRelevance({
    required this.node,
    required this.score,
    required this.depth,
    required this.reason,
    required this.path,
  });
}

// 检索配置
class RetrievalConfig {
  final int maxDepth;           // 最大检索深度
  final int maxNodesPerLayer;   // 每层最大节点数
  final double minScore;        // 最小相关性阈值
  final int maxTotalNodes;      // 最大总节点数
  final bool enableSemanticSimilarity; // 是否启用语义相似度

  const RetrievalConfig({
    this.maxDepth = 3,
    this.maxNodesPerLayer = 10,
    this.minScore = 0.3,
    this.maxTotalNodes = 50,
    this.enableSemanticSimilarity = true,
  });

  // 根据意图调整配置
  factory RetrievalConfig.forIntent(String intent) {
    switch (intent.toLowerCase()) {
      case 'purchase':
        return const RetrievalConfig(
          maxDepth: 2,
          maxNodesPerLayer: 8,
          minScore: 0.4,
          maxTotalNodes: 30,
        );
      case 'compare':
        return const RetrievalConfig(
          maxDepth: 3,
          maxNodesPerLayer: 12,
          minScore: 0.3,
          maxTotalNodes: 40,
        );
      case 'recommend':
        return const RetrievalConfig(
          maxDepth: 4,
          maxNodesPerLayer: 15,
          minScore: 0.25,
          maxTotalNodes: 60,
        );
      default:
        return const RetrievalConfig();
    }
  }
}

class AdvancedKGRetrieval {
  static final AdvancedKGRetrieval _instance = AdvancedKGRetrieval._internal();
  factory AdvancedKGRetrieval() => _instance;
  AdvancedKGRetrieval._internal();

  final ObjectBoxService _objectBox = ObjectBoxService();

  // 主要检索方法：多层扩散检索
  Future<List<NodeRelevance>> retrieveRelevantNodes({
    required List<String> seedEntityIds,
    required String userQuery,
    required String intent,
    RetrievalConfig? config,
  }) async {
    config ??= RetrievalConfig.forIntent(intent);

    final Map<String, NodeRelevance> nodeRelevanceMap = {};
    final Set<String> visited = {};
    final List<List<String>> layerNodes = [seedEntityIds];

    // 第0层：种子节点
    for (final entityId in seedEntityIds) {
      final node = _objectBox.findNodeById(entityId);
      if (node != null) {
        final relevance = NodeRelevance(
          node: node,
          score: 1.0, // 种子节点得分最高
          depth: 0,
          reason: '直接匹配实体',
          path: [node.name],
        );
        nodeRelevanceMap[entityId] = relevance;
        visited.add(entityId);
      }
    }

    // 多层扩散
    for (int depth = 1; depth <= config.maxDepth && layerNodes.isNotEmpty; depth++) {
      final currentLayer = layerNodes.last;
      final nextLayer = <String>[];

      for (final nodeId in currentLayer) {
        final expandedNodes = await _expandNode(
          nodeId: nodeId,
          userQuery: userQuery,
          currentDepth: depth,
          config: config,
          visited: visited,
          parentPath: nodeRelevanceMap[nodeId]?.path ?? [],
        );

        for (final relevance in expandedNodes) {
          if (!visited.contains(relevance.node.id)) {
            nodeRelevanceMap[relevance.node.id] = relevance;
            visited.add(relevance.node.id);
            nextLayer.add(relevance.node.id);
          }
        }

        // 控制每层节点数量
        if (nextLayer.length >= config.maxNodesPerLayer) break;
      }

      if (nextLayer.isNotEmpty) {
        layerNodes.add(nextLayer);
      }

      // 控制总节点数量
      if (nodeRelevanceMap.length >= config.maxTotalNodes) break;
    }

    // 过滤和排序
    final filteredNodes = nodeRelevanceMap.values
        .where((relevance) => relevance.score >= (config?.minScore ?? 0.3))
        .toList();

    // 应用多维度排序
    filteredNodes.sort((a, b) => _compareNodeRelevance(a, b, userQuery));

    return filteredNodes.take(config?.maxTotalNodes ?? 50).toList();
  }

  // 扩展单个节点
  Future<List<NodeRelevance>> _expandNode({
    required String nodeId,
    required String userQuery,
    required int currentDepth,
    required RetrievalConfig config,
    required Set<String> visited,
    required List<String> parentPath,
  }) async {
    final expandedNodes = <NodeRelevance>[];

    // 获取当前节点的所有邻居
    final outgoingEdges = _objectBox.queryEdges(source: nodeId);
    final incomingEdges = _objectBox.queryEdges(target: nodeId);

    // 处理出边（当前节点指向的节点）
    for (final edge in outgoingEdges) {
      if (!visited.contains(edge.target)) {
        final targetNode = _objectBox.findNodeById(edge.target);
        if (targetNode != null) {
          final score = _calculateNodeRelevance(
            node: targetNode,
            userQuery: userQuery,
            depth: currentDepth,
            edgeType: edge.relation,
            isOutgoing: true,
          );

          if (score >= config.minScore) {
            expandedNodes.add(NodeRelevance(
              node: targetNode,
              score: score,
              depth: currentDepth,
              reason: '通过关系"${edge.relation}"连接',
              path: [...parentPath, targetNode.name],
            ));
          }
        }
      }
    }

    // 处理入边（指向当前节点的节点）
    for (final edge in incomingEdges) {
      if (!visited.contains(edge.source)) {
        final sourceNode = _objectBox.findNodeById(edge.source);
        if (sourceNode != null) {
          final score = _calculateNodeRelevance(
            node: sourceNode,
            userQuery: userQuery,
            depth: currentDepth,
            edgeType: edge.relation,
            isOutgoing: false,
          );

          if (score >= config.minScore) {
            expandedNodes.add(NodeRelevance(
              node: sourceNode,
              score: score,
              depth: currentDepth,
              reason: '通过关系"${edge.relation}"被连接',
              path: [...parentPath, sourceNode.name],
            ));
          }
        }
      }
    }

    // 按分数排序并限制数量
    expandedNodes.sort((a, b) => b.score.compareTo(a.score));
    return expandedNodes.take(config.maxNodesPerLayer ~/ 2).toList();
  }

  // 计算节点相关性分数
  double _calculateNodeRelevance({
    required Node node,
    required String userQuery,
    required int depth,
    required String edgeType,
    required bool isOutgoing,
  }) {
    double score = 0.0;

    // 1. 深度惩罚（距离越远，分数越低）
    final depthPenalty = pow(0.7, depth).toDouble();

    // 2. 文本相似度
    final textSimilarity = _calculateTextSimilarity(node, userQuery);

    // 3. 关系类型权重
    final relationWeight = _getRelationWeight(edgeType, isOutgoing);

    // 4. 节点类型权重
    final typeWeight = _getNodeTypeWeight(node.type, userQuery);

    // 5. 属性匹配度
    final attributeMatch = _calculateAttributeMatch(node, userQuery);

    // 综合计算
    score = (textSimilarity * 0.3 +
             relationWeight * 0.25 +
             typeWeight * 0.2 +
             attributeMatch * 0.25) * depthPenalty;

    return score.clamp(0.0, 1.0);
  }

  // 计算文本相似度
  double _calculateTextSimilarity(Node node, String userQuery) {
    final queryWords = _extractWords(userQuery.toLowerCase());
    final nodeWords = _extractWords('${node.name} ${node.type}'.toLowerCase());

    if (queryWords.isEmpty || nodeWords.isEmpty) return 0.0;

    // Jaccard相似度
    final intersection = queryWords.intersection(nodeWords).length;
    final union = queryWords.union(nodeWords).length;

    final jaccardSimilarity = union > 0 ? intersection / union : 0.0;

    // 关键词匹配加分
    double keywordBonus = 0.0;
    for (final word in queryWords) {
      if (node.name.toLowerCase().contains(word)) {
        keywordBonus += 0.2;
      }
    }

    return (jaccardSimilarity + keywordBonus).clamp(0.0, 1.0);
  }

  // 提取词语
  Set<String> _extractWords(String text) {
    final words = RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where((word) => word.length > 1)
        .toSet();
    return words;
  }

  // 获取关系权重
  double _getRelationWeight(String edgeType, bool isOutgoing) {
    final weights = {
      'hasProperty': 0.9,     // 具有属性
      'belongsTo': 0.8,       // 属于
      'isTypeOf': 0.7,        // 是...类型
      'relatedTo': 0.6,       // 相关于
      'competesWith': 0.8,    // 竞争关系
      'contains': 0.7,        // 包含
      'supports': 0.6,        // 支持
      'requires': 0.5,        // 需要
    };

    final baseWeight = weights[edgeType] ?? 0.5;
    // 出边权重稍高于入边
    return isOutgoing ? baseWeight : baseWeight * 0.9;
  }

  // 获取节点类型权重
  double _getNodeTypeWeight(String nodeType, String userQuery) {
    final query = userQuery.toLowerCase();

    // 根据查询内容判断节点类型的重要性
    final typeImportance = {
      'product': query.contains('产品') || query.contains('手机') ? 1.0 : 0.7,
      'brand': query.contains('品牌') || query.contains('牌子') ? 1.0 : 0.8,
      'feature': query.contains('功能') || query.contains('特性') ? 1.0 : 0.6,
      'price': query.contains('价格') || query.contains('钱') ? 1.0 : 0.5,
      'store': query.contains('店') || query.contains('商店') ? 1.0 : 0.4,
      'review': query.contains('评价') || query.contains('怎么样') ? 0.9 : 0.3,
    };

    return typeImportance[nodeType.toLowerCase()] ?? 0.5;
  }

  // 计算属性匹配度
  double _calculateAttributeMatch(Node node, String userQuery) {
    double matchScore = 0.0;
    final queryLower = userQuery.toLowerCase();

    for (final entry in node.attributes.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value.toLowerCase();

      if (queryLower.contains(key) || queryLower.contains(value)) {
        matchScore += 0.3;
      }

      // 特殊属性加权
      if (key.contains('price') || key.contains('价格')) {
        if (queryLower.contains('钱') || queryLower.contains('价格')) {
          matchScore += 0.4;
        }
      }
    }

    return matchScore.clamp(0.0, 1.0);
  }

  // 多维度节点比较
  int _compareNodeRelevance(NodeRelevance a, NodeRelevance b, String userQuery) {
    // 1. 主要按相关性分数排序
    final scoreDiff = b.score.compareTo(a.score);
    if (scoreDiff != 0) return scoreDiff;

    // 2. 相同分数时，优先选择深度较浅的
    final depthDiff = a.depth.compareTo(b.depth);
    if (depthDiff != 0) return depthDiff;

    // 3. 最后按节点类型重要性排序
    final typeWeightA = _getNodeTypeWeight(a.node.type, userQuery);
    final typeWeightB = _getNodeTypeWeight(b.node.type, userQuery);
    return typeWeightB.compareTo(typeWeightA);
  }

  // 智能信息过滤：去除冗余信息
  List<NodeRelevance> filterRedundantNodes(List<NodeRelevance> nodes) {
    final filtered = <NodeRelevance>[];
    final seenTypes = <String, int>{};

    for (final node in nodes) {
      final type = node.node.type;
      final typeCount = seenTypes[type] ?? 0;

      // 限制每种类型的节点数量
      final maxPerType = type == 'product' ? 5 : 3;

      if (typeCount < maxPerType) {
        filtered.add(node);
        seenTypes[type] = typeCount + 1;
      }
    }

    return filtered;
  }
}
