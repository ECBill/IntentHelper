/// 知识图谱管理服务 - 重构版本
/// 修复空白页面、相关性评分和关键词匹配等问题

import 'dart:async';
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/models/human_understanding_models.dart';

/// 知识图谱数据结构 - 重构版
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
  final String status; // 新增：数据状态

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
    this.status = 'success',
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
    'status': status,
    'is_empty': !hasData,
  };
}

class KnowledgeGraphManager {
  static final KnowledgeGraphManager _instance = KnowledgeGraphManager._internal();
  factory KnowledgeGraphManager() => _instance;
  KnowledgeGraphManager._internal();

  bool _initialized = false;
  KnowledgeGraphData? _currentData;
  List<String> _lastQueryKeywords = [];
  final StreamController<KnowledgeGraphData> _dataStreamController = StreamController<KnowledgeGraphData>.broadcast();

  // 缓存机制
  final Map<String, KnowledgeGraphData> _dataCache = {};

  // 统计信息
  int _totalQueries = 0;
  int _cacheHits = 0;
  DateTime? _lastUpdateTime;

  /// 数据更新流
  Stream<KnowledgeGraphData> get dataUpdates => _dataStreamController.stream;

  /// 初始化知识图谱管理器
  Future<void> initialize() async {
    if (_initialized) {
      print('[KnowledgeGraphManager] ✅ 已初始化，跳过重复初始化');
      return;
    }

    print('[KnowledgeGraphManager] 🚀 开始初始化知识图谱管理器...');

    try {
      // 生成空白初始状态，避免空白页面
      _currentData = _createEmptyData();
      _initialized = true;

      // 通知UI更新
      _dataStreamController.add(_currentData!);

      print('[KnowledgeGraphManager] ✅ 知识图谱管理器初始化完成');
    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 初始化失败: $e');
      _currentData = _createErrorData(e.toString());
      _initialized = true;

      // 即使出错也要通知UI
      if (_currentData != null) {
        _dataStreamController.add(_currentData!);
      }
    }
  }

  /// 创建空数据状态
  KnowledgeGraphData _createEmptyData() {
    return KnowledgeGraphData(
      entities: [],
      events: [],
      relations: [],
      insights: ['🔄 系统已准备就绪，等待查询关键词...'],
      queryKeywords: [],
      totalEntityCount: 0,
      totalEventCount: 0,
      totalRelationCount: 0,
      generatedAt: DateTime.now(),
      hasData: false,
      status: 'empty',
    );
  }

  /// 创建错误数据状态
  KnowledgeGraphData _createErrorData(String error) {
    return KnowledgeGraphData(
      entities: [],
      events: [],
      relations: [],
      insights: ['❌ 系统遇到问题: $error', '🔄 正在尝试恢复...'],
      queryKeywords: [],
      totalEntityCount: 0,
      totalEventCount: 0,
      totalRelationCount: 0,
      generatedAt: DateTime.now(),
      hasData: false,
      status: 'error',
    );
  }

  /// 🔥 重构：更新知识图谱数据
  Future<void> updateKnowledgeGraph(
      List<String> topicKeywords,
      List<String> entityKeywords,
      List<String> intentEntities,
      ) async {
    if (!_initialized) {
      print('[KnowledgeGraphManager] ⚠️ 管理器未初始化，自动初始化...');
      await initialize();
    }

    try {
      print('[KnowledgeGraphManager] 🔄 开始更新知识图谱...');

      // 🔥 改进：关键词处理和去重
      final allKeywords = <String>{};
      allKeywords.addAll(_cleanKeywords(topicKeywords));
      allKeywords.addAll(_cleanKeywords(entityKeywords));
      allKeywords.addAll(_cleanKeywords(intentEntities));

      final validKeywords = allKeywords.where((k) => k.length >= 2).take(20).toList();

      print('[KnowledgeGraphManager] 🔍 处理后的关键词: $validKeywords');

      // 🔥 优化：检查是否需要重新查询（关键词变化才查询）
      if (_shouldSkipQuery(validKeywords)) {
        print('[KnowledgeGraphManager] ⚡ 关键词未变化，使用缓存数据');
        return;
      }

      // 生成缓存键
      final cacheKey = validKeywords.join('|');

      // 🔥 新增：检查缓存
      if (_dataCache.containsKey(cacheKey)) {
        print('[KnowledgeGraphManager] ⚡ 命中缓存');
        _currentData = _dataCache[cacheKey];
        _lastQueryKeywords = validKeywords;
        _cacheHits++;

        _dataStreamController.add(_currentData!);
        return;
      }

      // 🔥 重构：执行查询
      _currentData = await _performKnowledgeGraphQuery(validKeywords);
      _lastQueryKeywords = validKeywords;
      _lastUpdateTime = DateTime.now();
      _totalQueries++;

      // 🔥 新增：缓存结果（限制缓存大小）
      if (_dataCache.length >= 10) {
        _dataCache.clear(); // 简单的缓存清理策略
      }
      _dataCache[cacheKey] = _currentData!;

      // 🔥 关键：始终通知UI更新
      _dataStreamController.add(_currentData!);

      print('[KnowledgeGraphManager] ✅ 知识图谱更新完成: ${_currentData!.entities.length}实体, ${_currentData!.events.length}事件');

    } catch (e) {
      print('[KnowledgeGraphManager] ❌ 更新失败: $e');

      // 🔥 修复：错误时也要保持数据状态，避免空白页
      _currentData = _createErrorData(e.toString());
      _dataStreamController.add(_currentData!);
    }
  }

