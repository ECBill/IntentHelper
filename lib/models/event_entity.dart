import 'package:objectbox/objectbox.dart';

@Entity()
class EventEntity {
  @Id()
  int id = 0;

  String? title; // 事件标题
  String? description; // 事件详细描述
  String? location; // 地点
  String? participants; // 参与人员，用逗号分隔
  int? timestamp; // 事件时间戳
  String? category; // 事件类别 (Study, Life, Work, Entertainment)

  @Property(type: PropertyType.floatVector)
  List<double>? vector; // 事件描述的向量嵌入

  int? createdAt; // 创建时间
  int? summaryId; // 关联的摘要ID

  EventEntity({
    this.title,
    this.description,
    this.location,
    this.participants,
    this.timestamp,
    this.category,
    this.vector,
    this.createdAt,
    this.summaryId,
  });

  EventEntity.create({
    required this.title,
    required this.description,
    this.location,
    this.participants,
    required this.timestamp,
    required this.category,
    this.vector,
    this.summaryId,
  }) {
    createdAt = DateTime.now().millisecondsSinceEpoch;
  }

  factory EventEntity.fromJson(Map<String, dynamic> json) {
    final entity = EventEntity(
      title: json['title'],
      description: json['description'],
      location: json['location'],
      participants: json['participants'],
      timestamp: json['timestamp'],
      category: json['category'],
      vector: (json['vector'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      createdAt: json['createdAt'],
      summaryId: json['summaryId'],
    );
    if (json['id'] != null) {
      if (json['id'] is int) {
        entity.id = json['id'];
      } else if (json['id'] is String) {
        entity.id = int.tryParse(json['id']) ?? 0;
      }
    }
    return entity;
  }
}
