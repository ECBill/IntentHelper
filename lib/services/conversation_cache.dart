import 'dart:async';
import 'dart:collection';
import 'package:app/services/advanced_kg_retrieval.dart';
import 'package:app/services/smart_kg_service.dart';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/services/llm.dart';
import 'dart:convert';

// 缓存项优先级枚举
enum CacheItemPriority {
  low,
  medium,
  high,
  critical
}

// 缓存项类
class CacheItem {
  final String key;
  final dynamic data;
  final String category;
  final CacheItemPriority priority;
  final double weight;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int accessCount;
  final Set<String> relatedTopics;
  final double relevanceScore;

  CacheItem({
    required this.key,
    required this.data,
    required this.category,
    required this.priority,
    required this.weight,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.accessCount,
    required this.relatedTopics,
    required this.relevanceScore,
  });

  CacheItem copyWith({
    String? key,
    dynamic data,
    String? category,
    CacheItemPriority? priority,
    double? weight,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    Set<String>? relatedTopics,
    double? relevanceScore,
  }) {
    return CacheItem(
      key: key ?? this.key,
      data: data ?? this.data,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      weight: weight ?? this.weight,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      relatedTopics: relatedTopics ?? this.relatedTopics,
      relevanceScore: relevanceScore ?? this.relevanceScore,
    );
  }
}

// 对话摘要类
class ConversationSummary {
  final String id;
  final String content;
  final DateTime timestamp;
  final List<String> keyTopics;
  final String category;

  ConversationSummary({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.keyTopics,
    required this.category,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'keyTopics': keyTopics,
      'category': category,
    };
  }
}

// 对话状态枚举
enum ConversationState {
  idle,
  active,
  processing,
  completed
}

// 用户意图枚举
enum UserIntent {
  question,
  request,
  casual,
  planning,
  reflection
}

// 用户情绪枚举
enum UserEmotion {
  neutral,
  positive,
  negative,
  excited,
  confused
}

// 对话上下文类
class ConversationContext {
  final String id;
  final ConversationState state;
  final UserIntent primaryIntent;
  final UserEmotion userEmotion;
  final DateTime startTime;
  final List<String> currentTopics;
  final List<String> participants;
  final Map<String, double> topicIntensity;
  final List<String> unfinishedTasks;

  ConversationContext({
    required this.id,
    required this.state,
    required this.primaryIntent,
    required this.userEmotion,
    required this.startTime,
    required this.currentTopics,
    required this.participants,
    required this.topicIntensity,
    required this.unfinishedTasks,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'state': state.toString(),
      'primaryIntent': primaryIntent.toString(),
      'userEmotion': userEmotion.toString(),
      'startTime': startTime.toIso8601String(),
      'currentTopics': currentTopics,
      'participants': participants,
      'topicIntensity': topicIntensity,
      'unfinishedTasks': unfinishedTasks,
    };
  }
}

// 用户个人上下文类
class UserPersonalContext {
  final String userId;
  final Map<String, dynamic> preferences;
  final Map<String, dynamic> personalInfo;
  final List<String> recentInterests;
  final DateTime lastUpdated;

