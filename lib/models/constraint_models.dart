import 'package:app/models/graph_models.dart';

/// 检索上下文 - 包含当前用户关注的信息用于约束评估
class RetrievalContext {
  final List<String> focusTopics;          // 当前关注的主题
  final DateTime queryTime;                 // 查询时间点
  final String? targetLocation;             // 目标地点（如有）
  final List<String> targetEntityIds;       // 目标实体ID列表
  final Map<String, dynamic> additionalContext; // 额外上下文

  RetrievalContext({
    required this.focusTopics,
    DateTime? queryTime,
    this.targetLocation,
    this.targetEntityIds = const [],
    this.additionalContext = const {},
  }) : queryTime = queryTime ?? DateTime.now();

  RetrievalContext copyWith({
    List<String>? focusTopics,
    DateTime? queryTime,
    String? targetLocation,
    List<String>? targetEntityIds,
    Map<String, dynamic>? additionalContext,
  }) {
    return RetrievalContext(
      focusTopics: focusTopics ?? this.focusTopics,
      queryTime: queryTime ?? this.queryTime,
      targetLocation: targetLocation ?? this.targetLocation,
      targetEntityIds: targetEntityIds ?? this.targetEntityIds,
      additionalContext: additionalContext ?? this.additionalContext,
    );
  }
}

/// 带评分的事件节点
class ScoredNode {
  final EventNode node;
  double embeddingScore;                    // 向量相似度得分
  Map<String, double> constraintScores;     // 各约束的得分贡献
  double compositeScore;                     // 综合得分
  DateTime lastUpdated;                      // 最后更新时间
  String? matchedTopic;                      // 匹配的主题

  ScoredNode({
    required this.node,
    this.embeddingScore = 0.0,
    Map<String, double>? constraintScores,
    this.compositeScore = 0.0,
    DateTime? lastUpdated,
    this.matchedTopic,
  })  : constraintScores = constraintScores ?? {},
        lastUpdated = lastUpdated ?? DateTime.now();

  /// 计算综合得分
  /// embeddingWeight: 嵌入得分权重
  /// constraintWeight: 约束得分权重
  /// recencyWeight: 时效性权重
  /// staleness: 老化系数（小时）
  void computeCompositeScore({
    double embeddingWeight = 0.4,
    double constraintWeight = 0.5,
    double recencyWeight = 0.1,
    double stalenessHours = 24.0,
  }) {
    // 1. 基础嵌入得分
    final embeddingComponent = embeddingScore * embeddingWeight;

    // 2. 约束得分总和（归一化）
    final totalConstraintScore = constraintScores.values.fold(0.0, (sum, score) => sum + score);
    final constraintComponent = totalConstraintScore * constraintWeight;

    // 3. 时效性衰减（基于最后更新时间）
    final hoursSinceUpdate = DateTime.now().difference(lastUpdated).inHours.toDouble();
    final recencyFactor = hoursSinceUpdate > 0 
        ? 1.0 / (1.0 + hoursSinceUpdate / stalenessHours)
        : 1.0;
    final recencyComponent = recencyFactor * recencyWeight;

    compositeScore = embeddingComponent + constraintComponent + recencyComponent;
  }

  ScoredNode copyWith({
    EventNode? node,
    double? embeddingScore,
    Map<String, double>? constraintScores,
    double? compositeScore,
    DateTime? lastUpdated,
    String? matchedTopic,
  }) {
    return ScoredNode(
      node: node ?? this.node,
      embeddingScore: embeddingScore ?? this.embeddingScore,
      constraintScores: constraintScores ?? Map.from(this.constraintScores),
      compositeScore: compositeScore ?? this.compositeScore,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      matchedTopic: matchedTopic ?? this.matchedTopic,
    );
  }

