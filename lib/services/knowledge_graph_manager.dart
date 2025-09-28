import 'dart:convert';
import 'dart:math';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/services/embedding_service.dart';
import 'package:app/models/human_understanding_models.dart' as hum;
import 'package:app/models/graph_models.dart';

/// 知识图谱管理器 - 基于向量匹配的查询
class KnowledgeGraphManager {
  final KnowledgeGraphService _service = KnowledgeGraphService();
  final EmbeddingService _embeddingService = EmbeddingService();
  KnowledgeGraphManager();

  List<hum.Topic> _lastTopics = [];
  String? _lastTopicsHash;
  Map<String, dynamic>? _cachedResult;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  /// 初始化（预留，实际可扩展）
  Future<void> initialize() async {
    // 可扩展初始化逻辑
  }

  /// 主题追踪内容变化时调用，自动查找知识图谱内容
  /// 新版：严格绑定 EmbeddingService，事件-主题映射清晰，支持排序筛选
  Future<Map<String, dynamic>> updateActiveTopics(
    List<hum.Topic> activeTopics, {
    int topK = 20,
    double threshold = 0.3,
    String sortBy = 'similarity', // or 'time'
  }) async {
    final topicsHash = _generateTopicsHash(activeTopics);
    if (_lastTopicsHash == topicsHash && _cachedResult != null && _lastCacheTime != null) {
      final now = DateTime.now();
      if (now.difference(_lastCacheTime!) < _cacheValidDuration) {
        print('[KnowledgeGraphManager] 🔄 使用缓存的知识图谱结果 (hash=$topicsHash)');
        return _cachedResult!;
      }
    }
    print('[KnowledgeGraphManager] 🔍 主题追踪内容变化，开始向量检索 (hash=$topicsHash)');
    if (activeTopics.isEmpty) {
      print('[KnowledgeGraphManager] ⚠️ 没有活跃主题，返回空结果');
      return _buildEmptyResult();
    }
    // 生成主题查询文本
    final queryTexts = activeTopics.map((t) => _topicToQueryText(t)).toList();
    // 生成主题向量
    final topicVectors = <List<double>>[];
    for (final text in queryTexts) {
      print('[KnowledgeGraphManager] 生成主题向量: $text');
      final vec = await _embeddingService.generateTextEmbedding(text);
      if (vec != null) {
        topicVectors.add(vec);
      } else {
        print('[KnowledgeGraphManager] 生成主题向量失败: $text');
      }
    }
    // 获取知识图谱所有事件
    final allEvents = await _service.getAllEvents();
    // 事件向量预处理
    for (final event in allEvents) {
      if (event.embedding == null || event.embedding!.isEmpty) {
        print('[KnowledgeGraphManager] 生成事件向量: [33m${event.name ?? event.id}[0m');
        final emb = await _embeddingService.generateEventEmbedding(event);
        if (emb != null && emb.isNotEmpty) {
          event.embedding = emb;
        } else {
          print('[KnowledgeGraphManager] 生成事件向量失败: ${event.name ?? event.id}');
        }
      }
    }
    // 针对每个主题做向量检索，记录事件-主题映射
    final topicResults = <Map<String, dynamic>>[];
    final eventToTopicMap = <String, Map<String, dynamic>>{}; // eventId -> {topicIndex, similarity}
    for (int i = 0; i < topicVectors.length; i++) {
      final qv = topicVectors[i];
      final results = await _embeddingService.findSimilarEventsAdvanced(
        qv,
        allEvents,
        topK: topK,
        threshold: threshold,
        useWhitening: true,
        useDiversity: true,
      );
      // 记录事件-主题映射
      for (final e in results) {
        final eventId = e['id']?.toString() ?? e['event_id']?.toString() ?? '';
        if (eventId.isNotEmpty) {
          if (!eventToTopicMap.containsKey(eventId) || (e['similarity_score'] ?? 0.0) > (eventToTopicMap[eventId]?['similarity_score'] ?? 0.0)) {
            eventToTopicMap[eventId] = {
              'topicIndex': i,
              'similarity_score': e['similarity_score'] ?? 0.0,
            };
          }
        }
      }
      topicResults.add({'events': results, 'entities': [], 'relations': []});
    }
    // 格式化结果，事件带上匹配主题
    final formattedResult = _formatVectorResultsWithTopicMap({'topic_results': topicResults}, activeTopics, eventToTopicMap, sortBy: sortBy);
    // 缓存
    _cachedResult = formattedResult;
    _lastCacheTime = DateTime.now();
    _lastTopics = List.from(activeTopics);
    _lastTopicsHash = topicsHash;
    print('[KnowledgeGraphManager] ✅ 向量检索完成 (hash=$topicsHash)');
    return formattedResult;
  }

