import 'package:app/services/advanced_kg_retrieval.dart';
import 'package:app/services/smart_kg_service.dart';
import 'package:app/models/graph_models.dart';

class AdvancedKGRetrievalService {
  static final AdvancedKGRetrievalService _instance = AdvancedKGRetrievalService._internal();
  factory AdvancedKGRetrievalService() => _instance;
  AdvancedKGRetrievalService._internal();

  final AdvancedKGRetrieval _advancedRetrieval = AdvancedKGRetrieval();

  // 扩展和排序节点
  Future<List<Node>> expandAndRankNodes(List<Node> initialNodes, IntentAnalysis analysis) async {
    try {
      // 提取种子实体ID
      final seedEntityIds = initialNodes.map((node) => node.id).toList();

      if (seedEntityIds.isEmpty) {
        return initialNodes;
      }

      // 使用高级检索进行多层扩散
      final nodeRelevances = await _advancedRetrieval.retrieveRelevantNodes(
        seedEntityIds: seedEntityIds,
        userQuery: analysis.keywords.join(' '),
        intent: analysis.intent.toString().split('.').last,
      );

      // 过滤冗余节点
      final filteredRelevances = _advancedRetrieval.filterRedundantNodes(nodeRelevances);

      // 转换为Node列表并返回
      return filteredRelevances.map((relevance) => relevance.node).toList();
    } catch (e) {
      print('AdvancedKGRetrievalService expandAndRankNodes error: $e');
      // 降级返回原始节点
      return initialNodes;
    }
  }

  // 获取节点的详细相关性信息（用于调试和优化）
  Future<List<NodeRelevance>> getDetailedRelevance(List<Node> initialNodes, IntentAnalysis analysis) async {
    final seedEntityIds = initialNodes.map((node) => node.id).toList();

    if (seedEntityIds.isEmpty) {
      return [];
    }

    return await _advancedRetrieval.retrieveRelevantNodes(
      seedEntityIds: seedEntityIds,
      userQuery: analysis.keywords.join(' '),
      intent: analysis.intent.toString().split('.').last,
    );
  }
}
