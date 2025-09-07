/// 日志评估相关的数据模型

/// 对话日志条目
class ConversationLogEntry {
  final String id;
  final String role; // 'user' 或 'assistant'
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic> functionResults;
  final UserEvaluation? evaluation;

  ConversationLogEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    required this.functionResults,
    this.evaluation,
  });

  factory ConversationLogEntry.fromJson(Map<String, dynamic> json) {
    return ConversationLogEntry(
      id: json['id'],
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      functionResults: json['functionResults'] ?? {},
      evaluation: json['evaluation'] != null
          ? UserEvaluation.fromJson(json['evaluation'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'functionResults': functionResults,
      'evaluation': evaluation?.toJson(),
    };
  }
}

/// 用户评估
class UserEvaluation {
  final double? foaScore; // FoA准确性评分 (支持小数如0.75)
  final bool? todoCorrect; // Todo是否正确
  final int? recommendationRelevance; // 推荐相关性 (1-5)
  final int? cognitiveLoadReasonability; // 认知负载合理性 (1-5)
  final int? summaryRelevance; // 总结相关性 (1-5)
  final int? kgAccuracy; // 知识图谱准确性 (1-5)
  final DateTime evaluatedAt;
  final String? notes; // 备注

  UserEvaluation({
    this.foaScore,
    this.todoCorrect,
    this.recommendationRelevance,
    this.cognitiveLoadReasonability,
    this.summaryRelevance,
    this.kgAccuracy,
    required this.evaluatedAt,
    this.notes,
  });

  factory UserEvaluation.fromJson(Map<String, dynamic> json) {
    return UserEvaluation(
      foaScore: json['foaScore']?.toDouble(),
      todoCorrect: json['todoCorrect'],
      recommendationRelevance: json['recommendationRelevance'],
      cognitiveLoadReasonability: json['cognitiveLoadReasonability'],
      summaryRelevance: json['summaryRelevance'],
      kgAccuracy: json['kgAccuracy'],
      evaluatedAt: DateTime.parse(json['evaluatedAt']),
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'foaScore': foaScore,
      'todoCorrect': todoCorrect,
      'recommendationRelevance': recommendationRelevance,
      'cognitiveLoadReasonability': cognitiveLoadReasonability,
      'summaryRelevance': summaryRelevance,
      'kgAccuracy': kgAccuracy,
      'evaluatedAt': evaluatedAt.toIso8601String(),
      'notes': notes,
    };
  }
}

/// 评估指标统计
class EvaluationMetrics {
  final double todoAccuracy; // Todo准确率 (0-1)
  final double averageFoaScore; // FoA平均分
  final double averageRecommendationRelevance; // 推荐相关性平均分
  final double averageCognitiveLoadReasonability; // 认知负载合理性平均分
  final double averageSummaryRelevance; // 总结质量平均分
  final double averageKgAccuracy; // KG准确性平均分
  final int totalEvaluations; // 总评估数

  EvaluationMetrics({
    required this.todoAccuracy,
    required this.averageFoaScore,
    required this.averageRecommendationRelevance,
    required this.averageCognitiveLoadReasonability,
    required this.averageSummaryRelevance,
    required this.averageKgAccuracy,
    required this.totalEvaluations,
  });

  Map<String, dynamic> toJson() {
    return {
      'todoAccuracy': todoAccuracy,
      'averageFoaScore': averageFoaScore,
      'averageRecommendationRelevance': averageRecommendationRelevance,
      'averageCognitiveLoadReasonability': averageCognitiveLoadReasonability,
      'averageSummaryRelevance': averageSummaryRelevance,
      'averageKgAccuracy': averageKgAccuracy,
      'totalEvaluations': totalEvaluations,
    };
  }
}

/// FoA主题识别条目
class FoAEntry {
  final String id;
  final List<String> topics;
  final double confidence;
  final DateTime timestamp;
  final String relatedContent;
  final UserEvaluation? evaluation;

  FoAEntry({
    required this.id,
    required this.topics,
    required this.confidence,
    required this.timestamp,
    required this.relatedContent,
    this.evaluation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topics': topics,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'relatedContent': relatedContent,
      'evaluation': evaluation?.toJson(),
    };
  }
}

/// Todo提醒条目
class TodoEntry {
  final String id;
  final String task;
  final DateTime? deadline;
  final double confidence;
  final DateTime timestamp;
  final String relatedContent;
  final UserEvaluation? evaluation;

  TodoEntry({
    required this.id,
    required this.task,
    this.deadline,
    required this.confidence,
    required this.timestamp,
    required this.relatedContent,
    this.evaluation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task': task,
      'deadline': deadline?.toIso8601String(),
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'relatedContent': relatedContent,
      'evaluation': evaluation?.toJson(),
    };
  }
}

/// 智能推荐条目
class RecommendationEntry {
  final String id;
  final String content;
  final String source;
  final double relevance;
  final DateTime timestamp;
  final String relatedContent;
  final UserEvaluation? evaluation;

  RecommendationEntry({
    required this.id,
    required this.content,
    required this.source,
    required this.relevance,
    required this.timestamp,
    required this.relatedContent,
    this.evaluation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'source': source,
      'relevance': relevance,
      'timestamp': timestamp.toIso8601String(),
      'relatedContent': relatedContent,
      'evaluation': evaluation?.toJson(),
    };
  }
}

/// 总结条目
class SummaryEntry {
  final String id;
  final String subject;
  final String content;
  final DateTime timestamp;
  final String relatedContent;
  final UserEvaluation? evaluation;

  SummaryEntry({
    required this.id,
    required this.subject,
    required this.content,
    required this.timestamp,
    required this.relatedContent,
    this.evaluation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'relatedContent': relatedContent,
      'evaluation': evaluation?.toJson(),
    };
  }
}

/// 知识图谱条目
class KGEntry {
  final String id;
  final String nodeType;
  final String content;
  final Map<String, dynamic> properties;
  final DateTime timestamp;
  final String relatedContent;
  final UserEvaluation? evaluation;

  KGEntry({
    required this.id,
    required this.nodeType,
    required this.content,
    required this.properties,
    required this.timestamp,
    required this.relatedContent,
    this.evaluation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeType': nodeType,
      'content': content,
      'properties': properties,
      'timestamp': timestamp.toIso8601String(),
      'relatedContent': relatedContent,
      'evaluation': evaluation?.toJson(),
    };
  }
}

/// 认知负载条目
class CognitiveLoadEntry {
  final String id;
  final double value;
  final String level;
  final DateTime timestamp;
  final String relatedContent;
  final UserEvaluation? evaluation;

  CognitiveLoadEntry({
    required this.id,
    required this.value,
    required this.level,
    required this.timestamp,
    required this.relatedContent,
    this.evaluation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'value': value,
      'level': level,
      'timestamp': timestamp.toIso8601String(),
      'relatedContent': relatedContent,
      'evaluation': evaluation?.toJson(),
    };
  }
}
