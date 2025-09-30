import 'package:objectbox/objectbox.dart';

@Entity()
class TodoEntity {
  int id;
  String? task;
  String? detail;

  @HnswIndex(dimensions: 1536, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? vector;

  @Property()
  int statusIndex;

  @Index()
  int? deadline;

  bool clock;

  @Index()
  int? createdAt;

  // 🔥 修复：智能提醒相关字段
  /// 是否为智能提醒生成的任务
  bool isIntelligentReminder;

  /// 原始用户输入文本（用于智能提醒）
  String? originalText;

  /// 提醒类型（manual, intelligent, natural_language）
  String? reminderType;

  /// 提醒触发的规则ID（用于智能提醒）
  String? ruleId;

  /// 置信度（用于自然语言提醒）
  double? confidence;

  TodoEntity({
    this.id = 0,
    this.task,
    this.detail,
    this.vector,
    this.deadline,
    this.clock = false,
    int? createdAt,
    Status status = Status.pending,
    // 🔥 修复：智能提醒字段的默认值
    this.isIntelligentReminder = false,
    this.originalText,
    this.reminderType,
    this.ruleId,
    this.confidence,
  }) : statusIndex = status.index,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  // 🔥 添加：status getter和setter
  Status get status => Status.values[statusIndex];
  set status(Status status) => statusIndex = status.index;

  factory TodoEntity.fromJson(Map<String, dynamic> json) {
    return TodoEntity(
      id: json['id'] ?? 0,
      task: json['task'],
      detail: json['detail'],
      vector: (json['vector'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      status: json['statusIndex'] != null ? Status.values[json['statusIndex']] : Status.pending,
      deadline: json['deadline'],
      clock: json['clock'] ?? false,
      createdAt: json['createdAt'],
      isIntelligentReminder: json['isIntelligentReminder'] ?? false,
      originalText: json['originalText'],
      reminderType: json['reminderType'],
      ruleId: json['ruleId'],
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

enum Status { pending, completed, expired, all, pending_reminder, reminded, intelligent_suggestion }