  UserPersonalContext({
    required this.userId,
    required this.preferences,
    required this.personalInfo,
    required this.recentInterests,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'preferences': preferences,
      'personalInfo': personalInfo,
      'recentInterests': recentInterests,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

// 用户关注点 - 核心概念（重新定义：专注于个人信息相关）
class UserFocus {
  final String focusId;
  final String description;          // 关注点的自然语言描述
  final FocusType type;             // 关注点类型
  final double intensity;           // 关注强度 0-1
  final List<String> keywords;      // 相关关键词
  final List<String> entities;      // 相关实体
  final DateTime identifiedAt;      // 识别时间
  final Map<String, dynamic> context; // 上下文信息

  UserFocus({
    required this.focusId,
    required this.description,
    required this.type,
    required this.intensity,
    required this.keywords,
    required this.entities,
    required this.identifiedAt,
    required this.context,
  });
}

// 关注点类型（重新定义：专注于个人信息维度）
enum FocusType {
  personal_history,    // 个人历史相关 - 用户想了解自己的过往经历
  relationship,        // 人际关系相关 - 涉及用户的朋友、家人等
  preference,          // 个人偏好相关 - 用户的喜好、习惯等
  goal_tracking,       // 目标追踪相关 - 用户的计划、目标进展
  behavior_pattern,    // 行为模式相关 - 用户的行为习惯分析
  emotional_context,   // 情感上下文相关 - 用户的情感状态历史
  temporal_context,    // 时间上下文相关 - 特定时间段的用户信息
}

// 个人信息检索结果
class PersonalInfoRetrievalResult {
  final String resultId;
  final List<Node> personalNodes;      // 检索到的用户个人信息节点
  final List<EventNode> relatedEvents; // 相关的用户事件
  final List<Edge> relationships;      // 相关的人际关系
  final double relevanceScore;         // 个人相关性评分
  final String retrievalReason;        // 检索原因
  final UserFocus sourceFocus;         // 来源关注点
  final DateTime retrievedAt;          // 检索时间
  final Map<String, dynamic> personalContext; // 个人上下文信息

  PersonalInfoRetrievalResult({
    required this.resultId,
    required this.personalNodes,
    required this.relatedEvents,
    required this.relationships,
    required this.relevanceScore,
    required this.retrievalReason,
    required this.sourceFocus,
    required this.retrievedAt,
    required this.personalContext,
  });
}

// 智能个人信息缓存系统 - 专注于用户个人知识图谱
class ConversationCache {
  static final ConversationCache _instance = ConversationCache._internal();
  factory ConversationCache() => _instance;
  ConversationCache._internal();

  // 核心缓存存储
  final Map<String, UserFocus> _userFocuses = {};           // 用户关注点
  final Map<String, PersonalInfoRetrievalResult> _personalInfoResults = {}; // 个人信息检索结果
  final Queue<String> _conversationHistory = Queue<String>(); // 对话历史（用于语义分析）
  
  // 用户个人信息上下文
  String _currentConversationContext = '';
  DateTime _lastAnalysisTime = DateTime.now();
  
  // 配置参数
  static const int maxFocuses = 15;                    // 最大关注点数量
  static const int maxPersonalInfoResults = 30;       // 最大个人信息结果数量
  static const int conversationHistoryLimit = 10;      // 对话历史记录条数
  static const Duration focusExpirationTime = Duration(hours: 4); // 关注点过期时间
  static const double minFocusIntensity = 0.3;         // 最小关注强度阈值

  // 服务依赖
  final SmartKGService _smartKGService = SmartKGService();
  final AdvancedKGRetrieval _advancedKGRetrieval = AdvancedKGRetrieval();

  // ========== 核心方法 1: 快速分析用户个人信息关注点 ==========

  Future<void> analyzeUserFocusFromConversation(String conversationText) async {
    print('[PersonalCache] 🧠 开始快速分析用户个人信息关注点: ${conversationText.substring(0, conversationText.length > 50 ? 50 : conversationText.length)}...');

    try {
      // 1. 更新对话历史
      _conversationHistory.addLast(conversationText);
      if (_conversationHistory.length > conversationHistoryLimit) {
        _conversationHistory.removeFirst();
      }
      
      // 2. 构建上下文
      _currentConversationContext = _conversationHistory.join('\n');
      
      // 3. 快速关键词匹配分析（优先）- 毫秒级响应
      await _performQuickKeywordAnalysis(conversationText);

      // 4. 异步执行深度LLM分析（不阻塞主流程）
      _performAsyncDeepAnalysis(_currentConversationContext);

      _lastAnalysisTime = DateTime.now();
      print('[PersonalCache] ✅ 快速个人信息关注点分析完成，当前活跃关注点: ${_getActiveFocuses().length}');

    } catch (e, stackTrace) {
      print('[PersonalCache] ❌ 分析用户个人信息关注点错误: $e');
      print('[PersonalCache] Stack trace: $stackTrace');
    }
  }

  // 快速关键词匹配分析 - 毫秒级响应
  Future<void> _performQuickKeywordAnalysis(String conversationText) async {
    final personalKeywords = {
      'personal_history': ['我的', '我之前', '我以前', '我曾经', '我做过', '我去过', '记得我', '我经历过'],
      'relationship': ['我朋友', '我家人', '我和', '我们', '朋友', '家人', '男友', '女友', '伴侣', '同事'],
      'preference': ['我喜欢', '我不喜欢', '我习惯', '我通常', '我偏好', '我爱', '我讨厌'],
      'goal_tracking': ['我的目标', '我计划', '我想要', '我的进展', '我的计划', '我希望', '我打算'],
      'behavior_pattern': ['我经常', '我总是', '我很少', '我从不', '我习惯', '我一般'],
      'emotional_context': ['我觉得', '我感觉', '我心情', '我开心', '我难过', '我压力', '我担心', '我兴奋'],
      'temporal_context': ['最近', '昨天', '上周', '这个月', '去年', '今天', '明天', '下周'],
    };

    final now = DateTime.now();

    for (final entry in personalKeywords.entries) {
      final type = entry.key;
      final keywords = entry.value;

      for (final keyword in keywords) {
        if (conversationText.contains(keyword)) {
          // 快速创建关注点
          final focusId = 'quick_focus_${now.millisecondsSinceEpoch}_${type}';
          final userFocus = UserFocus(
            focusId: focusId,
            description: '用户询问与${type}相关的个人信息',
            type: _parsePersonalFocusType(type),
            intensity: 0.7, // 默认强度
            keywords: [keyword],
            entities: ['用户'],
            identifiedAt: now,
            context: {
              'trigger_text': conversationText.length > 100 ? conversationText.substring(0, 100) + '...' : conversationText,
              'time_scope': _detectTimeScope(conversationText),
              'info_type': _detectInfoType(type),
              'analysis_type': 'quick_keyword'
            },
          );

          _userFocuses[focusId] = userFocus;
          print('[PersonalCache] ⚡ 快速识别个人信息关注点: ${userFocus.description} (关键词: $keyword)');

          // 立即触发快速个人信息检索
          _triggerQuickPersonalInfoRetrieval(userFocus);
          break; // 每个类型最多添加一个
        }
      }
    }
  }

  // 异步深度分析（不阻塞主流程）
  void _performAsyncDeepAnalysis(String conversationContext) {
    Future.microtask(() async {
      try {
        print('[PersonalCache] 🔍 开始异步深度分析...');
        final deepAnalysisResult = await _performPersonalFocusAnalysis(conversationContext);
        await _processFocusAnalysisResults(deepAnalysisResult);
        await _triggerPersonalInfoRetrievalForActiveFocuses();
        print('[PersonalCache] ✅ 异步深度分析完成');
      } catch (e) {
        print('[PersonalCache] ⚠️ 异步深度分析失败: $e');
      }
    });
  }

  // 快速个人信息检索
  void _triggerQuickPersonalInfoRetrieval(UserFocus focus) {
    Future.microtask(() async {
      try {
        // 简化的个人信息检索 - 基于关键词直接匹配
        final quickResults = await _performQuickPersonalInfoRetrieval(focus);
        if (quickResults.isNotEmpty) {
          await _storeQuickPersonalInfoResult(quickResults, focus);
        }
      } catch (e) {
        print('[PersonalCache] ⚠️ 快速个人信息检索失败: $e');
      }
    });
  }

  // 简化的个人信息检索
  Future<Map<String, dynamic>> _performQuickPersonalInfoRetrieval(UserFocus focus) async {
    final results = {
      'personal_nodes': <Node>[],
      'related_events': <EventNode>[],
      'relationships': <Edge>[],
    };

    try {
      // 使用关键词直接查找相关节点（快速）
      final keywords = focus.keywords;
      if (keywords.isNotEmpty) {
        final relatedNodes = await KnowledgeGraphService.getRelatedNodesByKeywords(keywords);

        // 过滤出与用户相关的节点
        final personalNodes = relatedNodes.where((node) => _isUserRelatedNode(node)).toList();
        results['personal_nodes'] = personalNodes.take(3).toList(); // 限制数量以提高速度

        print('[PersonalCache] ⚡ 快速检索到${personalNodes.length}个个人节点');
      }

      return results;
    } catch (e) {
      print('[PersonalCache] ⚠️ 快速个人信息检索错误: $e');
      return results;
    }
  }

  // 存储快速检索结果
  Future<void> _storeQuickPersonalInfoResult(Map<String, dynamic> results, UserFocus focus) async {
    final resultId = 'quick_pir_${focus.focusId}_${DateTime.now().millisecondsSinceEpoch}';

    final personalNodes = results['personal_nodes'] as List<Node>? ?? [];
    final relatedEvents = results['related_events'] as List<EventNode>? ?? [];
    final relationships = results['relationships'] as List<Edge>? ?? [];

    final avgRelevance = personalNodes.isNotEmpty ? 0.8 : 0.5; // 简化评分

    final personalInfoResult = PersonalInfoRetrievalResult(
      resultId: resultId,
      personalNodes: personalNodes,
      relatedEvents: relatedEvents,
      relationships: relationships,
      relevanceScore: avgRelevance,
      retrievalReason: '基于关键词快速检索个人信息',
      sourceFocus: focus,
      retrievedAt: DateTime.now(),
      personalContext: {
        'focus_type': focus.type.toString(),
        'analysis_type': 'quick',
        'nodes_count': personalNodes.length,
        'events_count': relatedEvents.length,
        'relationships_count': relationships.length,
      },
    );

    _personalInfoResults[resultId] = personalInfoResult;
    print('[PersonalCache] ⚡ 快速存储个人信息检索结果: ${personalNodes.length}个节点');
  }

  // 解析个人关注点类型
  FocusType _parsePersonalFocusType(String typeStr) {
    switch (typeStr) {
      case 'relationship':
        return FocusType.relationship;
      case 'preference':
        return FocusType.preference;
      case 'goal_tracking':
        return FocusType.goal_tracking;
      case 'behavior_pattern':
        return FocusType.behavior_pattern;
      case 'emotional_context':
        return FocusType.emotional_context;
      case 'temporal_context':
        return FocusType.temporal_context;
      default:
        return FocusType.personal_history;
    }
  }

  // ========== 核心方法 2: 精准个人信息检索 ==========

  Future<void> _triggerPersonalInfoRetrievalForActiveFocuses() async {
    final activeFocuses = _getActiveFocuses();
    
    print('[PersonalCache] 🔍 开始为${activeFocuses.length}个关注点检索个人信息');

    for (final focus in activeFocuses) {
      await _performPersonalInfoRetrievalForFocus(focus);
    }
  }

  Future<void> _performPersonalInfoRetrievalForFocus(UserFocus focus) async {
    try {
      print('[PersonalCache] 🎯 为关注点检索个人信息: ${focus.description}');

      // 1. 构建个人信息检索查询
      final retrievalQuery = await _buildPersonalInfoRetrievalQuery(focus);

      // 2. 执行多维度个人信息检索
      final retrievalResults = await _executePersonalInfoRetrieval(retrievalQuery, focus);

      // 3. 评估和过滤结果
      final filteredResults = await _evaluateAndFilterPersonalInfoResults(retrievalResults, focus);

      // 4. 存储个人信息检索结果
      if (filteredResults.isNotEmpty) {
        await _storePersonalInfoRetrievalResult(filteredResults, focus);
      }
      
    } catch (e) {
      print('[PersonalCache] ❌ 个人信息检索失败 for ${focus.focusId}: $e');
    }
  }

  // 构建个人信息检索查询
  Future<Map<String, dynamic>> _buildPersonalInfoRetrievalQuery(UserFocus focus) async {
    return {
      'focus_type': focus.type.toString(),
      'keywords': focus.keywords,
      'entities': focus.entities,
      'description': focus.description,
      'time_scope': focus.context['time_scope'] ?? 'recent',
      'info_type': focus.context['info_type'] ?? 'general',
      'intensity': focus.intensity,
    };
  }

  // 执行多维度个人信息检索
  Future<Map<String, dynamic>> _executePersonalInfoRetrieval(
    Map<String, dynamic> query,
    UserFocus focus
  ) async {
    final results = {
      'personal_nodes': <Node>[],
      'related_events': <EventNode>[],
      'relationships': <Edge>[],
    };

    try {
      // 1. 检索用户相关的节点（基于关键词和实体）
      final personalNodes = await _retrieveUserPersonalNodes(query);
      results['personal_nodes'] = personalNodes;

      // 2. 检索相关的用户事件
      final relatedEvents = await _retrieveUserRelatedEvents(query, personalNodes);
      results['related_events'] = relatedEvents;

      // 3. 检索用户的人际关系信息
      final relationships = await _retrieveUserRelationships(query, personalNodes);
      results['relationships'] = relationships;

      print('[PersonalCache] 📊 个人信息检索结果: ${personalNodes.length}个节点, ${relatedEvents.length}个事件, ${relationships.length}个关系');

      return results;
    } catch (e) {
      print('[PersonalCache] ⚠️ 个人信息检索部分失败: $e');
      return results;
    }
  }

  // 检索用户个人节点
  Future<List<Node>> _retrieveUserPersonalNodes(Map<String, dynamic> query) async {
    final results = <Node>[];

    try {
      final keywords = query['keywords'] as List<String>? ?? [];
      final entities = query['entities'] as List<String>? ?? [];

      // 使用KnowledgeGraphService查找相关节点
      final allKeywords = [...keywords, ...entities];
      final relatedNodes = await KnowledgeGraphService.getRelatedNodesByKeywords(allKeywords);

      // 过滤出与用户直接相关的节点
      for (final node in relatedNodes) {
        if (_isUserRelatedNode(node)) {
          results.add(node);
        }
      }

      print('[PersonalCache] 👤 检索到${results.length}个用户相关节点');

    } catch (e) {
      print('[PersonalCache] ⚠️ 检索用户个人节点失败: $e');
    }
    
    return results;
  }

  // 检索用户相关事件
  Future<List<EventNode>> _retrieveUserRelatedEvents(Map<String, dynamic> query, List<Node> personalNodes) async {
    final results = <EventNode>[];

    try {
      // 基于个人节点查找相关事件
      for (final node in personalNodes.take(5)) { // 限制查找数量
        final events = await KnowledgeGraphService.getRelatedEvents(node.id);
        results.addAll(events);
      }
      
      // 根据时间范围过滤事件
      final timeScope = query['time_scope']?.toString() ?? 'recent';
      final filteredEvents = _filterEventsByTimeScope(results, timeScope);

      print('[PersonalCache] 📅 检索到${filteredEvents.length}个相关用户事件');

      return filteredEvents;
    } catch (e) {
      print('[PersonalCache] ⚠️ 检索用户相关事件失败: $e');
      return results;
    }
  }

  // 检索用户关系信息
  Future<List<Edge>> _retrieveUserRelationships(Map<String, dynamic> query, List<Node> personalNodes) async {
    final results = <Edge>[];

    try {
      final objectBox = ObjectBoxService();

      // 查找与用户相关的关系边
      for (final node in personalNodes.take(3)) { // 限制查找数量
        final outgoingEdges = objectBox.queryEdges(source: node.id);
        final incomingEdges = objectBox.queryEdges(target: node.id);

        results.addAll(outgoingEdges);
        results.addAll(incomingEdges);
      }

      // 过滤出人际关系相关的边
      final relationshipEdges = results.where((edge) => _isRelationshipEdge(edge)).toList();

      print('[PersonalCache] 👥 检索到${relationshipEdges.length}个用户关系');

      return relationshipEdges;
    } catch (e) {
      print('[PersonalCache] ⚠️ 检索用户关系信息失败: $e');
      return results;
    }
  }

  // 判断节点是否与用户相关
  bool _isUserRelatedNode(Node node) {
    // 检查节点是否包含用户相关的信息
    final userIndicators = ['我', '用户', '个人', '自己'];

    // 检查节点名称
    for (final indicator in userIndicators) {
      if (node.name.contains(indicator)) return true;
    }

    // 检查节点属性
    for (final value in node.attributes.values) {
      for (final indicator in userIndicators) {
        if (value.contains(indicator)) return true;
      }
    }

    // 检查节点类型是否为个人相关
    final personalTypes = ['个人', '用户', '经历', '偏好', '习惯', '目标'];
    for (final type in personalTypes) {
      if (node.type.contains(type)) return true;
    }

    return false;
  }

  // 根据时间范围过滤事件
  List<EventNode> _filterEventsByTimeScope(List<EventNode> events, String timeScope) {
    final now = DateTime.now();
    DateTime cutoffTime;

    switch (timeScope) {
      case 'recent':
        cutoffTime = now.subtract(const Duration(days: 7));
        break;
      case 'past_week':
        cutoffTime = now.subtract(const Duration(days: 14));
        break;
      case 'past_month':
        cutoffTime = now.subtract(const Duration(days: 30));
        break;
      default:
        return events; // 'long_term' 不过滤
    }

    return events.where((event) {
      if (event.startTime != null) {
        return event.startTime!.isAfter(cutoffTime);
      }
      // 如果没有时间信息，检查更新时间
      return event.lastUpdated.isAfter(cutoffTime);
    }).toList();
  }

  // 判断边是否为关系边
  bool _isRelationshipEdge(Edge edge) {
    final relationshipTypes = ['朋友', '家人', '同事', '认识', '喜欢', '关心', '合作'];

    for (final type in relationshipTypes) {
      if (edge.relation.contains(type)) return true;
    }

    return false;
  }

  // 评估和过滤个人信息结果
  Future<Map<String, dynamic>> _evaluateAndFilterPersonalInfoResults(
    Map<String, dynamic> rawResults,
    UserFocus focus
  ) async {
    final personalNodes = rawResults['personal_nodes'] as List<Node>? ?? [];
    final relatedEvents = rawResults['related_events'] as List<EventNode>? ?? [];
    final relationships = rawResults['relationships'] as List<Edge>? ?? [];

    // 1. 根据关注点类型调整相关性评分
    final scoredNodes = _scorePersonalNodesByFocus(personalNodes, focus);
    final scoredEvents = _scoreEventsByFocus(relatedEvents, focus);
    final scoredRelationships = _scoreRelationshipsByFocus(relationships, focus);

    // 2. 过滤低分结果
    final filteredNodes = scoredNodes.where((item) => item['score'] > 0.4).toList();
    final filteredEvents = scoredEvents.where((item) => item['score'] > 0.4).toList();
    final filteredRelationships = scoredRelationships.where((item) => item['score'] > 0.4).toList();

    // 3. 排序并限制数量
    filteredNodes.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    filteredEvents.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    filteredRelationships.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return {
      'personal_nodes': filteredNodes.take(8).map((item) => item['item']).toList(),
      'related_events': filteredEvents.take(5).map((item) => item['item']).toList(),
      'relationships': filteredRelationships.take(5).map((item) => item['item']).toList(),
    };
  }

  // 根据关注点为个人节点评分
  List<Map<String, dynamic>> _scorePersonalNodesByFocus(List<Node> nodes, UserFocus focus) {
    return nodes.map((node) {
      double score = 0.5; // 基础分数

      // 根据关注点类型调整分数
      switch (focus.type) {
        case FocusType.personal_history:
          if (node.type.contains('经历') || node.type.contains('事件')) score += 0.3;
          break;
        case FocusType.relationship:
          if (node.type.contains('人') || node.type.contains('朋友')) score += 0.3;
          break;
        case FocusType.preference:
          if (node.type.contains('偏好') || node.type.contains('喜好')) score += 0.3;
          break;
        case FocusType.goal_tracking:
          if (node.type.contains('目标') || node.type.contains('计划')) score += 0.3;
          break;
        default:
          break;
      }
      
      // 关键词匹配加分
      for (final keyword in focus.keywords) {
        if (node.name.contains(keyword) || node.attributes.values.any((v) => v.contains(keyword))) {
          score += 0.2;
        }
      }

      // 基于关注点强度调整
      score *= focus.intensity;
      
      return {'item': node, 'score': score.clamp(0.0, 1.0)};
    }).toList();
  }

  // 根据关注点为事件评分
  List<Map<String, dynamic>> _scoreEventsByFocus(List<EventNode> events, UserFocus focus) {
    return events.map((event) {
      double score = 0.5; // 基础分数

      // 根据关注点类型调整分数
      switch (focus.type) {
        case FocusType.personal_history:
          score += 0.4; // 事件与个人历史高度相关
          break;
        case FocusType.emotional_context:
          if (event.result != null && (event.result!.contains('开心') || event.result!.contains('难过'))) {
            score += 0.3;
          }
          break;
        case FocusType.temporal_context:
          score += 0.3; // 时间上下文中事件重要
          break;
        default:
          break;
      }

      // 关键词匹配加分
      for (final keyword in focus.keywords) {
        if (event.name.contains(keyword) ||
            (event.description?.contains(keyword) ?? false)) {
          score += 0.2;
        }
      }

      // 基于关注点强度调整
      score *= focus.intensity;

      return {'item': event, 'score': score.clamp(0.0, 1.0)};
    }).toList();
  }

  // 根据关注点为关系评分
  List<Map<String, dynamic>> _scoreRelationshipsByFocus(List<Edge> relationships, UserFocus focus) {
    return relationships.map((edge) {
      double score = 0.5; // 基础分数

      // 根据关注点类型调整分数
      switch (focus.type) {
        case FocusType.relationship:
          score += 0.4; // 关系信息与人际关系关注点高度相关
          break;
        case FocusType.emotional_context:
          if (edge.relation.contains('喜欢') || edge.relation.contains('关心')) {
            score += 0.3;
          }
          break;
        default:
          break;
      }
      
      // 关键词匹配加分
      for (final keyword in focus.keywords) {
        if (edge.relation.contains(keyword)) {
          score += 0.2;
        }
      }

      // 基于关注点强度调整
      score *= focus.intensity;

      return {'item': edge, 'score': score.clamp(0.0, 1.0)};
    }).toList();
  }

  // 存储个人信息检索结果
  Future<void> _storePersonalInfoRetrievalResult(
    Map<String, dynamic> results,
    UserFocus focus
  ) async {
    final resultId = 'pir_${focus.focusId}_${DateTime.now().millisecondsSinceEpoch}';

    final personalNodes = results['personal_nodes'] as List<Node>? ?? [];
    final relatedEvents = results['related_events'] as List<EventNode>? ?? [];
    final relationships = results['relationships'] as List<Edge>? ?? [];

    // 计算整体相关性评分
    double totalRelevance = 0.0;
    int itemCount = 0;

    if (personalNodes.isNotEmpty) {
      totalRelevance += personalNodes.length * 0.8;
      itemCount += personalNodes.length;
    }
    if (relatedEvents.isNotEmpty) {
      totalRelevance += relatedEvents.length * 0.7;
      itemCount += relatedEvents.length;
    }
    if (relationships.isNotEmpty) {
      totalRelevance += relationships.length * 0.6;
      itemCount += relationships.length;
    }

    final avgRelevance = itemCount > 0 ? totalRelevance / itemCount : 0.0;

    final personalInfoResult = PersonalInfoRetrievalResult(
      resultId: resultId,
      personalNodes: personalNodes,
      relatedEvents: relatedEvents,
      relationships: relationships,
      relevanceScore: avgRelevance,
      retrievalReason: '基于个人信息关注点"${focus.description}"检索用户相关信息',
      sourceFocus: focus,
      retrievedAt: DateTime.now(),
      personalContext: {
        'focus_type': focus.type.toString(),
        'time_scope': focus.context['time_scope'] ?? 'recent',
        'info_type': focus.context['info_type'] ?? 'general',
        'nodes_count': personalNodes.length,
        'events_count': relatedEvents.length,
        'relationships_count': relationships.length,
      },
    );
    
    _personalInfoResults[resultId] = personalInfoResult;

    // 清理过量的检索结果
    if (_personalInfoResults.length > maxPersonalInfoResults) {
      _cleanupOldPersonalInfoResults();
    }
    
    print('[PersonalCache] 💾 存储个人信息检索结果: ${personalNodes.length}个节点, ${relatedEvents.length}个事件, ${relationships.length}个关系 (相关度: ${avgRelevance.toStringAsFixed(2)})');
  }

  // ========== 对外接口方法 ==========
  
  // 获取当前最相关的个人信息用于LLM生成
  Map<String, dynamic> getRelevantPersonalInfoForGeneration() {
    final activeFocuses = _getActiveFocuses();
    final relevantResults = <PersonalInfoRetrievalResult>[];

    // 收集所有相关的个人信息检索结果
    for (final focus in activeFocuses) {
      final focusResults = _personalInfoResults.values
          .where((result) => result.sourceFocus.focusId == focus.focusId)
          .toList();
      relevantResults.addAll(focusResults);
    }
    
    // 按相关性排序
    relevantResults.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    
    // 构建个人信息上下文
    final personalNodes = <Node>[];
    final userEvents = <EventNode>[];
    final userRelationships = <Edge>[];
    final contextInfo = <String, dynamic>{};
    
    for (final result in relevantResults.take(10)) { // 最多返回10个最相关的结果
      personalNodes.addAll(result.personalNodes);
      userEvents.addAll(result.relatedEvents);
      userRelationships.addAll(result.relationships);

      contextInfo[result.resultId] = {
        'focus_description': result.sourceFocus.description,
        'focus_type': result.sourceFocus.type.toString(),
        'relevance_score': result.relevanceScore,
        'retrieval_reason': result.retrievalReason,
        'personal_context': result.personalContext,
      };
    }
    
    return {
      'personal_nodes': personalNodes,
      'user_events': userEvents,
      'user_relationships': userRelationships,
      'focus_contexts': activeFocuses.map((f) => {
        'description': f.description,
        'type': f.type.toString(),
        'intensity': f.intensity,
        'keywords': f.keywords,
      }).toList(),
      'retrieval_contexts': contextInfo,
      'total_personal_info_items': personalNodes.length + userEvents.length + userRelationships.length,
      'active_focuses_count': activeFocuses.length,
    };
  }

  // 获取用户当前个人信息关注点摘要
  List<String> getCurrentPersonalFocusSummary() {
    final activeFocuses = _getActiveFocuses();
    return activeFocuses
        .map((focus) => '${focus.description} (${focus.type.toString().split('.').last})')
        .toList();
  }

  // ========== 辅助方法 ==========
  
  List<UserFocus> _getActiveFocuses() {
    final now = DateTime.now();
    return _userFocuses.values
        .where((focus) => now.difference(focus.identifiedAt) < focusExpirationTime)
        .toList()
      ..sort((a, b) => b.intensity.compareTo(a.intensity));
  }

  void _cleanupExpiredFocuses() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    for (final entry in _userFocuses.entries) {
      if (now.difference(entry.value.identifiedAt) > focusExpirationTime) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _userFocuses.remove(key);
      print('[PersonalCache] 🗑️ 清理过期个人信息关注点: $key');
    }
    
    // 如果关注点数量过多，删除一些低强度的
    if (_userFocuses.length > maxFocuses) {
      final sortedFocuses = _userFocuses.entries.toList()
        ..sort((a, b) => a.value.intensity.compareTo(b.value.intensity));
      
      final toRemove = sortedFocuses.take(_userFocuses.length - maxFocuses);
      for (final entry in toRemove) {
        _userFocuses.remove(entry.key);
        print('[PersonalCache] 🗑️ 清理低强度个人信息关注点: ${entry.key}');
      }
    }
  }

  void _cleanupOldPersonalInfoResults() {
    final sortedResults = _personalInfoResults.entries.toList()
      ..sort((a, b) => a.value.retrievedAt.compareTo(b.value.retrievedAt));
    
    final toRemove = sortedResults.take(_personalInfoResults.length - maxPersonalInfoResults);
    for (final entry in toRemove) {
      _personalInfoResults.remove(entry.key);
    }
  }

  // ========== 调试和监控方法 ==========
  
  Map<String, dynamic> getCacheStats() {
    final activeFocuses = _getActiveFocuses();
    final now = DateTime.now();
    
    return {
      'active_personal_focuses': activeFocuses.length,
      'total_personal_focuses': _userFocuses.length,
      'personal_info_results': _personalInfoResults.length,
      'conversation_history_length': _conversationHistory.length,
      'last_analysis_time': _lastAnalysisTime.toIso8601String(),
      'time_since_last_analysis': now.difference(_lastAnalysisTime).inMinutes,
      'focus_types_distribution': _getPersonalFocusTypesDistribution(),
      'avg_focus_intensity': _getAveragePersonalFocusIntensity(),
      'total_personal_nodes': _getTotalPersonalNodes(),
      'total_user_events': _getTotalUserEvents(),
      'total_user_relationships': _getTotalUserRelationships(),
    };
  }

  Map<String, int> _getPersonalFocusTypesDistribution() {
    final distribution = <String, int>{};
    for (final focus in _getActiveFocuses()) {
      final type = focus.type.toString().split('.').last;
      distribution[type] = (distribution[type] ?? 0) + 1;
    }
    return distribution;
  }

  double _getAveragePersonalFocusIntensity() {
    final activeFocuses = _getActiveFocuses();
    if (activeFocuses.isEmpty) return 0.0;
    
    final totalIntensity = activeFocuses.fold(0.0, (sum, focus) => sum + focus.intensity);
    return totalIntensity / activeFocuses.length;
  }

  int _getTotalPersonalNodes() {
    return _personalInfoResults.values
        .fold(0, (sum, result) => sum + result.personalNodes.length);
  }

  int _getTotalUserEvents() {
    return _personalInfoResults.values
        .fold(0, (sum, result) => sum + result.relatedEvents.length);
  }

  int _getTotalUserRelationships() {
    return _personalInfoResults.values
        .fold(0, (sum, result) => sum + result.relationships.length);
  }

  void clearCache() {
    _userFocuses.clear();
    _personalInfoResults.clear();
    _conversationHistory.clear();
    _currentConversationContext = '';
    print('[PersonalCache] 🗑️ 个人信息缓存已清空');
  }

  // 兼容性方法 - 保持原有接口
  void initialize() {
    print('[PersonalCache] 🚀 智能个人信息缓存系统已初始化');
  }

  void dispose() {
    // 清理资源
  }

  Future<void> updateConversationContext(String conversationText) async {
    await analyzeUserFocusFromConversation(conversationText);
  }

  Map<String, dynamic>? getQuickResponse(String userQuery) {
    final relevantPersonalInfo = getRelevantPersonalInfoForGeneration();
    if (relevantPersonalInfo['total_personal_info_items'] > 0) {
      return {
        'hasCache': true,
        'personal_info': relevantPersonalInfo,
        'focus_summary': getCurrentPersonalFocusSummary(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
    return null;
  }

  List<CacheItem> getAllCacheItems() {
    final items = <CacheItem>[];
    final now = DateTime.now();
    
    // 转换个人信息关注点为CacheItem格式用于兼容显示
    for (final focus in _userFocuses.values) {
      items.add(CacheItem(
        key: focus.focusId,
        data: {
          'description': focus.description,
          'type': focus.type.toString(),
          'intensity': focus.intensity,
          'keywords': focus.keywords,
          'entities': focus.entities,
          'personal_info_focus': true,
        },
        priority: _focusTypeToPriority(focus.type),
        relatedTopics: focus.keywords.toSet(),
        relevanceScore: focus.intensity,
        category: 'personal_focus',
        createdAt: focus.identifiedAt,
        lastAccessedAt: now,
        accessCount: 1,
        weight: focus.intensity,
      ));
    }
    
    // 转换个人信息检索结果为CacheItem格式
    for (final result in _personalInfoResults.values) {
      items.add(CacheItem(
        key: result.resultId,
        data: {
          'personal_nodes_count': result.personalNodes.length,
          'user_events_count': result.relatedEvents.length,
          'relationships_count': result.relationships.length,
          'retrieval_reason': result.retrievalReason,
          'source_focus': result.sourceFocus.description,
          'relevance_score': result.relevanceScore,
          'personal_context': result.personalContext,
        },
        priority: CacheItemPriority.high,
        relatedTopics: result.sourceFocus.keywords.toSet(),
        relevanceScore: result.relevanceScore,
        category: 'personal_info_result',
        createdAt: result.retrievedAt,
        lastAccessedAt: now,
        accessCount: 1,
        weight: result.relevanceScore,
      ));
    }

    return items..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  CacheItemPriority _focusTypeToPriority(FocusType type) {
    switch (type) {
      case FocusType.personal_history:
      case FocusType.relationship:
        return CacheItemPriority.critical;
      case FocusType.preference:
      case FocusType.goal_tracking:
        return CacheItemPriority.high;
      case FocusType.emotional_context:
      case FocusType.behavior_pattern:
        return CacheItemPriority.medium;
      default:
        return CacheItemPriority.low;
    }
  }

  // 其他兼容性方法...
  List<CacheItem> getCacheItemsByCategory(String category) {
    return getAllCacheItems().where((item) => item.category == category).toList();
  }

  Map<String, dynamic> getClassifiedCacheStats() {
    return getCacheStats();
  }

  // 空实现或简化实现用于兼容
  Map<String, dynamic> getProactiveInteractionSuggestions() {
    return {
      'summaryReady': false,
      'suggestions': <String>[],
      'reminders': <String>[],
      'helpOpportunities': <String>[],
    };
  }

  List<ConversationSummary> getRecentSummaries({int limit = 5}) {
    return <ConversationSummary>[];
  }

  ConversationContext? getCurrentConversationContext() {
    return null;
  }

  UserPersonalContext? getUserPersonalContext() {
    return null;
  }

  Map<String, dynamic> getCacheItemDetails(String key) {
    return <String, dynamic>{};
  }

  Future<void> triggerCacheUpdate(String conversation) async => await updateConversationContext(conversation);

  Future<void> processBackgroundConversation(String conversation) async => await updateConversationContext(conversation);

  void addToCache({
    required String key,
    required data,
    required CacheItemPriority priority,
    required Set<String> relatedTopics,
    required double relevanceScore,
    String category = 'general'
  }) {
    // 简化实现，不实际存储
  }

  // 深度个人信息关注点分析 - 使用LLM理解用户的个人信息需求
  Future<Map<String, dynamic>> _performPersonalFocusAnalysis(String conversationContext) async {
    final analysisPrompt = """
你是一个用户个人信息分析专家，专门分析用户对其个人历史、经历、偏好、关系等信息的需求。

请分析对话，识别用户可能需要了解的个人信息维度。注意：不要分析通用知识需求，只关注用户个人相关的信息需求。

个人信息维度：
1. personal_history - 用户想了解自己的过往经历、做过的事情
2. relationship - 用户关心的人际关系、朋友、家人相关信息  
3. preference - 用户的个人偏好、喜好、习惯相关
4. goal_tracking - 用户的目标、计划、进展跟踪相关
5. behavior_pattern - 用户的行为模式、习惯分析相关
6. emotional_context - 用户的情感状态、心情历史相关
7. temporal_context - 特定时间段的用户信息需求

输出JSON格式：
{
  "personal_focuses": [
    {
      "description": "用户个人信息需求的自然语言描述，如：用户想了解自己最近的约会经历和感受",
      "type": "personal_history/relationship/preference/goal_tracking/behavior_pattern/emotional_context/temporal_context",
      "intensity": 0.8,
      "keywords": ["约会", "感受", "最近"],
      "entities": ["用户", "朋友", "伴侣"],
      "reasoning": "识别这个个人信息需求的推理过程",
      "context": {
        "trigger_text": "触发这个需求的具体文本",
        "time_scope": "时间范围：recent/past_week/past_month/long_term",
        "info_type": "信息类型：experience/relationship/emotion/habit/goal"
      }
    }
  ],
  "conversation_summary": "对话内容的简要总结",
  "personal_context_hints": ["用户个人上下文的提示信息"],
  "expected_personal_info": ["用户可能期望的个人信息类型"]
}

对话内容：
$conversationContext

请专注于识别用户个人信息相关的需求，忽略通用知识查询。
""";

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: analysisPrompt);
      final response = await llm.createRequest(content: '请分析这段对话中的用户个人信息关注点');

      // 解析JSON响应
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) {
        throw FormatException('LLM未返回有效的JSON格式');
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;

      return result;
    } catch (e) {
      print('[PersonalCache] ⚠️ LLM个人信息关注点分析失败，使用备用方法: $e');
      return await _fallbackPersonalFocusAnalysis(conversationContext);
    }
  }

  // 备用个人信息关注点分析方法
  Future<Map<String, dynamic>> _fallbackPersonalFocusAnalysis(String conversationContext) async {
    // 使用关键词匹配识别个人信息相关的需求
    try {
      final personalKeywords = {
        'personal_history': ['我的', '我之前', '我以前', '我曾经', '我做过', '我去过', '记得我'],
        'relationship': ['我朋友', '我家人', '我和', '我们', '朋友', '家人', '男友', '女友', '伴侣'],
        'preference': ['我喜欢', '我不喜欢', '我习惯', '我通常', '我偏好'],
        'goal_tracking': ['我的目标', '我计划', '我想要', '我的进展', '我的计划'],
        'behavior_pattern': ['我经常', '我总是', '我很少', '我从不', '我习惯'],
        'emotional_context': ['我觉得', '我感觉', '我心情', '我开心', '我难过', '我压力'],
        'temporal_context': ['最近', '昨天', '上周', '这个月', '去年'],
      };

      final detectedFocuses = <Map<String, dynamic>>[];

      for (final entry in personalKeywords.entries) {
        final type = entry.key;
        final keywords = entry.value;

        for (final keyword in keywords) {
          if (conversationContext.contains(keyword)) {
            detectedFocuses.add({
              'description': '用户询问与${type}相关的个人信息',
              'type': type,
              'intensity': 0.6,
              'keywords': [keyword],
              'entities': ['用户'],
              'reasoning': '基于关键词"$keyword"识别',
              'context': {
                'trigger_text': conversationContext.length > 100 ? conversationContext.substring(0, 100) + '...' : conversationContext,
                'time_scope': _detectTimeScope(conversationContext),
                'info_type': _detectInfoType(type),
              }
            });
            break; // 每个类型最多添加一个
          }
        }
      }

      if (detectedFocuses.isEmpty) {
        // 如果没有检测到明确的个人信息需求，添加一个默认的
        detectedFocuses.add({
          'description': '用户可能需要相关的个人背景信息',
          'type': 'personal_history',
          'intensity': 0.4,
          'keywords': ['对话'],
          'entities': ['用户'],
          'reasoning': '基于对话上下文推断',
          'context': {
            'trigger_text': conversationContext.length > 50 ? conversationContext.substring(0, 50) + '...' : conversationContext,
            'time_scope': 'recent',
            'info_type': 'context',
          }
        });
      }

      return {
        'personal_focuses': detectedFocuses,
        'conversation_summary': '用户进行了个人相关的对话',
        'personal_context_hints': ['需要检索用户个人信息'],
        'expected_personal_info': ['用户历史', '个人偏好']
      };
    } catch (e) {
      // 最基本的备用方案
      return {
        'personal_focuses': [
          {
            'description': '用户可能需要个人背景信息',
            'type': 'personal_history',
            'intensity': 0.3,
            'keywords': ['用户'],
            'entities': ['用户'],
            'reasoning': '默认个人信息需求',
            'context': {
              'trigger_text': conversationContext.length > 50 ? conversationContext.substring(0, 50) + '...' : conversationContext,
              'time_scope': 'recent',
              'info_type': 'general',
            }
          }
        ],
        'conversation_summary': '用户进行了对话',
        'personal_context_hints': [],
        'expected_personal_info': []
      };
    }
  }

  String _detectTimeScope(String text) {
    if (text.contains('最近') || text.contains('今天') || text.contains('昨天')) return 'recent';
    if (text.contains('这周') || text.contains('上周')) return 'past_week';
    if (text.contains('这个月') || text.contains('上个月')) return 'past_month';
    return 'long_term';
  }

  String _detectInfoType(String type) {
    switch (type) {
      case 'personal_history': return 'experience';
      case 'relationship': return 'relationship';
      case 'emotional_context': return 'emotion';
      case 'behavior_pattern': return 'habit';
      case 'goal_tracking': return 'goal';
      default: return 'general';
    }
  }

  // 处理关注点分析结果
  Future<void> _processFocusAnalysisResults(Map<String, dynamic> analysisResult) async {
    final focuses = analysisResult['personal_focuses'] as List? ?? [];
    final now = DateTime.now();

    for (final focusData in focuses) {
      if (focusData is Map<String, dynamic>) {
        final description = focusData['description']?.toString() ?? '';
        final typeStr = focusData['type']?.toString() ?? 'personal_history';
        final intensity = (focusData['intensity'] as num?)?.toDouble() ?? 0.5;
        final keywords = (focusData['keywords'] as List?)?.map((k) => k.toString()).toList() ?? [];
        final entities = (focusData['entities'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final context = focusData['context'] as Map<String, dynamic>? ?? {};

        // 过滤掉强度过低的关注点
        if (intensity < minFocusIntensity) continue;

        // 解析关注点类型
        FocusType type = FocusType.personal_history;
        switch (typeStr) {
          case 'relationship':
            type = FocusType.relationship;
            break;
          case 'preference':
            type = FocusType.preference;
            break;
          case 'goal_tracking':
            type = FocusType.goal_tracking;
            break;
          case 'behavior_pattern':
            type = FocusType.behavior_pattern;
            break;
          case 'emotional_context':
            type = FocusType.emotional_context;
            break;
          case 'temporal_context':
            type = FocusType.temporal_context;
            break;
        }

        // 创建关注点
        final focusId = 'deep_focus_${now.millisecondsSinceEpoch}_${_userFocuses.length}';
        final userFocus = UserFocus(
          focusId: focusId,
          description: description,
          type: type,
          intensity: intensity,
          keywords: keywords,
          entities: entities,
          identifiedAt: now,
          context: {...context, 'analysis_type': 'deep_llm'},
        );

        _userFocuses[focusId] = userFocus;
        print('[PersonalCache] 🔍 深度识别个人信息关注点: $description (强度: ${intensity.toStringAsFixed(2)})');
      }
    }

    // 清理过期的关注点
    _cleanupExpiredFocuses();
  }
}
