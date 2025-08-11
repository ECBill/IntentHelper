/// 个性化理解服务
/// 基于人类理解系统的结果，结合用户历史知识图谱，为 LLM 提供个性化上下文

import 'dart:async';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/human_understanding_system.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';

/// 用户个性化上下文模型
class PersonalizedContext {
  final Map<String, dynamic> currentSemanticState;
  final Map<String, dynamic> longTermProfile;
  final Map<String, dynamic> contextualRecommendations;
  final Map<String, dynamic> interactionHistory;
  final DateTime generatedAt;

  PersonalizedContext({
    required this.currentSemanticState,
    required this.longTermProfile,
    required this.contextualRecommendations,
    required this.interactionHistory,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'current_semantic_state': currentSemanticState,
    'long_term_profile': longTermProfile,
    'contextual_recommendations': contextualRecommendations,
    'interaction_history': interactionHistory,
    'generated_at': generatedAt.toIso8601String(),
  };
}

class PersonalizedUnderstandingService {
  static final PersonalizedUnderstandingService _instance = PersonalizedUnderstandingService._internal();
  factory PersonalizedUnderstandingService() => _instance;
  PersonalizedUnderstandingService._internal();

  final HumanUnderstandingSystem _understandingSystem = HumanUnderstandingSystem();
  bool _initialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    print('[PersonalizedUnderstandingService] 🚀 初始化个性化理解服务...');

    // 确保人类理解系统已初始化
    await _understandingSystem.initialize();

    _initialized = true;
    print('[PersonalizedUnderstandingService] ✅ 个性化理解服务初始化完成');
  }

  /// 生成个性���上下文（主要接口）
  Future<PersonalizedContext> generatePersonalizedContext({
    String? userInput,
    List<String>? focusKeywords,
    int historicalDays = 30,
  }) async {
    if (!_initialized) await initialize();

    print('[PersonalizedUnderstandingService] 🧠 生成个性化上下文...');

    try {
      // 1. 获取当前语义状态
      final currentState = await _extractCurrentSemanticState();

      // 2. 构建长期用户档案
      final longTermProfile = await _buildLongTermUserProfile(
        focusKeywords: focusKeywords,
        historicalDays: historicalDays,
      );

      // 3. 生成上下文推荐
      final recommendations = await _generateContextualRecommendations(
        currentState: currentState,
        userProfile: longTermProfile,
        userInput: userInput,
      );

      // 4. 整合交互历史
      final interactionHistory = await _extractRelevantInteractionHistory(
        keywords: focusKeywords,
        days: historicalDays,
      );

      final personalizedContext = PersonalizedContext(
        currentSemanticState: currentState,
        longTermProfile: longTermProfile,
        contextualRecommendations: recommendations,
        interactionHistory: interactionHistory,
        generatedAt: DateTime.now(),
      );

      print('[PersonalizedUnderstandingService] ✅ 个性化上下文生成完成');
      return personalizedContext;

    } catch (e) {
      print('[PersonalizedUnderstandingService] ❌ 生成个性化上下文失败: $e');
      rethrow;
    }
  }

  /// 1. 提取当前语义状态
  Future<Map<String, dynamic>> _extractCurrentSemanticState() async {
    try {
      final systemState = _understandingSystem.getCurrentState();

      // 提取关键语义信息
      final semanticState = <String, dynamic>{};

      // 当前活跃意图分析
      final activeIntents = systemState.activeIntents;
      semanticState['active_intents'] = {
        'count': activeIntents.length,
        'categories': _analyzeIntentCategories(activeIntents),
        'urgency_distribution': _analyzeIntentUrgency(activeIntents),
        'recent_intents': activeIntents.take(3).map((intent) => {
          'description': intent.description,
          'category': intent.category,
          'state': intent.state.toString().split('.').last,
          'confidence': intent.confidence,
          'context': intent.context,
        }).toList(),
      };

      // 当前话题分析
      final activeTopics = systemState.activeTopics;
      semanticState['active_topics'] = {
        'count': activeTopics.length,
        'focus_areas': _analyzeTopicFocusAreas(activeTopics),
        'relevance_scores': activeTopics.map((topic) => {
          'name': topic.name,
          'relevance': topic.relevanceScore,
          'category': topic.category,
        }).toList(),
      };

      // 认知负载状态
      final cognitiveLoad = systemState.currentCognitiveLoad;
      semanticState['cognitive_state'] = {
        'load_level': cognitiveLoad.level.toString().split('.').last,
        'load_score': cognitiveLoad.score,
        'capacity_utilization': _calculateCapacityUtilization(cognitiveLoad),
        'recommendation': cognitiveLoad.recommendation,
        'factors': cognitiveLoad.factors,
      };

      // 因果链分析
      final causalChains = systemState.recentCausalChains;
      semanticState['causal_patterns'] = {
        'recent_chains_count': causalChains.length,
        'dominant_patterns': _analyzeCausalPatterns(causalChains),
        'behavioral_insights': _extractBehavioralInsights(causalChains),
      };

      // 语义图谱连接
      final semanticTriples = systemState.recentTriples;
      semanticState['semantic_connections'] = {
        'recent_connections': semanticTriples.length,
        'connection_types': _analyzeConnectionTypes(semanticTriples),
        'knowledge_density': _calculateKnowledgeDensity(semanticTriples),
      };

      return semanticState;

    } catch (e) {
      print('[PersonalizedUnderstandingService] ❌ 提取当前语义状态失败: $e');
      return {};
    }
  }