  /// 🔥 新增：清理关键词
  List<String> _cleanKeywords(List<String> keywords) {
    return keywords
        .map((k) => k.trim().toLowerCase())
        .where((k) => k.isNotEmpty && k.length >= 2 && k.length <= 50)
        .toList();
  }



  /// 🔥 新增：判断是否应该跳过查询
  bool _shouldSkipQuery(List<String> newKeywords) {
    if (_currentData == null || _currentData!.status == 'error') return false;
    if (newKeywords.isEmpty && _lastQueryKeywords.isEmpty) return true;

    // 比较关键词列表
    final newSet = Set<String>.from(newKeywords);
    final oldSet = Set<String>.from(_lastQueryKeywords);

    return newSet.length == oldSet.length && newSet.difference(oldSet).isEmpty;
  }

  /// 🔥 重构：执行知识图谱查询
  Future<KnowledgeGraphData> _performKnowledgeGraphQuery(List<String> keywords) async {
    final stopwatch = Stopwatch()..start();

    try {
      final objectBox = ObjectBoxService();

      // 🔥 改进：分别获取数据
      final allNodes = objectBox.queryNodes();
      final allEvents = objectBox.queryEventNodes();
      final allEdges = objectBox.queryEdges();

      print('[KnowledgeGraphManager] 📊 数据库: ${allNodes.length}节点, ${allEvents.length}事件, ${allEdges.length}边');

      // 🔥 重构：实体匹配和评分
      final entityResults = await _matchAndScoreEntities(allNodes, keywords);
      final eventResults = await _matchAndScoreEvents(allEvents, keywords, entityResults.map((e) => e['id'].toString()).toList());
      final relationResults = _buildRelations(entityResults, eventResults, allEdges, objectBox);

      // 🔥 改进：生成洞察
      final insights = _generateInsights(entityResults, eventResults, keywords);

      stopwatch.stop();
      print('[KnowledgeGraphManager] ⏱️ 查询完成，耗时: ${stopwatch.elapsedMilliseconds}ms');

      return KnowledgeGraphData(
        entities: entityResults,
        events: eventResults,
        relations: relationResults,
        insights: insights,
        queryKeywords: keywords,
        totalEntityCount: allNodes.length,
        totalEventCount: allEvents.length,
        totalRelationCount: allEdges.length,
        generatedAt: DateTime.now(),
        hasData: entityResults.isNotEmpty || eventResults.isNotEmpty,
        status: 'success',
      );

    } catch (e) {
      stopwatch.stop();
      print('[KnowledgeGraphManager] ❌ 查询失败 (耗时: ${stopwatch.elapsedMilliseconds}ms): $e');
      throw e;
    }
  }

  /// 🔥 重构：实体匹配和评分
  Future<List<Map<String, dynamic>>> _matchAndScoreEntities(List<Node> nodes, List<String> keywords) async {
    final scored = <Map<String, dynamic>>[];

    if (keywords.isEmpty) {
      // 🔥 修复：没有关键词时，按节点的重要性和时间排序
      for (final node in nodes) {
        final defaultScore = _calculateDefaultEntityScore(node);
        scored.add(_createEntityMap(node, [], defaultScore));
      }

      // 按默认评分排序
      scored.sort((a, b) => (b['relevance_score'] as double).compareTo(a['relevance_score'] as double));
      return scored.take(15).toList();
    }

    // 有关键词时的匹配逻辑
    for (final node in nodes) {
      final matchResult = _calculateEntityMatch(node, keywords);
      // 🔥 修复：即使分数为0也要包含一些结果，但用默认评分
      if (matchResult['score'] > 0.0) {
        scored.add(_createEntityMap(node, matchResult['matched_keywords'], matchResult['score']));
      } else if (scored.length < 5) {
        // 没有关键词匹配时，使用默认评分
        final defaultScore = _calculateDefaultEntityScore(node);
        scored.add(_createEntityMap(node, [], defaultScore));
      }
    }

    // 🔥 改进：按分数排序，确保有数据
    scored.sort((a, b) => (b['relevance_score'] as double).compareTo(a['relevance_score'] as double));

    return scored.take(15).toList();
  }

