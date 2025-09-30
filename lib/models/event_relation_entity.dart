import 'package:objectbox/objectbox.dart';

@Entity()
class EventRelationEntity {
  @Id()
  int id = 0;

  int? sourceEventId; // 源事件ID
  int? targetEventId; // 目标事件ID
  String? relationType; // 关系类型 (cause, temporal, similarity, conflict等)
  String? description; // 关系描述
  double? confidence; // 关系置信度 (0.0-1.0)

  int? createdAt; // 创建时间

  EventRelationEntity({
    this.sourceEventId,
    this.targetEventId,
    this.relationType,
    this.description,
    this.confidence,
    this.createdAt,
  });

  EventRelationEntity.create({
    required this.sourceEventId,
    required this.targetEventId,
    required this.relationType,
    this.description,
    this.confidence,
  }) {
    createdAt = DateTime.now().millisecondsSinceEpoch;
  }

  factory EventRelationEntity.fromJson(Map<String, dynamic> json) {
    final entity = EventRelationEntity(
      sourceEventId: json['sourceId'],
      targetEventId: json['targetId'],
      relationType: json['type'],
      description: json['description'],
      confidence: (json['confidence'] as num?)?.toDouble(),
      createdAt: json['createdAt'],
    );
    if (json['id'] != null) entity.id = json['id'];
    return entity;
  }
}
