/// 对话关注点状态机的数据模型
/// 用于追踪开放式长对话中用户关注点的漂移和演化

import 'package:uuid/uuid.dart';

/// 关注点类型
enum FocusType {
  event,   // 事件关注（具体发生的事情）
  topic,   // 主题关注（语义主题）
  entity,  // 实体关注（人、地点、物品等）
}

/// 关注点状态
enum FocusState {
  emerging,  // 新兴（刚刚出现）
  active,    // 活跃（当前正在讨论）
  background, // 背景（曾经讨论过，现在不是焦点）
  latent,    // 潜在（可能即将讨论）
  fading,    // 衰退（正在淡出）
}

/// 关注点对象
/// 代表用户在对话中关注的一个具体方面（事件/主题/实体）
class FocusPoint {
  final String id;
  FocusType type;
  String canonicalLabel; // 标准化标签
  Set<String> aliases;   // 别名集合
  
  DateTime firstSeen;
  DateTime lastUpdated;
  FocusState state;
  
  // 多维度分数
  double salienceScore;         // 显著性总分（综合分数）
  double recencyScore;          // 最近性分数
  double repetitionScore;       // 重复强化分数
  double emotionalScore;        // 情绪权重分数
  double causalConnectivityScore; // 因果连接度分数
  double driftPredictiveScore;  // 漂移预测分数
  
  // 上下文特征（用于约束匹配）
  Map<String, dynamic> constraintFeatures;
  
  // 关联信息
  List<String> linkedFocusIds;  // 关联的其他关注点ID
  int mentionCount;             // 提及次数
  List<DateTime> mentionTimestamps; // 提及时间戳列表
  
  // 元数据
  Map<String, dynamic> metadata; // 额外元数据

  FocusPoint({
    String? id,
    required this.type,
    required this.canonicalLabel,
    Set<String>? aliases,
    DateTime? firstSeen,
    DateTime? lastUpdated,
    this.state = FocusState.emerging,
    this.salienceScore = 0.5,
    this.recencyScore = 1.0,
    this.repetitionScore = 0.0,
    this.emotionalScore = 0.5,
    this.causalConnectivityScore = 0.0,
    this.driftPredictiveScore = 0.0,
    Map<String, dynamic>? constraintFeatures,
    List<String>? linkedFocusIds,
    this.mentionCount = 1,
    List<DateTime>? mentionTimestamps,
    Map<String, dynamic>? metadata,
  })  : id = id ?? const Uuid().v4(),
        aliases = aliases ?? {},
        firstSeen = firstSeen ?? DateTime.now(),
        lastUpdated = lastUpdated ?? DateTime.now(),
        constraintFeatures = constraintFeatures ?? {},
        linkedFocusIds = linkedFocusIds ?? [],
        mentionTimestamps = mentionTimestamps ?? [DateTime.now()],
        metadata = metadata ?? {};

  /// 记录新的提及
  void recordMention({DateTime? timestamp}) {
    final time = timestamp ?? DateTime.now();
    mentionCount++;
    mentionTimestamps.add(time);
    lastUpdated = time;
    
    // 限制时间戳列表大小，保留最近100个
    if (mentionTimestamps.length > 100) {
      mentionTimestamps = mentionTimestamps.sublist(mentionTimestamps.length - 100);
    }
  }

  /// 更新状态
  void updateState(FocusState newState) {
    state = newState;
    lastUpdated = DateTime.now();
  }

  /// 合并另一个关注点（处理别名/重复）
  void mergeWith(FocusPoint other) {
    // 合并别名
    aliases.addAll(other.aliases);
    aliases.add(other.canonicalLabel);
    
    // 合并提及次数和时间戳
    mentionCount += other.mentionCount;
    mentionTimestamps.addAll(other.mentionTimestamps);
    mentionTimestamps.sort();
    
    // 限制时间戳列表大小
    if (mentionTimestamps.length > 100) {
      mentionTimestamps = mentionTimestamps.sublist(mentionTimestamps.length - 100);
    }
    
    // 更新时间
    if (other.firstSeen.isBefore(firstSeen)) {
      firstSeen = other.firstSeen;
    }
    lastUpdated = DateTime.now();
    
    // 合并特征
    constraintFeatures.addAll(other.constraintFeatures);
    
    // 合并关联
    linkedFocusIds.addAll(other.linkedFocusIds);
    linkedFocusIds = linkedFocusIds.toSet().toList();
    
    // 合并元数据
    metadata.addAll(other.metadata);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'canonicalLabel': canonicalLabel,
      'aliases': aliases.toList(),
      'firstSeen': firstSeen.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'state': state.toString(),
      'salienceScore': salienceScore,
      'recencyScore': recencyScore,
      'repetitionScore': repetitionScore,
      'emotionalScore': emotionalScore,
      'causalConnectivityScore': causalConnectivityScore,
      'driftPredictiveScore': driftPredictiveScore,
      'constraintFeatures': constraintFeatures,
      'linkedFocusIds': linkedFocusIds,
      'mentionCount': mentionCount,
      'mentionTimestamps': mentionTimestamps.map((t) => t.toIso8601String()).toList(),
      'metadata': metadata,
    };
  }
}

/// 关注点转移记录
class FocusTransition {
  final DateTime timestamp;
  final String? fromFocusId;
  final String toFocusId;
  final double transitionStrength; // 转移强度 0-1
  final String reason;

  FocusTransition({
    required this.timestamp,
    this.fromFocusId,
    required this.toFocusId,
    this.transitionStrength = 0.5,
    this.reason = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'fromFocusId': fromFocusId,
      'toFocusId': toFocusId,
      'transitionStrength': transitionStrength,
      'reason': reason,
    };
  }
}

/// 关注点更新增量
class FocusUpdateDelta {
  final List<FocusPoint> added;
  final List<FocusPoint> updated;
  final List<String> removed;
  final List<FocusTransition> transitions;
  final DateTime timestamp;

  FocusUpdateDelta({
    required this.added,
    required this.updated,
    required this.removed,
    required this.transitions,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'added': added.map((f) => f.toJson()).toList(),
      'updated': updated.map((f) => f.toJson()).toList(),
      'removed': removed,
      'transitions': transitions.map((t) => t.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
