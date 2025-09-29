import 'dart:async';
import 'dart:math' as math;
import 'package:app/services/embedding_service.dart';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/models/graph_models.dart';

/// 知识图谱向量查询管理器
class KnowledgeGraphManager {
  static final KnowledgeGraphManager _instance = KnowledgeGraphManager._internal();
  factory KnowledgeGraphManager() => _instance;
  KnowledgeGraphManager._internal();

  final EmbeddingService _embeddingService = EmbeddingService();
  final KnowledgeGraphService _kgService = KnowledgeGraphService();

  List<String> _lastTopics = [];
  String? _lastTopicsHash;
  Map<String, dynamic>? _cachedResult;
  DateTime? _lastQueryTime;

  /// 主动刷新缓存
  void refreshCache() {
    _cachedResult = null;
    _lastTopics = [];
    _lastTopicsHash = null;
    _lastQueryTime = null;
  }

  /// 主题追踪内容变化时调用，自动查找并缓存结果
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

    final List<Map<String, dynamic>> allResults = [];
    final Set<String> seenEventIds = {};
    for (final topic in topics) {
      final results = await KnowledgeGraphService.searchEventsByText(
        topic,
        topK: 30,
        similarityThreshold: 0.2,
      );
      print('[KnowledgeGraphManager] Topic "$topic" got ${results.length} results.');
      for (final result in results) {
        final eventNode = result['event'] as EventNode;
        final id = eventNode.id;
        if (id.isNotEmpty && !seenEventIds.contains(id)) {
          final eventMap = {
            'id': eventNode.id,
            'title': eventNode.name,
            'name': eventNode.name,
            'type': eventNode.type,
            'description': eventNode.description,
            'similarity': result['similarity'],
            'matched_topic': topic,
            'startTime': eventNode.startTime?.toIso8601String(),
            'endTime': eventNode.endTime?.toIso8601String(),
            'location': eventNode.location,
            'purpose': eventNode.purpose,
            'result': eventNode.result,
            'sourceContext': eventNode.sourceContext,
          };
          allResults.add(eventMap);
          seenEventIds.add(id);
        }
      }
      if (results.isNotEmpty) {
        final eventNode = results[0]['event'] as EventNode;
        print('[KnowledgeGraphManager] Topic "$topic" sample event: '
          'id=${eventNode.id}, title=${eventNode.name}, score=${results[0]['similarity']}');
      }
    }

    print('[KnowledgeGraphManager] All merged results count: ${allResults.length}');
    if (allResults.isNotEmpty) {
      print('[KnowledgeGraphManager] First merged event: '
        'id=${allResults[0]['id']}, title=${allResults[0]['title']}, score=${allResults[0]['similarity']}, matched_topic=${allResults[0]['matched_topic']}');
    }

    allResults.sort((a, b) {
      final sa = a['similarity'] ?? a['score'] ?? 0.0;
      final sb = b['similarity'] ?? b['score'] ?? 0.0;
      return sb.compareTo(sa);
    });

    final topResults = allResults.take(20).toList();

    print('[KnowledgeGraphManager] Final topResults count: ${topResults.length}');
    if (topResults.isNotEmpty) {
      print('[KnowledgeGraphManager] First topResult: '
        'id=${topResults[0]['id']}, title=${topResults[0]['title']}, score=${topResults[0]['similarity']}, matched_topic=${topResults[0]['matched_topic']}');
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
    print('[KnowledgeGraphManager] Cached result: $_cachedResult');
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
