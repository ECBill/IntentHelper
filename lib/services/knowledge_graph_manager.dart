/// 知识图谱管理服务
/// 独立的知识图谱数据生成和管理模块，与其他子模块保持一致的架构

import 'dart:async';
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/models/human_understanding_models.dart';

/// 知识图谱数据结构
class KnowledgeGraphData {
  final List<Map<String, dynamic>> entities;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> relations;
  final List<String> insights;
  final List<String> queryKeywords;
  final int totalEntityCount;
  final int totalEventCount;
  final int totalRelationCount;
  final DateTime generatedAt;
  final bool hasData;

  KnowledgeGraphData({
    required this.entities,
    required this.events,
    required this.relations,
    required this.insights,
    required this.queryKeywords,
    required this.totalEntityCount,
    required this.totalEventCount,
    required this.totalRelationCount,
    required this.generatedAt,
    required this.hasData,
  });

  Map<String, dynamic> toJson() => {
    'entities': entities,
    'events': events,
    'relations': relations,
    'insights': insights,
    'keywords_used': queryKeywords,
    'entity_count': totalEntityCount,
    'event_count': totalEventCount,
    'relation_count': totalRelationCount,
    'relevant_entity_count': entities.length,
    'relevant_event_count': events.length,
    'generated_at': generatedAt.millisecondsSinceEpoch,
    'has_data': hasData,
    'is_empty': false,
  };
}

class KnowledgeGraphManager {
  static final KnowledgeGraphManager _instance = KnowledgeGraphManager._internal();
  factory KnowledgeGraphManager() => _instance;
  KnowledgeGraphManager._internal();

  bool _initialized = false;
  KnowledgeGraphData? _currentData;
  final Set<String> _currentQueryKeywords = {};

  // 统计信息
  int _totalGenerationCount = 0;
  int _totalEntityMatches = 0;
  int _totalEventMatches = 0;
  DateTime? _lastUpdateTime;

  /// 初始化知识图谱管理器
  Future<void> initialize() async {
    if (_initialized) {
      print('[KnowledgeGraphManager] ✅ 知识图谱管理器已初始化');
      return;
    }

    print('[KnowledgeGraphManager] 🚀 初始化知识图谱管理器...');

    try {
      // 生成初始数据
      await _generateInitialData();

      _initialized = true;
      print('[KnowledgeGraphManager] ✅ 知识图谱管理器初始化完成');
    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 初始化失败: $e');
      rethrow;
    }
  }

  /// 生成初始数据
  Future<void> _generateInitialData() async {
    try {
      // 使用基础关键词生成初始数据
      final basicKeywords = ['系统', '对话', '分析', '理解', '用户'];
      await updateKnowledgeGraph(basicKeywords, [], []);
    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 生成初始数据失败: $e');
    }
  }

  /// 更新知识图谱数据
  Future<void> updateKnowledgeGraph(
    List<String> topicKeywords,
    List<String> entityKeywords,
    List<String> intentEntities,
  ) async {
    if (!_initialized) {
      print('[KnowledgeGraphManager] ⚠️ 管理器未初始化');
      return;
    }

    try {
      print('[KnowledgeGraphManager] 🔄 更新知识图谱数据...');

      // 合并所有关键词
      final allKeywords = <String>{};
      allKeywords.addAll(topicKeywords.map((k) => k.trim().toLowerCase()));
      allKeywords.addAll(entityKeywords.map((k) => k.trim().toLowerCase()));
      allKeywords.addAll(intentEntities.map((k) => k.trim().toLowerCase()));

      // 过滤关键词
      final validKeywords = allKeywords.where((keyword) =>
        keyword.isNotEmpty &&
        keyword.length >= 1 &&
        keyword.length <= 50
      ).take(30).toList();

      print('[KnowledgeGraphManager] 🔍 使用${validKeywords.length}个关键词查询');

      // 更新当前查询关键词
      _currentQueryKeywords.clear();
      _currentQueryKeywords.addAll(validKeywords);

      // 生成知识图谱数据
      _currentData = await _generateKnowledgeGraphData(validKeywords);
      _lastUpdateTime = DateTime.now();
      _totalGenerationCount++;

      print('[KnowledgeGraphManager] ✅ 知识图谱更新完成: ${_currentData!.entities.length}实体, ${_currentData!.events.length}事件');
    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 更新知识图谱失败: $e');
    }
  }