  /// 🔥 重构：事件匹配和评分
  Future<List<Map<String, dynamic>>> _matchAndScoreEvents(List<EventNode> events, List<String> keywords, List<String> entityIds) async {
    final scored = <Map<String, dynamic>>[];

    if (keywords.isEmpty) {
      // 🔥 修复：没有关键词时，按事件的重要性和时间排序
      for (final event in events) {
        final defaultScore = _calculateDefaultEventScore(event);
        scored.add(_createEventMap(event, [], defaultScore));
      }

      // 按默认评分排序
      scored.sort((a, b) => (b['relevance_score'] as double).compareTo(a['relevance_score'] as double));
      return scored.take(12).toList();
    }

    // 有关键词时的匹配逻辑
    for (final event in events) {
      final matchResult = _calculateEventMatch(event, keywords);
      // 🔥 修复：即使分数为0也要包含一些结果，但用默认评分
      if (matchResult['score'] > 0.0) {
        scored.add(_createEventMap(event, matchResult['matched_keywords'], matchResult['score']));
      } else if (scored.length < 5) {
        // 没有关键词匹配时，使用默认评分
        final defaultScore = _calculateDefaultEventScore(event);
        scored.add(_createEventMap(event, [], defaultScore));
      }
    }

    // 🔥 改进：按分数排序
    scored.sort((a, b) => (b['relevance_score'] as double).compareTo(a['relevance_score'] as double));

    return scored.take(12).toList();
  }

  /// 🔥 新增：计算实体默认评分（基于重要性指标）
  double _calculateDefaultEntityScore(Node node) {
    double score = 1.0; // 基础分数

    // 根据节点的属性数量评分（属性越多说明越重要）
    score += (node.attributes.length * 0.1);

    // 根据别名数量评分（别名越多说明越知名）
    score += (node.aliases.length * 0.2);

    // 根据名称长度评分（适中的名称长度通常更重要）
    final nameLength = node.name.length;
    if (nameLength >= 2 && nameLength <= 20) {
      score += 0.5;
    }

    // 根据类型评分（某些类型可能更重要）
    switch (node.type.toLowerCase()) {
      case 'person':
      case '人物':
        score += 1.0;
        break;
      case 'organization':
      case '组织':
        score += 0.8;
        break;
      case 'location':
      case '地点':
        score += 0.6;
        break;
      default:
        score += 0.3;
    }

    return score;
  }

  /// 🔥 新增：计算事件默认评分（基于时间和重要性）
  double _calculateDefaultEventScore(EventNode event) {
    double score = 1.0; // 基础分数

    // 根据事件的描述长度评分
    final descLength = (event.description ?? '').length;
    score += (descLength > 0 ? (descLength / 100.0).clamp(0.0, 2.0) : 0.0);

    // 根据事件时间评分（最近的事件分数更高）
    final eventTime = event.startTime ?? event.lastUpdated;
    final now = DateTime.now();
    final daysDiff = now.difference(eventTime).inDays;

    if (daysDiff <= 1) {
      score += 3.0; // 今天或昨天
    } else if (daysDiff <= 7) {
      score += 2.0; // 一周内
    } else if (daysDiff <= 30) {
      score += 1.0; // 一个月内
    } else if (daysDiff <= 365) {
      score += 0.5; // 一年内
    }

    // 根据事件类型评分
    switch (event.type.toLowerCase()) {
      case 'meeting':
      case '会议':
        score += 1.5;
        break;
      case 'call':
      case '通话':
        score += 1.2;
        break;
      case 'email':
      case '邮件':
        score += 1.0;
        break;
      default:
        score += 0.8;
    }

    // 有位置信息的事件分数更高
    if ((event.location ?? '').isNotEmpty) {
      score += 0.5;
    }

    return score;
  }

