import 'dart:convert';
import 'dart:math';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/models/human_understanding_models.dart' as hum;

/// 知识图谱管理器 - 基于向量匹配的查询
class KnowledgeGraphManager {
  final KnowledgeGraphService _service = KnowledgeGraphService();
  KnowledgeGraphManager();

  // 添加 initialize 方法
  Future<void> initialize() async {
    // 初始化知识图谱管理器
    print('[KnowledgeGraphManager] 初始化完成');
  }

  Map<String, dynamic>? _cachedResult;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  /// 基于活跃主题进行向量匹配查询
  Future<Map<String, dynamic>> queryByActiveTopics(List<hum.Topic> activeTopics) async {
    // 检查缓存
    if (_cachedResult != null && _lastCacheTime != null) {
      final now = DateTime.now();
      if (now.difference(_lastCacheTime!) < _cacheValidDuration) {
        print('[KnowledgeGraphManager] 🔄 使用缓存的知识图谱结果');
        return _cachedResult!;
      }
    }

    try {
      print('[KnowledgeGraphManager] 🔍 开始基于活跃主题进行向量匹配查询...');

      if (activeTopics.isEmpty) {
        print('[KnowledgeGraphManager] ⚠️ 没有活跃主题，返回空结果');
        return _buildEmptyResult();
      }

      // 构建查询请求
      final queryRequest = _buildVectorQueryRequest(activeTopics);

      // 执行向量匹配查询
      final vectorResults = await _service.queryByVectorSimilarity( queryRequest);

      // 处理和格式化结果
      final formattedResult = _formatVectorResults(vectorResults, activeTopics);

      // 缓存结果
      _cachedResult = formattedResult;
      _lastCacheTime = DateTime.now();

      print('[KnowledgeGraphManager] ✅ 向量匹配查询完成');
      return formattedResult;

    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 向量匹配查询失败: $e');
      return _buildErrorResult(e.toString());
    }
  }

  /// 构建向量查询请求
  Map<String, dynamic> _buildVectorQueryRequest(List<hum.Topic> activeTopics) {
    final queryTexts = <String>[];
    final topicMappings = <Map<String, dynamic>>[];

    for (final topic in activeTopics) {
      // 构建主题的查询文本（结合主题名称、关键词和实体）
      final queryComponents = <String>[];

      // 添加主题名称
      queryComponents.add(topic.name);

      // 添加关键词
      if (topic.keywords.isNotEmpty) {
        queryComponents.addAll(topic.keywords);
      }

      // 添加实体
      if (topic.entities.isNotEmpty) {
        queryComponents.addAll(topic.entities);
      }

      // 添加上下文重要信息
      if (topic.context != null) {
        final ctx = topic.context as Map<String, dynamic>;
        if (ctx['importance'] != null) {
          queryComponents.add(ctx['importance'].toString());
        }
        if (ctx['emotional_tone'] != null) {
          queryComponents.add(ctx['emotional_tone'].toString());
        }
      }

      final queryText = queryComponents.join(' ');
      queryTexts.add(queryText);

      // 记录主题映射信息
      topicMappings.add({
        'topic_name': topic.name,
        'topic_weight': topic.weight,
        'topic_state': topic.state.toString(),
        'query_text': queryText,
        'keywords': topic.keywords,
        'entities': topic.entities,
        'context': topic.context ?? {},
      });
    }

    return {
      'query_texts': queryTexts,
      'topic_mappings': topicMappings,
      'similarity_threshold': 0.3, // 相似度阈值
      'max_results_per_topic': 10,
      'include_events': true,
      'include_entities': true,
      'include_relations': true,
    };
  }