  Map<String, dynamic> toJson() => {
    'nodeId': node.id,
    'nodeName': node.name,
    'embeddingScore': embeddingScore,
    'constraintScores': constraintScores,
    'compositeScore': compositeScore,
    'lastUpdated': lastUpdated.toIso8601String(),
    'matchedTopic': matchedTopic,
  };
}

/// 约束评估结果
class ConstraintResult {
  final bool passes;                // 是否通过约束（硬约束用）
  final double scoreContribution;   // 得分贡献（软约束用）
  final String? reason;             // 原因说明

  ConstraintResult({
    required this.passes,
    this.scoreContribution = 0.0,
    this.reason,
  });

  static ConstraintResult pass({double score = 0.0, String? reason}) {
    return ConstraintResult(passes: true, scoreContribution: score, reason: reason);
  }

  static ConstraintResult fail({String? reason}) {
    return ConstraintResult(passes: false, scoreContribution: 0.0, reason: reason);
  }
}

/// 约束基类
abstract class Constraint {
  final String name;
  final bool isHard;                // true=硬约束（必须满足），false=软约束（评分）
  final double weight;              // 约束权重（软约束用）

  Constraint({
    required this.name,
    this.isHard = false,
    this.weight = 1.0,
  });

  /// 评估事件节点是否满足约束
  ConstraintResult evaluate(EventNode node, RetrievalContext context);
}

/// 时间窗口硬约束 - 事件必须在指定时间范围内
class TimeWindowConstraint extends Constraint {
  final DateTime? startTime;
  final DateTime? endTime;

  TimeWindowConstraint({
    this.startTime,
    this.endTime,
    double weight = 1.0,
  }) : super(name: 'TimeWindow', isHard: true, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    // 如果节点没有时间信息，拒绝
    if (node.startTime == null) {
      return ConstraintResult.fail(reason: '节点无时间信息');
    }

    // 检查是否在时间窗口内
    if (startTime != null && node.startTime!.isBefore(startTime!)) {
      return ConstraintResult.fail(reason: '早于起始时间');
    }

    if (endTime != null && node.startTime!.isAfter(endTime!)) {
      return ConstraintResult.fail(reason: '晚于结束时间');
    }

    return ConstraintResult.pass(reason: '在时间窗口内');
  }
}

/// 时间接近度软约束 - 时间越接近得分越高
class TemporalProximityConstraint extends Constraint {
  final DateTime targetTime;
  final Duration maxDistance;       // 最大时间距离

  TemporalProximityConstraint({
    DateTime? targetTime,
    this.maxDistance = const Duration(days: 7),
    double weight = 1.0,
  })  : targetTime = targetTime ?? DateTime.now(),
        super(name: 'TemporalProximity', isHard: false, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    if (node.startTime == null) {
      return ConstraintResult.pass(score: 0.0, reason: '无时间信息');
    }

    final distance = (node.startTime!.difference(targetTime).inSeconds).abs();
    final maxDistanceSeconds = maxDistance.inSeconds;

    if (distance > maxDistanceSeconds) {
      return ConstraintResult.pass(score: 0.0, reason: '超出最大时间距离');
    }

    // 线性衰减
    final score = 1.0 - (distance / maxDistanceSeconds);
    return ConstraintResult.pass(
      score: score * weight,
      reason: '距离目标时间 ${(distance / 3600).toStringAsFixed(1)} 小时',
    );
  }
}

/// 地点匹配硬约束 - 必须在指定地点
class LocationMatchConstraint extends Constraint {
  final String requiredLocation;

  LocationMatchConstraint({
    required this.requiredLocation,
    double weight = 1.0,
  }) : super(name: 'LocationMatch', isHard: true, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    if (node.location == null || node.location!.isEmpty) {
      return ConstraintResult.fail(reason: '节点无地点信息');
    }

    // 简单字符串匹配（可扩展为层级地点匹配）
    if (node.location!.contains(requiredLocation) || 
        requiredLocation.contains(node.location!)) {
      return ConstraintResult.pass(reason: '地点匹配');
    }

    return ConstraintResult.fail(reason: '地点不匹配');
  }
}