  /// 🔥 新增：计算实体匹配度
  Map<String, dynamic> _calculateEntityMatch(Node node, List<String> keywords) {
    double score = 0.0;
    final matchedKeywords = <String>[];

    final nodeName = node.name.toLowerCase();
    final canonicalName = node.canonicalName.toLowerCase();
    final aliases = node.aliases.map((a) => a.toLowerCase()).toList();

    for (final keyword in keywords) {
      final keywordLower = keyword.toLowerCase();
      bool matched = false;
      double keywordScore = 0.0;

      // 完全匹配 - 最高分
      if (nodeName == keywordLower || canonicalName == keywordLower) {
        keywordScore = 5.0;
        matched = true;
      }
      // 包含匹配 - 中等分
      else if (nodeName.contains(keywordLower) || keywordLower.contains(nodeName)) {
        keywordScore = 3.0;
        matched = true;
      }
      // 规范名称匹配
      else if (canonicalName.contains(keywordLower) || keywordLower.contains(canonicalName)) {
        keywordScore = 2.0;
        matched = true;
      }
      // 别名匹配
      else if (aliases.any((alias) => alias.contains(keywordLower) || keywordLower.contains(alias))) {
        keywordScore = 1.5;
        matched = true;
      }

      if (matched) {
        score += keywordScore;
        matchedKeywords.add(keyword); // 🔥 修复：记录具体匹配的关键词
        print('[KnowledgeGraphManager] 🎯 实体 "${node.name}" 匹配关键词 "$keyword" (得分: $keywordScore)');
      }
    }

    return {
      'score': score,
      'matched_keywords': matchedKeywords,
    };
  }

  /// 🔥 新增：计算事件匹配度
  Map<String, dynamic> _calculateEventMatch(EventNode event, List<String> keywords) {
    double score = 0.0;
    final matchedKeywords = <String>[];

    final eventName = event.name.toLowerCase();
    final description = (event.description ?? '').toLowerCase();
    final type = event.type.toLowerCase();
    final location = (event.location ?? '').toLowerCase();

    for (final keyword in keywords) {
      final keywordLower = keyword.toLowerCase();
      bool matched = false;
      double keywordScore = 0.0;

      // 名称完全匹配
      if (eventName == keywordLower) {
        keywordScore = 5.0;
        matched = true;
      }
      // 名称包含匹配
      else if (eventName.contains(keywordLower) || keywordLower.contains(eventName)) {
        keywordScore = 3.0;
        matched = true;
      }
      // 描述匹配
      else if (description.isNotEmpty && (description.contains(keywordLower) || keywordLower.contains(description))) {
        keywordScore = 2.0;
        matched = true;
      }
      // 类型匹配
      else if (type.contains(keywordLower)) {
        keywordScore = 1.5;
        matched = true;
      }
      // 位置匹配
      else if (location.isNotEmpty && location.contains(keywordLower)) {
        keywordScore = 1.0;
        matched = true;
      }

      if (matched) {
        score += keywordScore;
        matchedKeywords.add(keyword); // 🔥 修复：记录具体匹配的关键词
        print('[KnowledgeGraphManager] 🎯 事件 "${event.name}" 匹配关键词 "$keyword" (得分: $keywordScore)');
      }
    }

    return {
      'score': score,
      'matched_keywords': matchedKeywords,
    };
  }

  /// 🔥 新增：创建实体映射
  Map<String, dynamic> _createEntityMap(Node node, List<String> matchedKeywords, double score) {
    return {
      'id': node.id,
      'name': node.name,
      'type': node.type,
      'canonical_name': node.canonicalName,
      'aliases': List<String>.from(node.aliases),
      'attributes_count': node.attributes.length,
      'relevance_score': score,
      'matched_keywords': matchedKeywords,
    };
  }

  /// 🔥 新增：创建事件映射
  Map<String, dynamic> _createEventMap(EventNode event, List<String> matchedKeywords, double score) {
    return {
      'id': event.id,
      'name': event.name,
      'type': event.type,
      'description': event.description ?? '',
      'location': event.location ?? '',
      'start_time': event.startTime?.toIso8601String() ?? '',
      'formatted_date': _formatEventDate(event.startTime ?? event.lastUpdated),
      'relevance_score': score,
      'matched_keywords': matchedKeywords,
      'source_query': matchedKeywords.join(', '),
    };
  }