  /// 格式化向量查询结果
  Map<String, dynamic> _formatVectorResults(
    Map<String, dynamic> vectorResults,
    List<hum.Topic> activeTopics
  ) {
    final allEvents = <Map<String, dynamic>>[];
    final allEntities = <Map<String, dynamic>>[];
    final allRelations = <Map<String, dynamic>>[];
    final topicMatchStats = <Map<String, dynamic>>[];

    // 处理每个主题的匹配结果
    final topicResults = vectorResults['topic_results'] as List? ?? [];

    for (int i = 0; i < topicResults.length && i < activeTopics.length; i++) {
      final topicResult = topicResults[i] as Map<String, dynamic>;
      final topic = activeTopics[i];

      // 处理事件匹配结果
      final events = topicResult['events'] as List? ?? [];
      final processedEvents = _processEventsForTopic(events, topic, i);
      allEvents.addAll(processedEvents);

      // 处理实体匹配结果
      final entities = topicResult['entities'] as List? ?? [];
      final processedEntities = _processEntitiesForTopic(entities, topic, i);
      allEntities.addAll(processedEntities);

      // 处理关系匹配结果
      final relations = topicResult['relations'] as List? ?? [];
      final processedRelations = _processRelationsForTopic(relations, topic, i);
      allRelations.addAll(processedRelations);

      // 统计该主题的匹配情况
      topicMatchStats.add({
        'topic_name': topic.name,
        'topic_weight': topic.weight,
        'topic_index': i,
        'events_count': processedEvents.length,
        'entities_count': processedEntities.length,
        'relations_count': processedRelations.length,
        'avg_similarity': _calculateAverageSimilarity([
          ...processedEvents,
          ...processedEntities,
          ...processedRelations
        ]),
        'max_similarity': _calculateMaxSimilarity([
          ...processedEvents,
          ...processedEntities,
          ...processedRelations
        ]),
      });
    }

    // 按相似度排序
    allEvents.sort((a, b) => (b['similarity_score'] as double).compareTo(a['similarity_score'] as double));
    allEntities.sort((a, b) => (b['similarity_score'] as double).compareTo(a['similarity_score'] as double));
    allRelations.sort((a, b) => (b['similarity_score'] as double).compareTo(a['similarity_score'] as double));

    // 生成洞察
    final insights = _generateVectorMatchInsights(topicMatchStats, allEvents, allEntities);

    return {
      'generated_at': DateTime.now().millisecondsSinceEpoch,
      'has_data': allEvents.isNotEmpty || allEntities.isNotEmpty || allRelations.isNotEmpty,
      'query_method': 'vector_similarity',
      'active_topics_count': activeTopics.length,

      // 统计信息
      'total_events': allEvents.length,
      'total_entities': allEntities.length,
      'total_relations': allRelations.length,
      'topic_match_stats': topicMatchStats,

      // 详细结果
      'events': allEvents,
      'entities': allEntities,
      'relations': allRelations,

      // 洞察和建议
      'insights': insights,

      // 原始查询信息
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

  /// 处理主题的事件匹配结果
  List<Map<String, dynamic>> _processEventsForTopic(
    List events,
    hum.Topic topic,
    int topicIndex
  ) {
    return events.map<Map<String, dynamic>>((event) {
      final eventMap = event as Map<String, dynamic>;
      return {
        ...eventMap,
        'matched_by_topic': topic.name,
        'matched_by_topic_index': topicIndex,
        'matched_by_topic_weight': topic.weight,
        'topic_context': {
          'keywords': topic.keywords,
          'entities': topic.entities,
          'state': topic.state.toString(),
          'context': topic.context ?? {},
        },
        // 添加匹配详情
        'match_details': {
          'topic_name': topic.name,
          'similarity_score': eventMap['similarity_score'] ?? 0.0,
          'matched_text': eventMap['matched_text'] ?? '',
          'vector_distance': eventMap['vector_distance'] ?? 0.0,
        },
      };
    }).toList();
  }

  /// 处理主题的实体匹配结果
  List<Map<String, dynamic>> _processEntitiesForTopic(
    List entities,
    hum.Topic topic,
    int topicIndex
  ) {
    return entities.map<Map<String, dynamic>>((entity) {
      final entityMap = entity as Map<String, dynamic>;
      return {
        ...entityMap,
        'matched_by_topic': topic.name,
        'matched_by_topic_index': topicIndex,
        'matched_by_topic_weight': topic.weight,
        'topic_context': {
          'keywords': topic.keywords,
          'entities': topic.entities,
          'state': topic.state.toString(),
          'context': topic.context ?? {},
        },
        'match_details': {
          'topic_name': topic.name,
          'similarity_score': entityMap['similarity_score'] ?? 0.0,
          'matched_text': entityMap['matched_text'] ?? '',
          'vector_distance': entityMap['vector_distance'] ?? 0.0,
        },
      };
    }).toList();
  }

  /// 处理主题的关系匹配结果
  List<Map<String, dynamic>> _processRelationsForTopic(
    List relations,
    hum.Topic topic,
    int topicIndex
  ) {
    return relations.map<Map<String, dynamic>>((relation) {
      final relationMap = relation as Map<String, dynamic>;
      return {
        ...relationMap,
        'matched_by_topic': topic.name,
        'matched_by_topic_index': topicIndex,
        'matched_by_topic_weight': topic.weight,
        'match_details': {
          'topic_name': topic.name,
          'similarity_score': relationMap['similarity_score'] ?? 0.0,
        },
      };
    }).toList();
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

  /// 刷新缓存
  void refreshCache() {
    _cachedResult = null;
    _lastCacheTime = null;
    print('[KnowledgeGraphManager] 🔄 缓存已清除');
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