  /// 2. 构建长期用户档案
  Future<Map<String, dynamic>> _buildLongTermUserProfile({
    List<String>? focusKeywords,
    int historicalDays = 30,
  }) async {
    try {
      final objectBox = ObjectBoxService();
      final profile = <String, dynamic>{};

      // 获取历史时间范围
      final cutoffTime = DateTime.now().subtract(Duration(days: historicalDays)).millisecondsSinceEpoch;

      // 从知识图谱中提取长期偏好
      final nodes = objectBox.queryNodes();
      final events = objectBox.queryEventNodes();

      // 分析用户兴趣实体
      final interestEntities = await _analyzeUserInterestEntities(nodes, events, cutoffTime);
      profile['interest_entities'] = interestEntities;

      // 分析行为模式
      final behaviorPatterns = await _analyzeBehaviorPatterns(events, cutoffTime);
      profile['behavior_patterns'] = behaviorPatterns;

      // 分析技能和知识领域
      final knowledgeDomains = await _analyzeKnowledgeDomains(nodes, events);
      profile['knowledge_domains'] = knowledgeDomains;

      // 分析社交网络
      final socialNetwork = await _analyzeSocialNetwork(nodes, events);
      profile['social_network'] = socialNetwork;

      // 分析时间偏好
      final timePreferences = await _analyzeTimePreferences(events, cutoffTime);
      profile['time_preferences'] = timePreferences;

      // 分析目标导向
      final goalOrientation = await _analyzeGoalOrientation(nodes, events);
      profile['goal_orientation'] = goalOrientation;

      return profile;

    } catch (e) {
      print('[PersonalizedUnderstandingService] ❌ 构建长期用户档案失败: $e');
      return {};
    }
  }

  /// 3. 生成上下文推荐
  Future<Map<String, dynamic>> _generateContextualRecommendations({
    required Map<String, dynamic> currentState,
    required Map<String, dynamic> userProfile,
    String? userInput,
  }) async {
    try {
      final recommendations = <String, dynamic>{};

      // 基于当前意图的推荐
      final intentRecommendations = _generateIntentBasedRecommendations(currentState, userProfile);
      recommendations['intent_based'] = intentRecommendations;

      // 基于认知负载的推荐
      final cognitiveRecommendations = _generateCognitiveLoadRecommendations(currentState, userProfile);
      recommendations['cognitive_based'] = cognitiveRecommendations;

      // 基于历史模式的推荐
      final patternRecommendations = _generatePatternBasedRecommendations(currentState, userProfile);
      recommendations['pattern_based'] = patternRecommendations;

      // 基于用户输入的推荐
      if (userInput != null && userInput.isNotEmpty) {
        final inputRecommendations = await _generateInputBasedRecommendations(userInput, currentState, userProfile);
        recommendations['input_based'] = inputRecommendations;
      }

      // 主动建议
      final proactiveRecommendations = _generateProactiveRecommendations(currentState, userProfile);
      recommendations['proactive'] = proactiveRecommendations;

      return recommendations;

    } catch (e) {
      print('[PersonalizedUnderstandingService] ❌ 生成上下文推荐失败: $e');
      return {};
    }
  }