/// 地点相似度软约束 - 地点部分匹配也有分
class LocationSimilarityConstraint extends Constraint {
  final String? targetLocation;

  LocationSimilarityConstraint({
    this.targetLocation,
    double weight = 1.0,
  }) : super(name: 'LocationSimilarity', isHard: false, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    final target = targetLocation ?? context.targetLocation;
    
    if (target == null || target.isEmpty) {
      return ConstraintResult.pass(score: 0.0, reason: '无目标地点');
    }

    if (node.location == null || node.location!.isEmpty) {
      return ConstraintResult.pass(score: 0.0, reason: '节点无地点信息');
    }

    // 计算地点相似度（简单实现：包含关系）
    double similarity = 0.0;
    if (node.location == target) {
      similarity = 1.0;
    } else if (node.location!.contains(target) || target.contains(node.location!)) {
      similarity = 0.7;
    } else {
      // 检查是否有共同子串
      final nodeTokens = node.location!.split(RegExp(r'[，。、\s]+')).where((t) => t.isNotEmpty).toList();
      final targetTokens = target.split(RegExp(r'[，。、\s]+')).where((t) => t.isNotEmpty).toList();
      final commonTokens = nodeTokens.where((t) => targetTokens.contains(t)).length;
      if (commonTokens > 0) {
        similarity = commonTokens / targetTokens.length.toDouble() * 0.5;
      }
    }

    return ConstraintResult.pass(
      score: similarity * weight,
      reason: '地点相似度: ${(similarity * 100).toInt()}%',
    );
  }
}

/// 实体存在硬约束 - 必须包含指定实体
class EntityPresenceConstraint extends Constraint {
  final List<String> requiredEntityIds;

  EntityPresenceConstraint({
    required this.requiredEntityIds,
    double weight = 1.0,
  }) : super(name: 'EntityPresence', isHard: true, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    // 注意：EventNode 没有直接的 relatedEntityIds 字段
    // 需要通过 EventEntityRelation 查询，这里先简化实现
    // TODO: 集成 EventEntityRelation 查询
    return ConstraintResult.pass(reason: '实体检查未实现（需集成关系查询）');
  }
}

/// 语义漂移惩罚 - 如果节点与当前主题相关性降低，降低分数
class SemanticDriftPenaltyConstraint extends Constraint {
  final double similarityThreshold;  // 相似度阈值

  SemanticDriftPenaltyConstraint({
    this.similarityThreshold = 0.3,
    double weight = 1.0,
  }) : super(name: 'SemanticDriftPenalty', isHard: false, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    // 这个约束在外层已通过 embedding 搜索保证了基本相似度
    // 这里可以额外检查是否有急剧下降
    // 简化实现：总是通过，得分为0（不额外惩罚）
    return ConstraintResult.pass(score: 0.0, reason: '语义漂移检查（待实现）');
  }
}

/// 新鲜度奖励 - 最近更新或访问的节点得分更高
class FreshnessBoostConstraint extends Constraint {
  final Duration recentWindow;

  FreshnessBoostConstraint({
    this.recentWindow = const Duration(hours: 24),
    double weight = 1.0,
  }) : super(name: 'FreshnessBoost', isHard: false, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    final lastSeen = node.lastSeenTime ?? node.lastUpdated;
    final hoursSince = DateTime.now().difference(lastSeen).inHours.toDouble();
    final windowHours = recentWindow.inHours.toDouble();

    if (hoursSince > windowHours) {
      return ConstraintResult.pass(score: 0.0, reason: '超出新鲜窗口');
    }

    final freshness = 1.0 - (hoursSince / windowHours);
    return ConstraintResult.pass(
      score: freshness * weight,
      reason: '新鲜度: ${(freshness * 100).toInt()}%',
    );
  }
}
