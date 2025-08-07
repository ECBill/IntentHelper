/// 类人理解系统的核心数据模型
/// 包含意图、主题、因果关系、语义记忆等结构定义

import 'package:uuid/uuid.dart';

/// 意图生命周期状态
enum IntentLifecycleState {
  forming,     // 形成中
  clarifying,  // 澄清中
  executing,   // 执行中
  paused,      // 暂停
  completed,   // 完成
  abandoned,   // 放弃
}

/// 意图对象 - 具有生命周期的用户意图
class Intent {
  final String id;
  String description;
  IntentLifecycleState state;
  String category; // 工作、生活、学习、娱乐等
  double confidence; // 置信度 0-1
  DateTime createdAt;
  DateTime lastUpdated;
  DateTime? completedAt;

  // 意图上下文
  List<String> triggerPhrases; // 触发短语
  List<String> relatedEntities; // 相关实体
  Map<String, dynamic> context; // 上下文信息

  // 生命周期轨迹
  List<IntentStateTransition> stateHistory;

  Intent({
    String? id,
    required this.description,
    this.state = IntentLifecycleState.forming,
    required this.category,
    this.confidence = 0.5,
    DateTime? createdAt,
    DateTime? lastUpdated,
    this.triggerPhrases = const [],
    this.relatedEntities = const [],
    this.context = const {},
    this.stateHistory = const [],
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       lastUpdated = lastUpdated ?? DateTime.now();

  void updateState(IntentLifecycleState newState, String reason) {
    final transition = IntentStateTransition(
      fromState: state,
      toState: newState,
      timestamp: DateTime.now(),
      reason: reason,
    );
    stateHistory = [...stateHistory, transition];
    state = newState;
    lastUpdated = DateTime.now();

    if (newState == IntentLifecycleState.completed ||
        newState == IntentLifecycleState.abandoned) {
      completedAt = DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'state': state.toString(),
      'category': category,
      'confidence': confidence,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'triggerPhrases': triggerPhrases,
      'relatedEntities': relatedEntities,
      'context': context,
      'stateHistory': stateHistory.map((h) => h.toJson()).toList(),
    };
  }
}

/// 意图状态转换记录
class IntentStateTransition {
  final IntentLifecycleState fromState;
  final IntentLifecycleState toState;
  final DateTime timestamp;
  final String reason;

  IntentStateTransition({
    required this.fromState,
    required this.toState,
    required this.timestamp,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return {
      'fromState': fromState.toString(),
      'toState': toState.toString(),
      'timestamp': timestamp.toIso8601String(),
      'reason': reason,
    };
  }
}

/// 对话主题状态
enum TopicState {
  active,    // 活跃
  background, // 背景
  dormant,   // 休眠
  closed,    // 关闭
}

/// 对话主题
class ConversationTopic {
  final String id;
  String name;
  String category; // 工作、生活、娱乐等
  TopicState state;
  double relevanceScore; // 当前相关性分数
  DateTime createdAt;
  DateTime lastMentioned;

  // 主题内容
  List<String> keywords; // 关键词
  List<String> entities; // 相关实体
  List<String> relatedIntentIds; // 关联意图ID
  Map<String, dynamic> context; // 主题上下文

  // 主题演进
  List<TopicEvolution> evolutionHistory;

  ConversationTopic({
    String? id,
    required this.name,
    required this.category,
    this.state = TopicState.active,
    this.relevanceScore = 1.0,
    DateTime? createdAt,
    DateTime? lastMentioned,
    this.keywords = const [],
    this.entities = const [],
    this.relatedIntentIds = const [],
    this.context = const {},
    this.evolutionHistory = const [],
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       lastMentioned = lastMentioned ?? DateTime.now();

  void updateRelevance(double newScore, String reason) {
    final evolution = TopicEvolution(
      timestamp: DateTime.now(),
      oldRelevance: relevanceScore,
      newRelevance: newScore,
      reason: reason,
    );
    evolutionHistory = [...evolutionHistory, evolution];
    relevanceScore = newScore;
    lastMentioned = DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'state': state.toString(),
      'relevanceScore': relevanceScore,
      'createdAt': createdAt.toIso8601String(),
      'lastMentioned': lastMentioned.toIso8601String(),
      'keywords': keywords,
      'entities': entities,
      'relatedIntentIds': relatedIntentIds,
      'context': context,
      'evolutionHistory': evolutionHistory.map((e) => e.toJson()).toList(),
    };
  }
}

/// 主题演进记录
class TopicEvolution {
  final DateTime timestamp;
  final double oldRelevance;
  final double newRelevance;
  final String reason;

  TopicEvolution({
    required this.timestamp,
    required this.oldRelevance,
    required this.newRelevance,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'oldRelevance': oldRelevance,
      'newRelevance': newRelevance,
      'reason': reason,
    };
  }
}

/// 因果关系类型
enum CausalRelationType {
  directCause,    // 直接因果
  indirectCause,  // 间接因果
  enabler,        // 使能条件
  inhibitor,      // 抑制条件
  correlation,    // 相关性
}

/// 因果关系
class CausalRelation {
  final String id;
  String cause; // 原因描述
  String effect; // 结果描述
  CausalRelationType type;
  double confidence; // 置信度
  DateTime extractedAt;

  // 上下文
  String sourceText; // 来源文本
  List<String> involvedEntities; // 涉及的实体
  Map<String, dynamic> context;

  CausalRelation({
    String? id,
    required this.cause,
    required this.effect,
    required this.type,
    this.confidence = 0.5,
    DateTime? extractedAt,
    required this.sourceText,
    this.involvedEntities = const [],
    this.context = const {},
  }) : id = id ?? const Uuid().v4(),
       extractedAt = extractedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cause': cause,
      'effect': effect,
      'type': type.toString(),
      'confidence': confidence,
      'extractedAt': extractedAt.toIso8601String(),
      'sourceText': sourceText,
      'involvedEntities': involvedEntities,
      'context': context,
    };
  }
}

/// 语义三元组
class SemanticTriple {
  final String id;
  String subject;   // 主语
  String predicate; // 谓词/关系
  String object;    // 宾语
  double confidence; // 置信度
  DateTime createdAt;

  // 元数据
  String sourceContext; // 来源上下文
  List<String> supportingEvidence; // 支持证据
  Map<String, dynamic> attributes; // 额外属性

  SemanticTriple({
    String? id,
    required this.subject,
    required this.predicate,
    required this.object,
    this.confidence = 0.5,
    DateTime? createdAt,
    required this.sourceContext,
    this.supportingEvidence = const [],
    this.attributes = const {},
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'predicate': predicate,
      'object': object,
      'confidence': confidence,
      'createdAt': createdAt.toIso8601String(),
      'sourceContext': sourceContext,
      'supportingEvidence': supportingEvidence,
      'attributes': attributes,
    };
  }
}

/// 认知负载级别
enum CognitiveLoadLevel {
  low,      // 低负载
  moderate, // 中等负载
  high,     // 高负载
  overload, // 过载
}

/// 认知负载评估
class CognitiveLoadAssessment {
  final DateTime timestamp;
  CognitiveLoadLevel level;
  double score; // 0-1 负载分数

  // 负载因子
  Map<String, double> factors; // 各类因子的贡献分数

  // 详细指标
  int activeIntentCount;     // 活跃意图数量
  int activeTopicCount;      // 活跃主题数量
  double emotionalIntensity; // 情绪强度
  double topicSwitchRate;    // 话题切换频率
  double complexityScore;    // 语言复杂度

  String recommendation; // 建议

  CognitiveLoadAssessment({
    DateTime? timestamp,
    required this.level,
    required this.score,
    required this.factors,
    required this.activeIntentCount,
    required this.activeTopicCount,
    required this.emotionalIntensity,
    required this.topicSwitchRate,
    required this.complexityScore,
    this.recommendation = '',
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.toString(),
      'score': score,
      'factors': factors,
      'activeIntentCount': activeIntentCount,
      'activeTopicCount': activeTopicCount,
      'emotionalIntensity': emotionalIntensity,
      'topicSwitchRate': topicSwitchRate,
      'complexityScore': complexityScore,
      'recommendation': recommendation,
    };
  }
}

/// 语义分析结果（从现有cache系统接收的数据结构）
class SemanticAnalysisInput {
  final List<String> entities;
  final String intent;
  final String emotion;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic> additionalContext;

  SemanticAnalysisInput({
    required this.entities,
    required this.intent,
    required this.emotion,
    required this.content,
    required this.timestamp,
    this.additionalContext = const {},
  });
}

/// 系统状态快照
class HumanUnderstandingSystemState {
  final DateTime timestamp;
  final List<Intent> activeIntents;
  final List<ConversationTopic> activeTopics;
  final List<CausalRelation> recentCausalChains;
  final List<SemanticTriple> recentTriples;
  final CognitiveLoadAssessment currentCognitiveLoad;
  final Map<String, dynamic> systemMetrics;

  HumanUnderstandingSystemState({
    DateTime? timestamp,
    required this.activeIntents,
    required this.activeTopics,
    required this.recentCausalChains,
    required this.recentTriples,
    required this.currentCognitiveLoad,
    this.systemMetrics = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'activeIntents': activeIntents.map((i) => i.toJson()).toList(),
      'activeTopics': activeTopics.map((t) => t.toJson()).toList(),
      'recentCausalChains': recentCausalChains.map((c) => c.toJson()).toList(),
      'recentTriples': recentTriples.map((t) => t.toJson()).toList(),
      'currentCognitiveLoad': currentCognitiveLoad.toJson(),
      'systemMetrics': systemMetrics,
    };
  }
}