  /// 生成知识图谱数据
  Future<KnowledgeGraphData> _generateKnowledgeGraphData(List<String> keywords) async {
    // 🔥 新增：开始计时
    final stopwatch = Stopwatch()..start();

    try {
      final objectBox = ObjectBoxService();
      final allNodes = objectBox.queryNodes();
      final allEvents = objectBox.queryEventNodes();
      final allEdges = objectBox.queryEdges();

      print('[KnowledgeGraphManager] 📊 数据库统计: ${allNodes.length}节点, ${allEvents.length}事件, ${allEdges.length}边');

      final relatedEntityNodes = <Node>[];
      final relatedEventNodes = <EventNode>[];
      final entityIds = <String>{};
      final eventIds = <String>{};

      // 实体匹配
      for (final node in allNodes) {
        bool isMatched = false;

        for (final keyword in keywords) {
          if (_isEntityMatched(node, keyword)) {
            isMatched = true;
            break;
          }
        }

        if (isMatched && !entityIds.contains(node.id)) {
          relatedEntityNodes.add(node);
          entityIds.add(node.id);
        }
      }

      // 如果关键词匹配的实体不够，补充最近的实体
      if (relatedEntityNodes.length < 5 && allNodes.isNotEmpty) {
        final recentNodes = allNodes.take(10).toList();
        for (final node in recentNodes) {
          if (!entityIds.contains(node.id)) {
            relatedEntityNodes.add(node);
            entityIds.add(node.id);
            if (relatedEntityNodes.length >= 5) break;
          }
        }
        print('[KnowledgeGraphManager] 📈 补充了${relatedEntityNodes.length}个最近实体');
      }

      // 基于实体查找相关事件
      for (final entityNode in relatedEntityNodes) {
        final entityEventRelations = objectBox.queryEventEntityRelations(entityId: entityNode.id);

        for (final relation in entityEventRelations.take(5)) {
          final event = objectBox.findEventNodeById(relation.eventId);
          if (event != null && !eventIds.contains(event.id)) {
            relatedEventNodes.add(event);
            eventIds.add(event.id);
          }
        }
      }

      // 如果还是没有事件，直接取最近的事件
      if (relatedEventNodes.isEmpty && allEvents.isNotEmpty) {
        final recentEvents = allEvents.take(5).toList();
        relatedEventNodes.addAll(recentEvents);
        print('[KnowledgeGraphManager] 📈 补充了${recentEvents.length}个最近事件');
      }

      // 生成实体数据
      final entities = relatedEntityNodes.map((node) => {
        'name': node.name,
        'type': node.type,
        'attributes_count': node.attributes.length,
        'aliases': List<String>.from(node.aliases),
        'canonical_name': node.canonicalName,
      }).toList();

      // 生成事件数据
      final events = relatedEventNodes.map((event) => {
        'name': event.name,
        'type': event.type,
        'description': event.description ?? '',
        'location': event.location ?? '',
        'start_time': event.startTime?.toIso8601String() ?? '',
        'formatted_date': _formatEventDate(event.startTime ?? event.lastUpdated),
      }).toList();

      // 生成关系数据
      final relations = <Map<String, dynamic>>[];
      for (final entityNode in relatedEntityNodes) {
        final entityEventRelations = objectBox.queryEventEntityRelations(entityId: entityNode.id);
        for (final relation in entityEventRelations) {
          final event = relatedEventNodes.firstWhere(
            (e) => e.id == relation.eventId,
            orElse: () => EventNode(id: '', name: '', type: '', lastUpdated: DateTime.now(), sourceContext: ''),
          );
          if (event.name.isNotEmpty) {
            relations.add({
              'source': entityNode.name,
              'target': event.name,
              'relation_type': relation.role,
              'entity_type': entityNode.type,
              'event_type': event.type,
            });
          }
        }
      }

      // 生成洞察
      final insights = <String>[];
      insights.add('成功检索到${relatedEntityNodes.length}个相关实体和${relatedEventNodes.length}个相关事件');

      if (relatedEventNodes.isNotEmpty) {
        insights.add('最近的事件记录: ${events.first['name']}');
      }

      if (keywords.isNotEmpty) {
        insights.add('基于${keywords.length}个活跃主题关键词进行智能匹配');
      }

      // 更新统计
      _totalEntityMatches += relatedEntityNodes.length;
      _totalEventMatches += relatedEventNodes.length;

      // 🔥 新增：计算查询耗时并输出日志
      stopwatch.stop();
      final queryTimeMs = stopwatch.elapsedMilliseconds;
      print('[KnowledgeGraphManager] ⏱️ 知识图谱查询完成，耗时: ${queryTimeMs}ms (查询${keywords.length}个关键词，匹配到${relatedEntityNodes.length}个实体和${relatedEventNodes.length}个事件)');

      return KnowledgeGraphData(
        entities: entities,
        events: events,
        relations: relations,
        insights: insights,
        queryKeywords: List<String>.from(keywords),
        totalEntityCount: allNodes.length,
        totalEventCount: allEvents.length,
        totalRelationCount: allEdges.length,
        generatedAt: DateTime.now(),
        hasData: entities.isNotEmpty || events.isNotEmpty,
      );

    } catch (e) {
      // 🔥 新增：异常情况下也记录耗时
      stopwatch.stop();
      final queryTimeMs = stopwatch.elapsedMilliseconds;
      print('[KnowledgeGraphManager] ❌ 生成知识图谱数据失败 (耗时: ${queryTimeMs}ms): $e');

      // 返回空数据结构
      return KnowledgeGraphData(
        entities: [],
        events: [],
        relations: [],
        insights: ['数据生成遇到问题，但系统仍在正常运行...', '请稍后刷新或联系技术支持'],
        queryKeywords: [],
        totalEntityCount: 0,
        totalEventCount: 0,
        totalRelationCount: 0,
        generatedAt: DateTime.now(),
        hasData: false,
      );
    }
  }