  /// 4. 提取相关交互历史
  Future<Map<String, dynamic>> _extractRelevantInteractionHistory({
    List<String>? keywords,
    int days = 30,
  }) async {
    try {
      final objectBox = ObjectBoxService();
      final cutoffTime = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

      // 获取最近的对话记录
      final recentRecords = objectBox.getRecordsSince(cutoffTime);

      // 如果有关键词，过滤相关记录
      List<dynamic> relevantRecords = recentRecords;
      if (keywords != null && keywords.isNotEmpty) {
        relevantRecords = recentRecords.where((record) {
          final content = record.content?.toString().toLowerCase() ?? '';
          return keywords.any((keyword) => content.contains(keyword.toLowerCase()));
        }).toList();
      }

      // 分析交互模式
      final interactionHistory = <String, dynamic>{};

      // 对话频率分析
      interactionHistory['conversation_frequency'] = _analyzeConversationFrequency(relevantRecords);

      // 主题演变分析
      interactionHistory['topic_evolution'] = _analyzeTopicEvolution(relevantRecords);

      // 情感状态历史
      interactionHistory['emotional_journey'] = _analyzeEmotionalJourney(relevantRecords);

      // 问题解决历史
      interactionHistory['problem_solving_history'] = _analyzeProblemSolvingHistory(relevantRecords);

      return interactionHistory;

    } catch (e) {
      print('[PersonalizedUnderstandingService] ❌ 提取交互历史失败: $e');
      return {};
    }
  }

  /// 为 LLM 构建结构化输入
  Future<Map<String, dynamic>> buildLLMInput({
    required String userInput,
    List<String>? contextKeywords,
    bool includeDetailedHistory = false,
  }) async {
    try {
      print('[PersonalizedUnderstandingService] 🤖 为 LLM 构建结构化输入...');

      // 生成个性化上下文
      final personalizedContext = await generatePersonalizedContext(
        userInput: userInput,
        focusKeywords: contextKeywords,
        historicalDays: includeDetailedHistory ? 60 : 30,
      );

      // 构建 LLM 专用的结构化输入
      final llmInput = <String, dynamic>{};

      // 用户当前状态摘要
      llmInput['user_current_state'] = _buildCurrentStateSummary(personalizedContext.currentSemanticState);

      // 用户个性化档案摘要
      llmInput['user_profile_summary'] = _buildProfileSummary(personalizedContext.longTermProfile);

      // 上下文建议
      llmInput['contextual_suggestions'] = _buildContextualSuggestions(personalizedContext.contextualRecommendations);

      // 相关历史上下文
      llmInput['relevant_history'] = _buildRelevantHistoryContext(personalizedContext.interactionHistory);

      // 对话指导原则
      llmInput['conversation_guidelines'] = _buildConversationGuidelines(personalizedContext);

      // 元信息
      llmInput['meta_info'] = {
        'context_generated_at': personalizedContext.generatedAt.toIso8601String(),
        'context_freshness': 'fresh',
        'personalization_level': _calculatePersonalizationLevel(personalizedContext),
      };

      print('[PersonalizedUnderstandingService] ✅ LLM 输入构建完成');
      return llmInput;

    } catch (e) {
      print('[PersonalizedUnderstandingService] ❌ 构建 LLM 输入失败: $e');
      return {};
    }
  }

  /// 分析意��类别分布
  Map<String, int> _analyzeIntentCategories(List<Intent> intents) {
    final categories = <String, int>{};
    for (final intent in intents) {
      categories[intent.category] = (categories[intent.category] ?? 0) + 1;
    }
    return categories;
  }

  /// 分析意图紧急性分布
  Map<String, int> _analyzeIntentUrgency(List<Intent> intents) {
    final urgency = <String, int>{};
    for (final intent in intents) {
      final urgencyLevel = intent.context['urgency']?.toString() ?? 'medium';
      urgency[urgencyLevel] = (urgency[urgencyLevel] ?? 0) + 1;
    }
    return urgency;
  }

  /// 分析话题焦点领域
  Map<String, dynamic> _analyzeTopicFocusAreas(List<ConversationTopic> topics) {
    final focusAreas = <String, double>{};
    double totalRelevance = 0;

    for (final topic in topics) {
      focusAreas[topic.category] = (focusAreas[topic.category] ?? 0) + topic.relevanceScore;
      totalRelevance += topic.relevanceScore;
    }

    // 归一化
    if (totalRelevance > 0) {
      focusAreas.updateAll((key, value) => value / totalRelevance);
    }

    return focusAreas;
  }

  /// 计算容量利用率
  double _calculateCapacityUtilization(CognitiveLoadAssessment load) {
    // 基于负载级别和分��计算容量利用率
    switch (load.level) {
      case CognitiveLoadLevel.low:
        return load.score * 0.4;
      case CognitiveLoadLevel.moderate:
        return 0.4 + (load.score * 0.3);
      case CognitiveLoadLevel.high:
        return 0.7 + (load.score * 0.2);
      case CognitiveLoadLevel.overload:
        return 0.9 + (load.score * 0.1);
    }
  }

