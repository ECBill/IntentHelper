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

  // 🔥 新增：智能提醒相关字段
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
    // 🔥 新增字段的默认值
    this.isIntelligentReminder = false,
    this.originalText,
    this.reminderType = 'manual',
    this.ruleId,
    this.confidence,
  }) : statusIndex = status.index,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Status get status => Status.values[statusIndex];
  set status(Status status) => statusIndex = status.index;
}

enum Status { pending, completed, expired, all }