  /// 🔥 重构：构建关系
  List<Map<String, dynamic>> _buildRelations(
      List<Map<String, dynamic>> entities,
      List<Map<String, dynamic>> events,
      List<Edge> allEdges,
      ObjectBoxService objectBox
      ) {
    final relations = <Map<String, dynamic>>[];
    final entityIds = entities.map((e) => e['id'].toString()).toSet();
    final eventIds = events.map((e) => e['id'].toString()).toSet();

    // 实体-事件关系
    for (final entityId in entityIds) {
      final eventRelations = objectBox.queryEventEntityRelations(entityId: entityId);
      for (final relation in eventRelations.take(5)) {
        if (eventIds.contains(relation.eventId)) {
          final entity = entities.firstWhere((e) => e['id'] == entityId, orElse: () => {});
          final event = events.firstWhere((e) => e['id'] == relation.eventId, orElse: () => {});

          if (entity.isNotEmpty && event.isNotEmpty) {
            relations.add({
              'source': entity['name'],
              'target': event['name'],
              'relation_type': relation.role,
              'entity_type': entity['type'],
              'event_type': event['type'],
            });
          }
        }
      }
    }

    return relations.take(20).toList();
  }

  /// 🔥 重构：生成洞察
  List<String> _generateInsights(
      List<Map<String, dynamic>> entities,
      List<Map<String, dynamic>> events,
      List<String> keywords
      ) {
    final insights = <String>[];

    if (entities.isEmpty && events.isEmpty) {
      insights.add('🔍 当前关键词未匹配到相关数据');
      insights.add('💡 尝试使用更通用的关键词进行搜索');
      return insights;
    }

    insights.add('✅ 检索到 ${entities.length} 个相关实体和 ${events.length} 个相关事件');

    if (keywords.isNotEmpty) {
      insights.add('🔍 基于 ${keywords.length} 个关键词: ${keywords.take(3).join(', ')}${keywords.length > 3 ? '...' : ''}');

      // 统计关键词命中率
      final keywordHits = <String, int>{};
      for (final keyword in keywords) {
        int hits = 0;
        hits += entities.where((e) => (e['matched_keywords'] as List).contains(keyword)).length;
        hits += events.where((e) => (e['matched_keywords'] as List).contains(keyword)).length;
        if (hits > 0) keywordHits[keyword] = hits;
      }

      if (keywordHits.isNotEmpty) {
        final topKeyword = keywordHits.entries.reduce((a, b) => a.value > b.value ? a : b);
        insights.add('🎯 最活跃关键词: "${topKeyword.key}" (${topKeyword.value} 项匹配)');
      }
    }

    if (events.isNotEmpty) {
      final topEvent = events.first;
      final score = (topEvent['relevance_score'] as double);
      insights.add('⭐ 最相关事件: ${topEvent['name']} (相关性: ${score.toStringAsFixed(1)})');
    }

    return insights;
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

  /// 搜索知识图谱
  List<Map<String, dynamic>> searchKnowledgeGraph(String query) {
    if (_currentData == null || query.trim().isEmpty) return [];

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
      'total_queries': _totalQueries,
      'cache_hits': _cacheHits,
      'cache_hit_rate': _totalQueries > 0 ? (_cacheHits / _totalQueries * 100).toStringAsFixed(1) + '%' : '0%',
      'current_keywords_count': _lastQueryKeywords.length,
      'current_entities_count': _currentData?.entities.length ?? 0,
      'current_events_count': _currentData?.events.length ?? 0,
      'current_relations_count': _currentData?.relations.length ?? 0,
      'last_update_time': _lastUpdateTime?.toIso8601String(),
      'has_current_data': _currentData != null && _currentData!.hasData,
      'data_status': _currentData?.status ?? 'unknown',
    };
  }

  /// 🔥 新增：强制刷新数据
  Future<void> forceRefresh() async {
    print('[KnowledgeGraphManager] 🔄 强制刷新数据...');
    _dataCache.clear();
    await updateKnowledgeGraph(_lastQueryKeywords, [], []);
  }

  /// 重置系统
  void reset() {
    print('[KnowledgeGraphManager] 🔄 重置知识图谱管理器...');
    _dataCache.clear();
    _currentData = _createEmptyData();
    _lastQueryKeywords.clear();
    _totalQueries = 0;
    _cacheHits = 0;
    _lastUpdateTime = null;

    _dataStreamController.add(_currentData!);
    print('[KnowledgeGraphManager] ✅ 重置完成');
  }

  /// 释放资源
  void dispose() {
    print('[KnowledgeGraphManager] 🔄 释放知识图谱管理器资源...');
    _dataStreamController.close();
    _dataCache.clear();
    _initialized = false;
    print('[KnowledgeGraphManager] ✅ 资源释放完成');
  }
}
