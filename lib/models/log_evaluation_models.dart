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
  final int? foaScore; // FoA准确性评分 (1-5)
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
      foaScore: json['foaScore'],
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
  final int totalEvaluations; // 总评估数

  EvaluationMetrics({
    required this.todoAccuracy,
    required this.averageFoaScore,
    required this.averageRecommendationRelevance,
    required this.averageCognitiveLoadReasonability,
    required this.totalEvaluations,
  });

  factory EvaluationMetrics.fromJson(Map<String, dynamic> json) {
    return EvaluationMetrics(
      todoAccuracy: json['todoAccuracy'].toDouble(),
      averageFoaScore: json['averageFoaScore'].toDouble(),
      averageRecommendationRelevance: json['averageRecommendationRelevance'].toDouble(),
      averageCognitiveLoadReasonability: json['averageCognitiveLoadReasonability'].toDouble(),
      totalEvaluations: json['totalEvaluations'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'todoAccuracy': todoAccuracy,
      'averageFoaScore': averageFoaScore,
      'averageRecommendationRelevance': averageRecommendationRelevance,
      'averageCognitiveLoadReasonability': averageCognitiveLoadReasonability,
      'totalEvaluations': totalEvaluations,
    };
  }
}
