import 'dart:async';
import 'dart:math' as math;
import 'package:app/services/embedding_service.dart';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/models/constraint_models.dart';
import 'package:app/services/multi_constraint_retrieval.dart';

/// 知识图谱向量查询管理器
/// 
/// 增强版本：支持多约束动态检索和渐进式更新
class KnowledgeGraphManager {
  static final KnowledgeGraphManager _instance = KnowledgeGraphManager._internal();
  factory KnowledgeGraphManager() => _instance;
  KnowledgeGraphManager._internal();

  final EmbeddingService _embeddingService = EmbeddingService();
  final KnowledgeGraphService _kgService = KnowledgeGraphService();
  final MultiConstraintRetrievalService _retrievalService = MultiConstraintRetrievalService();

  List<String> _lastTopics = [];
  String? _lastTopicsHash;
  Map<String, dynamic>? _cachedResult;
  DateTime? _lastQueryTime;
  
  // 动态节点池 - 维护评分后的节点集合
  List<ScoredNode> _scoredNodePool = [];
  DateTime? _lastPoolUpdate;

  /// 主动刷新缓存
  void refreshCache() {
    _cachedResult = null;
    _lastTopics = [];
    _lastTopicsHash = null;
    _lastQueryTime = null;
    _scoredNodePool = [];
    _lastPoolUpdate = null;
  }

  /// 主题追踪内容变化时调用，自动查找并缓存结果
  /// 
  /// 增强版本：使用多约束检索和动态节点池更新
  Future<void> updateActiveTopics(List<String> topics) async {
    print('[KnowledgeGraphManager] updateActiveTopics called with topics: $topics');
    if (topics.isEmpty) {
      print('[KnowledgeGraphManager] No topics provided, clearing result.');
      _cachedResult = {
        'generated_at': DateTime.now().millisecondsSinceEpoch,
        'active_topics': [],
        'results': [],
      };
      _lastTopics = [];
      _lastTopicsHash = null;
      _lastQueryTime = DateTime.now();
      return;
    }

    // 创建检索上下文
    final context = RetrievalContext(
      focusTopics: topics,
      queryTime: DateTime.now(),
    );

    // 创建默认约束集
    final constraints = _retrievalService.createDefaultConstraints(
      targetTime: DateTime.now(),
    );

    // 使用多约束检索获取新的候选节点
    print('[KnowledgeGraphManager] Performing multi-constraint retrieval...');
    final newScoredNodes = await _retrievalService.retrieveMultipleTopics(
      topics: topics,
      context: context,
      constraints: constraints,
      topKPerTopic: 20,
      finalTopK: 30,
      similarityThreshold: 0.2,
    );

    print('[KnowledgeGraphManager] Retrieved ${newScoredNodes.length} new scored nodes');

    // 与现有节点池合并，保持动态更新
    _scoredNodePool = _retrievalService.mergeAndPrune(
      existingPool: _scoredNodePool,
      newNodes: newScoredNodes,
      maxPoolSize: 20,
      recomputeScores: true, // 重新计算得分以反映时效性
    );

    _lastPoolUpdate = DateTime.now();

    print('[KnowledgeGraphManager] Node pool updated, current size: ${_scoredNodePool.length}');

    // 转换为旧格式以兼容现有UI
    final topResults = _scoredNodePool.map((scoredNode) {
      final eventNode = scoredNode.node;
      return {
        'id': eventNode.id,
        'title': eventNode.name,
        'name': eventNode.name,
        'type': eventNode.type,
        'description': eventNode.description,
        'similarity': scoredNode.embeddingScore,
        'matched_topic': scoredNode.matchedTopic ?? topics.first,
        'startTime': eventNode.startTime?.toIso8601String(),
        'endTime': eventNode.endTime?.toIso8601String(),
        'location': eventNode.location,
        'purpose': eventNode.purpose,
        'result': eventNode.result,
        'sourceContext': eventNode.sourceContext,
        // 优先级评分相关字段
        'priority_score': eventNode.cachedPriorityScore,
        'final_score': scoredNode.compositeScore, // 使用新的综合得分
        'cosine_similarity': scoredNode.embeddingScore,
        'components': {
          'f_time': scoredNode.constraintScores['TemporalProximity'] ?? 0.0,
          'f_react': scoredNode.constraintScores['FreshnessBoost'] ?? 0.0,
          'f_sem': scoredNode.embeddingScore,
        },
        // 新增：约束得分详情
        'constraint_scores': scoredNode.constraintScores,
        'composite_score': scoredNode.compositeScore,
      };
    }).toList();

    print('[KnowledgeGraphManager] Final topResults count: ${topResults.length}');
    if (topResults.isNotEmpty) {
      print('[KnowledgeGraphManager] First topResult: '
        'id=${topResults[0]['id']}, title=${topResults[0]['title']}, '
        'composite_score=${topResults[0]['composite_score']}, '
        'matched_topic=${topResults[0]['matched_topic']}');
    }

    _cachedResult = {
      'generated_at': DateTime.now().millisecondsSinceEpoch,
      'active_topics': topics,
      'results': topResults,
    };
    _lastTopics = List.from(topics);
    _lastTopicsHash = topics.join('|').hashCode.toString();
    _lastQueryTime = DateTime.now();
    print('[KnowledgeGraphManager] updateActiveTopics finished.');
  }

  /// 获取上一次的查询结果（UI直接用）
  Map<String, dynamic>? getLastResult() => _cachedResult;

  /// 初始化（可选，初始化 embedding/model）
  Future<void> initialize() async {
    await _embeddingService.initialize();
  }

  /// 计算余弦相似度
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