  /// 分析因果模式
  Map<String, dynamic> _analyzeCausalPatterns(List<CausalRelation> chains) {
    final patterns = <String, int>{};
    final insights = <String>[];

    for (final relation in chains) {
      // 🔥 修复：使用正确的字段名
      final patternType = '${relation.type.toString().split('.').last} → ${relation.effect}';
      patterns[patternType] = (patterns[patternType] ?? 0) + 1;

      // 提取行为洞察
      if (relation.confidence > 0.7) {
        insights.add('用户倾向于 ${relation.cause} 导致 ${relation.effect}');
      }
    }

    return {
      'patterns': patterns,
      'insights': insights.take(3).toList(),
    };
  }

  /// 提取行为洞察
  List<String> _extractBehavioralInsights(List<CausalRelation> chains) {
    final insights = <String>[];

    // 基于因果链提取行为模式
    final highConfidenceChains = chains.where((c) => c.confidence > 0.7).toList();

    for (final chain in highConfidenceChains) {
      // 🔥 修复：使用正确的字段名和类型判断
      final relationTypeStr = chain.type.toString().split('.').last;
      if (relationTypeStr == 'directCause') {
        insights.add('行动模式: ${chain.cause} 通常直接导致 ${chain.effect}');
      } else if (relationTypeStr == 'correlation') {
        insights.add('关联模式: ${chain.cause} 与 ${chain.effect} 存在关联');
      }
    }

    return insights.take(5).toList();
  }

  /// 分析连接类型
  Map<String, int> _analyzeConnectionTypes(List<SemanticTriple> triples) {
    final types = <String, int>{};
    for (final triple in triples) {
      types[triple.predicate] = (types[triple.predicate] ?? 0) + 1;
    }
    return types;
  }

  /// 计算知识密度
  double _calculateKnowledgeDensity(List<SemanticTriple> triples) {
    if (triples.isEmpty) return 0.0;

    final uniqueEntities = <String>{};
    for (final triple in triples) {
      uniqueEntities.add(triple.subject);
      uniqueEntities.add(triple.object);
    }

    // 知识密度 = 连接数 / 实体数
    return triples.length / uniqueEntities.length;
  }