  /// 生成主题内容 hash
  String _generateTopicsHash(List<hum.Topic> topics) {
    final content = topics.map((t) => _topicToQueryText(t)).join('|');
    return content.hashCode.toString();
  }

  /// 主题转查询文本
  String _topicToQueryText(hum.Topic topic) {
    final queryComponents = <String>[];
    queryComponents.add(topic.name);
    if (topic.keywords.isNotEmpty) queryComponents.addAll(topic.keywords);
    if (topic.entities.isNotEmpty) queryComponents.addAll(topic.entities);
    if (topic.context != null) {
      final ctx = topic.context as Map<String, dynamic>;
      if (ctx['importance'] != null) queryComponents.add(ctx['importance'].toString());
      if (ctx['emotional_tone'] != null) queryComponents.add(ctx['emotional_tone'].toString());
    }
    return queryComponents.join(' ');
  }

  /// 刷新缓存（外部可调用）
  void refreshCache() {
    _cachedResult = null;
    _lastCacheTime = null;
    _lastTopics = [];
    _lastTopicsHash = null;
    print('[KnowledgeGraphManager] 🔄 缓存已清除');
  }

  /// 格式化向量查询结果，事件带上匹配主题信息
  Map<String, dynamic> _formatVectorResultsWithTopicMap(
    Map<String, dynamic> vectorResults,
    List<hum.Topic> activeTopics,
    Map<String, Map<String, dynamic>> eventToTopicMap,
    {String sortBy = 'similarity'}
  ) {
    final allEvents = <Map<String, dynamic>>[];
    final allEntities = <Map<String, dynamic>>[];
    final allRelations = <Map<String, dynamic>>[];
    final topicMatchStats = <Map<String, dynamic>>[];
    final topicResults = vectorResults['topic_results'] as List? ?? [];
    for (int i = 0; i < topicResults.length && i < activeTopics.length; i++) {
      final topicResult = topicResults[i] as Map<String, dynamic>;
      final topic = activeTopics[i];
      final events = topicResult['events'] as List? ?? [];
      final processedEvents = events.map<Map<String, dynamic>>((event) {
        final eventMap = event as Map<String, dynamic>;
        final eventId = eventMap['id']?.toString() ?? eventMap['event_id']?.toString() ?? '';
        final matchInfo = eventToTopicMap[eventId] ?? {};
        return {
          ...eventMap,
          'matched_by_topic': topic.name,
          'matched_by_topic_index': i,
          'matched_by_topic_weight': topic.weight,
          'topic_context': {
            'keywords': topic.keywords,
            'entities': topic.entities,
            'state': topic.state.toString(),
            'context': topic.context ?? {},
          },
          'match_details': {
            'topic_name': topic.name,
            'similarity_score': eventMap['similarity_score'] ?? 0.0,
            'matched_text': eventMap['matched_text'] ?? '',
            'vector_distance': eventMap['vector_distance'] ?? 0.0,
            'best_match_topic_index': matchInfo['topicIndex'] ?? i,
            'best_match_similarity': matchInfo['similarity_score'] ?? eventMap['similarity_score'] ?? 0.0,
          },
        };
      }).toList();
      allEvents.addAll(processedEvents);
      // 实体、关系同理（略）
      final entities = (topicResult['entities'] as List? ?? []).map((e) => e as Map<String, dynamic>).toList();
      allEntities.addAll(entities);
      final relations = (topicResult['relations'] as List? ?? []).map((e) => e as Map<String, dynamic>).toList();
      allRelations.addAll(relations);
      topicMatchStats.add({
        'topic_name': topic.name,
        'topic_weight': topic.weight,
        'topic_index': i,
        'events_count': processedEvents.length,
        'entities_count': entities.length,
        'relations_count': relations.length,
        'avg_similarity': _calculateAverageSimilarity([
          ...processedEvents,
          ...entities, 
          ...relations
        ]),
        'max_similarity': _calculateMaxSimilarity([
          ...processedEvents,
          ...entities,
          ...relations
        ]),
      });
    }
    // 排序
    if (sortBy == 'similarity') {
      allEvents.sort((a, b) => (b['similarity_score'] as double).compareTo(a['similarity_score'] as double));
    } else if (sortBy == 'time') {
      allEvents.sort((a, b) => ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));
    }
    // 洞察
    final insights = _generateVectorMatchInsights(topicMatchStats, allEvents.cast<Map<String, dynamic>>(), allEntities.cast<Map<String, dynamic>>());
    return {
      'generated_at': DateTime.now().millisecondsSinceEpoch,
      'has_data': allEvents.isNotEmpty || allEntities.isNotEmpty || allRelations.isNotEmpty,
      'query_method': 'vector_similarity',
      'active_topics_count': activeTopics.length,
      'total_events': allEvents.length,
      'total_entities': allEntities.length,
      'total_relations': allRelations.length,
      'topic_match_stats': topicMatchStats,
      'events': allEvents,
      'entities': allEntities,
      'relations': allRelations,
      'insights': insights,
      'query_info': {
        'topics_queried': activeTopics.map((t) => {
          'name': t.name,
          'weight': t.weight,
          'keywords_count': t.keywords.length,
          'entities_count': t.entities.length,
        }).toList(),
        'total_query_texts': topicResults.length,
      },
    };
  }


  /// 计算平均相似度
  double _calculateAverageSimilarity(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 0.0;

    final total = items.fold<double>(0.0, (sum, item) {
      return sum + (item['similarity_score'] as double? ?? 0.0);
    });

    return total / items.length;
  }

  /// 计算最大相似度
  double _calculateMaxSimilarity(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 0.0;

    return items.fold<double>(0.0, (max, item) {
      final score = item['similarity_score'] as double? ?? 0.0;
      return score > max ? score : max;
    });
  }

  /// 生成向量匹配洞察
  List<String> _generateVectorMatchInsights(
    List<Map<String, dynamic>> topicStats,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> entities
  ) {
    final insights = <String>[];

    if (topicStats.isEmpty) {
      insights.add('没有活跃主题参与匹配');
      return insights;
    }

    // 分析最活跃的主题
    topicStats.sort((a, b) => (b['max_similarity'] as double).compareTo(a['max_similarity'] as double));
    final bestTopic = topicStats.first;

    insights.add('主题"${bestTopic['topic_name']}"具有最高的向量匹配度 (${(bestTopic['max_similarity'] as double).toStringAsFixed(2)})');

    // 分析事件分布
    if (events.isNotEmpty) {
      final highSimilarityEvents = events.where((e) => (e['similarity_score'] as double) > 0.7).length;
      if (highSimilarityEvents > 0) {
        insights.add('发现 $highSimilarityEvents 个高相关性事件 (相似度 > 0.7)');
      }

      // 分析时间分布
      final recentEvents = events.where((e) {
        final timestamp = e['timestamp'] as int?;
        if (timestamp == null) return false;
        final eventTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final daysDiff = DateTime.now().difference(eventTime).inDays;
        return daysDiff <= 7;
      }).length;

      if (recentEvents > 0) {
        insights.add('最近一周内有 $recentEvents 个相关事件');
      }
    }

    // 分析主题覆盖度
    final topicsWithMatches = topicStats.where((t) =>
      (t['events_count'] as int) > 0 ||
      (t['entities_count'] as int) > 0
    ).length;

    insights.add('$topicsWithMatches/${topicStats.length} 个主题找到了相关内容');

    // 分析向量匹配质量
    if (events.isNotEmpty) {
      final avgSimilarity = events.fold<double>(0.0, (sum, e) =>
        sum + (e['similarity_score'] as double)
      ) / events.length;

      if (avgSimilarity > 0.6) {
        insights.add('整体匹配质量较高 (平均相似度: ${avgSimilarity.toStringAsFixed(2)})');
      } else if (avgSimilarity > 0.4) {
        insights.add('匹配质量中等 (平均相似度: ${avgSimilarity.toStringAsFixed(2)})');
      } else {
        insights.add('匹配质量偏低，可能需要更精确的主题描述');
      }
    }

    return insights;
  }

  /// 构建空结果
  Map<String, dynamic> _buildEmptyResult() {
    return {
      'generated_at': DateTime.now().millisecondsSinceEpoch,
      'has_data': false,
      'query_method': 'vector_similarity',
      'active_topics_count': 0,
      'total_events': 0,
      'total_entities': 0,
      'total_relations': 0,
      'topic_match_stats': [],
      'events': [],
      'entities': [],
      'relations': [],
      'insights': ['没有活跃主题可用于匹配'],
      'query_info': {
        'topics_queried': [],
        'total_query_texts': 0,
      },
    };
  }

  /// 构建错误结果
  Map<String, dynamic> _buildErrorResult(String error) {
    return {
      'generated_at': DateTime.now().millisecondsSinceEpoch,
      'has_data': false,
      'query_method': 'vector_similarity',
      'error': error,
      'active_topics_count': 0,
      'total_events': 0,
      'total_entities': 0,
      'total_relations': 0,
      'topic_match_stats': [],
      'events': [],
      'entities': [],
      'relations': [],
      'insights': ['查询过程中发生错误: $error'],
      'query_info': {
        'topics_queried': [],
        'total_query_texts': 0,
      },
    };
  }


  /// 获取缓存状态
  Map<String, dynamic> getCacheStatus() {
    return {
      'has_cache': _cachedResult != null,
      'cache_time': _lastCacheTime?.toIso8601String(),
      'cache_age_minutes': _lastCacheTime != null
        ? DateTime.now().difference(_lastCacheTime!).inMinutes
        : null,
      'cache_valid': _cachedResult != null && _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!) < _cacheValidDuration,
    };
  }
}