  /// 判断实体是否匹配关键词
  bool _isEntityMatched(Node node, String keyword) {
    return node.name.toLowerCase().contains(keyword) ||
           keyword.contains(node.name.toLowerCase()) ||
           node.canonicalName.toLowerCase().contains(keyword) ||
           keyword.contains(node.canonicalName.toLowerCase()) ||
           node.aliases.any((alias) =>
             alias.toLowerCase().contains(keyword) ||
             keyword.contains(alias.toLowerCase())
           );
  }

  /// 格式化事件日期
  String _formatEventDate(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      return '今天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}周前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  /// 获取当前知识图谱数据
  KnowledgeGraphData? getCurrentData() {
    return _currentData;
  }

  /// 获取当前查询关键词
  Set<String> getCurrentKeywords() {
    return Set<String>.from(_currentQueryKeywords);
  }

  /// 搜索相关知识图谱信息
  List<Map<String, dynamic>> searchKnowledgeGraph(String query) {
    if (_currentData == null) return [];

    final results = <Map<String, dynamic>>[];
    final queryLower = query.toLowerCase();

    // 搜索实体
    for (final entity in _currentData!.entities) {
      final name = entity['name']?.toString().toLowerCase() ?? '';
      final type = entity['type']?.toString().toLowerCase() ?? '';
      if (name.contains(queryLower) || type.contains(queryLower)) {
        results.add({
          'type': 'entity',
          'data': entity,
          'match_field': name.contains(queryLower) ? 'name' : 'type',
        });
      }
    }

    // 搜索事件
    for (final event in _currentData!.events) {
      final name = event['name']?.toString().toLowerCase() ?? '';
      final description = event['description']?.toString().toLowerCase() ?? '';
      if (name.contains(queryLower) || description.contains(queryLower)) {
        results.add({
          'type': 'event',
          'data': event,
          'match_field': name.contains(queryLower) ? 'name' : 'description',
        });
      }
    }

    return results;
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _initialized,
      'total_generation_count': _totalGenerationCount,
      'total_entity_matches': _totalEntityMatches,
      'total_event_matches': _totalEventMatches,
      'current_keywords_count': _currentQueryKeywords.length,
      'current_entities_count': _currentData?.entities.length ?? 0,
      'current_events_count': _currentData?.events.length ?? 0,
      'current_relations_count': _currentData?.relations.length ?? 0,
      'last_update_time': _lastUpdateTime?.toIso8601String(),
      'has_current_data': _currentData != null,
    };
  }

  /// 重置统计数据
  void resetStatistics() {
    print('[KnowledgeGraphManager] 🔄 重置统计数据...');
    _totalGenerationCount = 0;
    _totalEntityMatches = 0;
    _totalEventMatches = 0;
    _lastUpdateTime = null;
    print('[KnowledgeGraphManager] ✅ 统计数据已重置');
  }

  /// 导出知识图谱数据
  Map<String, dynamic> exportData() {
    return {
      'current_data': _currentData?.toJson(),
      'statistics': getStatistics(),
      'query_keywords': List<String>.from(_currentQueryKeywords),
      'export_timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 释放资源
  void dispose() {
    print('[KnowledgeGraphManager] 🔄 开始释放知识图谱管理器资源...');

    try {
      _currentData = null;
      _currentQueryKeywords.clear();
      _initialized = false;

      print('[KnowledgeGraphManager] ✅ 知识图谱管理器资源释放完成');
    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 释放资源时出现错误: $e');
    }
  }
}