  /// 分析用户兴趣实体
  Future<Map<String, dynamic>> _analyzeUserInterestEntities(
    List<Node> nodes,
    List<EventNode> events,
    int cutoffTime
  ) async {
    final interests = <String, double>{};
    final categories = <String, int>{};

    // 基于节点出现频率分析兴趣
    for (final node in nodes) {
      if (node.lastUpdated.millisecondsSinceEpoch > cutoffTime) {
        interests[node.name] = (interests[node.name] ?? 0) + 1.0;
        categories[node.type] = (categories[node.type] ?? 0) + 1;
      }
    }

    // 基于事件参与度分析兴趣
    for (final event in events) {
      if (event.lastUpdated.millisecondsSinceEpoch > cutoffTime) {
        interests[event.name] = (interests[event.name] ?? 0) + 0.5;
        categories[event.type] = (categories[event.type] ?? 0) + 1;
      }
    }

    // 排序并取前10
    final sortedInterests = interests.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'top_interests': sortedInterests.take(10).map((e) => {
        'entity': e.key,
        'score': e.value,
      }).toList(),
      'interest_categories': categories,
      'total_unique_interests': interests.length,
    };
  }

  /// 分析行为模式
  Future<Map<String, dynamic>> _analyzeBehaviorPatterns(
    List<EventNode> events,
    int cutoffTime
  ) async {
    final patterns = <String, dynamic>{};

    // 过滤最近事件
    final recentEvents = events.where((e) =>
      e.lastUpdated.millisecondsSinceEpoch > cutoffTime
    ).toList();

    // 分析事件类型分布
    final eventTypes = <String, int>{};
    final timePatterns = <int, int>{}; // 小时 -> 事件数

    for (final event in recentEvents) {
      eventTypes[event.type] = (eventTypes[event.type] ?? 0) + 1;

      // 分析时间模式
      final hour = event.startTime?.hour ?? event.lastUpdated.hour;
      timePatterns[hour] = (timePatterns[hour] ?? 0) + 1;
    }

    patterns['activity_types'] = eventTypes;
    patterns['time_patterns'] = timePatterns;
    patterns['activity_frequency'] = recentEvents.length / 30.0; // 平均每天事件数

    return patterns;
  }

  /// 分析知识领域
  Future<Map<String, dynamic>> _analyzeKnowledgeDomains(
    List<Node> nodes,
    List<EventNode> events
  ) async {
    final domains = <String, dynamic>{};

    // 技术领域
    final techNodes = nodes.where((n) =>
      n.type == '技能' || n.type == '技术' || n.type == '工具'
    ).toList();

    // 学习领域
    final learningEvents = events.where((e) =>
      e.type.contains('学习') || e.type.contains('教程')
    ).toList();

    domains['technical_skills'] = techNodes.map((n) => n.name).toList();
    domains['learning_activities'] = learningEvents.map((e) => e.name).toList();
    domains['skill_level'] = _estimateSkillLevel(techNodes, learningEvents);

    return domains;
  }

  /// 估算技能水平
  String _estimateSkillLevel(List<Node> techNodes, List<EventNode> learningEvents) {
    final score = techNodes.length * 0.3 + learningEvents.length * 0.2;

    if (score > 10) return 'advanced';
    if (score > 5) return 'intermediate';
    return 'beginner';
  }

  /// 分析社交网络
  Future<Map<String, dynamic>> _analyzeSocialNetwork(
    List<Node> nodes,
    List<EventNode> events
  ) async {
    final network = <String, dynamic>{};

    // 提取人物节点
    final people = nodes.where((n) => n.type == '人物').toList();

    // 分析交互频率
    final interactions = <String, int>{};
    for (final event in events) {
      // 这里需要根据事件关系表来分析
      // 简化实现
      if (event.type.contains('讨论') || event.type.contains('会议')) {
        interactions['collaboration'] = (interactions['collaboration'] ?? 0) + 1;
      }
    }

    network['contacts'] = people.map((p) => p.name).toList();
    network['interaction_patterns'] = interactions;
    network['social_activity_level'] = _calculateSocialActivityLevel(interactions);

    return network;
  }

  /// 计算社交活跃度
  String _calculateSocialActivityLevel(Map<String, int> interactions) {
    final total = interactions.values.fold(0, (sum, count) => sum + count);

    if (total > 20) return 'high';
    if (total > 10) return 'medium';
    return 'low';
  }

  /// 分析时间偏好
  Future<Map<String, dynamic>> _analyzeTimePreferences(
    List<EventNode> events,
    int cutoffTime
  ) async {
    final preferences = <String, dynamic>{};

    final recentEvents = events.where((e) =>
      e.lastUpdated.millisecondsSinceEpoch > cutoffTime
    ).toList();

    // 分析活跃时段
    final hourDistribution = <int, int>{};
    for (final event in recentEvents) {
      final hour = event.startTime?.hour ?? event.lastUpdated.hour;
      hourDistribution[hour] = (hourDistribution[hour] ?? 0) + 1;
    }

    // 找出最活跃的时段
    final sortedHours = hourDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    preferences['peak_hours'] = sortedHours.take(3).map((e) => e.key).toList();
    preferences['activity_distribution'] = hourDistribution;

    return preferences;
  }

  /// 分析目标导向
  Future<Map<String, dynamic>> _analyzeGoalOrientation(
    List<Node> nodes,
    List<EventNode> events
  ) async {
    final orientation = <String, dynamic>{};

    // 分析目标相关的节点和事件
    final goalNodes = nodes.where((n) =>
      n.name.contains('目标') || n.name.contains('计划') || n.type == '目标'
    ).toList();

    final planningEvents = events.where((e) =>
      e.type.contains('规划') || e.type.contains('计划')
    ).toList();

    orientation['explicit_goals'] = goalNodes.map((n) => n.name).toList();
    orientation['planning_activity'] = planningEvents.length;
    orientation['goal_orientation_level'] = _calculateGoalOrientationLevel(goalNodes, planningEvents);

    return orientation;
  }

  /// 计算目标导向水平
  String _calculateGoalOrientationLevel(List<Node> goalNodes, List<EventNode> planningEvents) {
    final score = goalNodes.length * 0.4 + planningEvents.length * 0.3;

    if (score > 5) return 'high';
    if (score > 2) return 'medium';
    return 'low';
  }

  // ... 继续实现其他辅助方法

  /// 构建当前状态摘要
  Map<String, dynamic> _buildCurrentStateSummary(Map<String, dynamic> currentState) {
    return {
      'focus_level': _extractFocusLevel(currentState),
      'primary_intents': _extractPrimaryIntents(currentState),
      'cognitive_capacity': _extractCognitiveCapacity(currentState),
      'current_topics': _extractCurrentTopics(currentState),
    };
  }

  String _extractFocusLevel(Map<String, dynamic> state) {
    final cognitiveState = state['cognitive_state'] as Map<String, dynamic>? ?? {};
    final loadLevel = cognitiveState['load_level']?.toString() ?? 'moderate';

    switch (loadLevel) {
      case 'low': return 'high_focus';
      case 'moderate': return 'medium_focus';
      case 'high': return 'low_focus';
      case 'overload': return 'scattered_focus';
      default: return 'medium_focus';
    }
  }

  List<String> _extractPrimaryIntents(Map<String, dynamic> state) {
    final activeIntents = state['active_intents'] as Map<String, dynamic>? ?? {};
    final recentIntents = activeIntents['recent_intents'] as List? ?? [];

    return recentIntents.take(3).map((intent) =>
      intent['description']?.toString() ?? ''
    ).where((desc) => desc.isNotEmpty).toList();
  }

  Map<String, dynamic> _extractCognitiveCapacity(Map<String, dynamic> state) {
    final cognitiveState = state['cognitive_state'] as Map<String, dynamic>? ?? {};

    return {
      'capacity_utilization': cognitiveState['capacity_utilization'] ?? 0.5,
      'recommendation': cognitiveState['recommendation'] ?? '保持当前状态',
      'load_level': cognitiveState['load_level'] ?? 'moderate',
    };
  }

  List<String> _extractCurrentTopics(Map<String, dynamic> state) {
    final activeTopics = state['active_topics'] as Map<String, dynamic>? ?? {};
    final relevanceScores = activeTopics['relevance_scores'] as List? ?? [];

    return relevanceScores.take(3).map((topic) =>
      topic['name']?.toString() ?? ''
    ).where((name) => name.isNotEmpty).toList();
  }

  /// 生成基于意图的推荐
  Map<String, dynamic> _generateIntentBasedRecommendations(
    Map<String, dynamic> currentState,
    Map<String, dynamic> userProfile
  ) {
    final recommendations = <String, dynamic>{};

    final activeIntents = currentState['active_intents'] as Map<String, dynamic>? ?? {};
    final categories = activeIntents['categories'] as Map<String, dynamic>? ?? {};

    // 基于意图类别生成建议
    if (categories.containsKey('learning') && categories['learning'] > 0) {
      recommendations['learning_support'] = '根据你的学习意图，推荐相关资源和学习路径';
    }

    if (categories.containsKey('planning') && categories['planning'] > 0) {
      recommendations['planning_assistance'] = '帮助你制定更详细的计划和时间安排';
    }

    return recommendations;
  }

  /// 生成基于认知负载的推荐
  Map<String, dynamic> _generateCognitiveLoadRecommendations(
    Map<String, dynamic> currentState,
    Map<String, dynamic> userProfile
  ) {
    final recommendations = <String, dynamic>{};

    final cognitiveState = currentState['cognitive_state'] as Map<String, dynamic>? ?? {};
    final loadLevel = cognitiveState['load_level']?.toString() ?? 'moderate';

    switch (loadLevel) {
      case 'low':
        recommendations['capacity_utilization'] = '当前认知负载较低，可以承担更多任务';
        break;
      case 'high':
        recommendations['load_management'] = '当前认知负载较高，建议优先处理重要任务';
        break;
      case 'overload':
        recommendations['urgent_action'] = '认知负载过高，需要立即减少任务或休息';
        break;
    }

    return recommendations;
  }

  /// 生成基于模式的推荐
  Map<String, dynamic> _generatePatternBasedRecommendations(
    Map<String, dynamic> currentState,
    Map<String, dynamic> userProfile
  ) {
    final recommendations = <String, dynamic>{};

    final behaviorPatterns = userProfile['behavior_patterns'] as Map<String, dynamic>? ?? {};
    final timePatterns = behaviorPatterns['time_patterns'] as Map<String, dynamic>? ?? {};

    // 基于时间模式给出建议
    final currentHour = DateTime.now().hour;
    final currentHourActivity = timePatterns[currentHour.toString()] ?? 0;

    if (currentHourActivity > 5) {
      recommendations['optimal_timing'] = '这是你通常活跃的时间段，适合处理重要任务';
    }

    return recommendations;
  }

  /// 生成基于输入的推荐
  Future<Map<String, dynamic>> _generateInputBasedRecommendations(
    String userInput,
    Map<String, dynamic> currentState,
    Map<String, dynamic> userProfile
  ) async {
    final recommendations = <String, dynamic>{};

    // 分析用户输入中的关键信息
    final inputLower = userInput.toLowerCase();

    if (inputLower.contains('学习') || inputLower.contains('教程')) {
      final knowledgeDomains = userProfile['knowledge_domains'] as Map<String, dynamic>? ?? {};
      recommendations['learning_path'] = '基于你的背景，推荐适合的学习资源';
    }

    if (inputLower.contains('计划') || inputLower.contains('安排')) {
      final timePreferences = userProfile['time_preferences'] as Map<String, dynamic>? ?? {};
      recommendations['schedule_optimization'] = '根据你的时间偏好，优化计划安排';
    }

    return recommendations;
  }

  /// 生成主动推荐
  Map<String, dynamic> _generateProactiveRecommendations(
    Map<String, dynamic> currentState,
    Map<String, dynamic> userProfile
  ) {
    final recommendations = <String, dynamic>{};

    // 基于用户档案主动推荐
    final goalOrientation = userProfile['goal_orientation'] as Map<String, dynamic>? ?? {};
    final orientationLevel = goalOrientation['goal_orientation_level']?.toString() ?? 'medium';

    if (orientationLevel == 'high') {
      recommendations['goal_tracking'] = '建议定期回顾和调整你的目标进展';
    }

    final socialNetwork = userProfile['social_network'] as Map<String, dynamic>? ?? {};
    final activityLevel = socialNetwork['social_activity_level']?.toString() ?? 'medium';

    if (activityLevel == 'low') {
      recommendations['social_engagement'] = '考虑增加与他人的交流互动';
    }

    return recommendations;
  }

  // ... 继续实现其他分析方法

  /// 分析对话频率
  Map<String, dynamic> _analyzeConversationFrequency(List<dynamic> records) {
    // 简化实现
    return {
      'daily_average': records.length / 30.0,
      'total_conversations': records.length,
      'engagement_level': records.length > 100 ? 'high' : records.length > 50 ? 'medium' : 'low',
    };
  }

  /// 分析话题演变
  Map<String, dynamic> _analyzeTopicEvolution(List<dynamic> records) {
    // 简化实现 - 实际应该分析话题变化趋势
    final topics = <String>[];
    for (final record in records.take(10)) {
      final content = record.content?.toString() ?? '';
      if (content.contains('学习')) topics.add('学习');
      if (content.contains('工作')) topics.add('工作');
      if (content.contains('技术')) topics.add('技术');
    }

    return {
      'recent_topics': topics.toSet().toList(),
      'topic_diversity': topics.toSet().length,
    };
  }

  /// 分析情感历程
  Map<String, dynamic> _analyzeEmotionalJourney(List<dynamic> records) {
    // 简化实现
    return {
      'overall_sentiment': 'neutral',
      'emotional_stability': 'stable',
      'recent_mood_trend': 'positive',
    };
  }

  /// 分析问题解决历史
  Map<String, dynamic> _analyzeProblemSolvingHistory(List<dynamic> records) {
    final problemKeywords = ['问题', 'bug', '错误', '困难', '挑战'];
    final solutionKeywords = ['解决', '完成', '成功', '修复', '优化'];

    int problemCount = 0;
    int solutionCount = 0;

    for (final record in records) {
      final content = record.content?.toString().toLowerCase() ?? '';
      if (problemKeywords.any((keyword) => content.contains(keyword))) {
        problemCount++;
      }
      if (solutionKeywords.any((keyword) => content.contains(keyword))) {
        solutionCount++;
      }
    }

    return {
      'problem_identification_count': problemCount,
      'solution_implementation_count': solutionCount,
      'resolution_rate': problemCount > 0 ? solutionCount / problemCount : 0.0,
      'problem_solving_style': solutionCount > problemCount ? 'proactive' : 'reactive',
    };
  }

  /// 构建用户档案摘要
  Map<String, dynamic> _buildProfileSummary(Map<String, dynamic> longTermProfile) {
    return {
      'expertise_areas': _extractExpertiseAreas(longTermProfile),
      'interaction_style': _extractInteractionStyle(longTermProfile),
      'preferred_topics': _extractPreferredTopics(longTermProfile),
      'goal_orientation': _extractGoalOrientation(longTermProfile),
    };
  }

  List<String> _extractExpertiseAreas(Map<String, dynamic> profile) {
    final knowledgeDomains = profile['knowledge_domains'] as Map<String, dynamic>? ?? {};
    final technicalSkills = knowledgeDomains['technical_skills'] as List? ?? [];
    return technicalSkills.take(5).map((skill) => skill.toString()).toList();
  }

  String _extractInteractionStyle(Map<String, dynamic> profile) {
    final socialNetwork = profile['social_network'] as Map<String, dynamic>? ?? {};
    final activityLevel = socialNetwork['social_activity_level']?.toString() ?? 'medium';

    switch (activityLevel) {
      case 'high': return 'collaborative';
      case 'medium': return 'balanced';
      case 'low': return 'independent';
      default: return 'balanced';
    }
  }

  List<String> _extractPreferredTopics(Map<String, dynamic> profile) {
    final interestEntities = profile['interest_entities'] as Map<String, dynamic>? ?? {};
    final topInterests = interestEntities['top_interests'] as List? ?? [];
    return topInterests.take(5).map((interest) =>
      interest['entity']?.toString() ?? ''
    ).where((topic) => topic.isNotEmpty).toList();
  }

  String _extractGoalOrientation(Map<String, dynamic> profile) {
    final goalOrientation = profile['goal_orientation'] as Map<String, dynamic>? ?? {};
    return goalOrientation['goal_orientation_level']?.toString() ?? 'medium';
  }

  /// 构建上下文建议
  Map<String, dynamic> _buildContextualSuggestions(Map<String, dynamic> recommendations) {
    final suggestions = <String, dynamic>{};

    // 整合各类推荐
    final intentBased = recommendations['intent_based'] as Map<String, dynamic>? ?? {};
    final cognitiveBased = recommendations['cognitive_based'] as Map<String, dynamic>? ?? {};
    final patternBased = recommendations['pattern_based'] as Map<String, dynamic>? ?? {};
    final proactive = recommendations['proactive'] as Map<String, dynamic>? ?? {};

    suggestions['immediate_actions'] = _combineRecommendations([intentBased, cognitiveBased]);
    suggestions['optimization_opportunities'] = _combineRecommendations([patternBased, proactive]);
    suggestions['long_term_advice'] = proactive;

    return suggestions;
  }

  Map<String, dynamic> _combineRecommendations(List<Map<String, dynamic>> recommendations) {
    final combined = <String, dynamic>{};
    for (final rec in recommendations) {
      combined.addAll(rec);
    }
    return combined;
  }

  /// 构建相��历史上下文
  Map<String, dynamic> _buildRelevantHistoryContext(Map<String, dynamic> interactionHistory) {
    return {
      'conversation_pattern': _extractConversationPattern(interactionHistory),
      'topic_preferences': _extractTopicPreferences(interactionHistory),
      'problem_solving_approach': _extractProblemSolvingApproach(interactionHistory),
    };
  }

  String _extractConversationPattern(Map<String, dynamic> history) {
    final frequency = history['conversation_frequency'] as Map<String, dynamic>? ?? {};
    final engagementLevel = frequency['engagement_level']?.toString() ?? 'medium';
    return 'User has $engagementLevel engagement with regular conversations';
  }

  List<String> _extractTopicPreferences(Map<String, dynamic> history) {
    final evolution = history['topic_evolution'] as Map<String, dynamic>? ?? {};
    final recentTopics = evolution['recent_topics'] as List? ?? [];
    return recentTopics.map((topic) => topic.toString()).toList();
  }

  String _extractProblemSolvingApproach(Map<String, dynamic> history) {
    final problemSolving = history['problem_solving_history'] as Map<String, dynamic>? ?? {};
    return problemSolving['problem_solving_style']?.toString() ?? 'balanced';
  }

  /// 构建对话指导原则
  Map<String, dynamic> _buildConversationGuidelines(PersonalizedContext context) {
    final guidelines = <String, dynamic>{};

    // 基于当前状态的指导原则
    final currentState = context.currentSemanticState;
    final cognitiveState = currentState['cognitive_state'] as Map<String, dynamic>? ?? {};
    final loadLevel = cognitiveState['load_level']?.toString() ?? 'moderate';

    switch (loadLevel) {
      case 'low':
        guidelines['communication_style'] = 'detailed_and_comprehensive';
        guidelines['response_length'] = 'extended';
        break;
      case 'high':
        guidelines['communication_style'] = 'concise_and_focused';
        guidelines['response_length'] = 'brief';
        break;
      case 'overload':
        guidelines['communication_style'] = 'simple_and_supportive';
        guidelines['response_length'] = 'minimal';
        break;
      default:
        guidelines['communication_style'] = 'balanced';
        guidelines['response_length'] = 'moderate';
    }

    // 基于用户档案的指导原则
    final profile = context.longTermProfile;
    final interactionStyle = _extractInteractionStyle(profile);

    guidelines['interaction_approach'] = interactionStyle;
    guidelines['personalization_level'] = _calculatePersonalizationLevel(context);

    return guidelines;
  }

  /// 计算个性化水平
  String _calculatePersonalizationLevel(PersonalizedContext context) {
    int score = 0;

    // 基于档案信息的丰富程度
    final profile = context.longTermProfile;
    if (profile.isNotEmpty) score += 2;

    // 基于交互历史的丰富程度
    final history = context.interactionHistory;
    if (history.isNotEmpty) score += 2;

    // 基于当前状态的详细程度
    final currentState = context.currentSemanticState;
    if (currentState.isNotEmpty) score += 1;

    if (score >= 4) return 'high';
    if (score >= 2) return 'medium';
    return 'low';
  }

  /// 获取调试信息
  Map<String, dynamic> getDebugInfo() {
    return {
      'service_initialized': _initialized,
      'understanding_system_status': _understandingSystem.getMonitoringStatus(),
      'last_context_generation': DateTime.now().toIso8601String(),
    };
  }

  /// 释放资源
  void dispose() {
    _initialized = false;
    print('[PersonalizedUnderstandingService] 🔌 个性化理解服务已释放');
  }
}
