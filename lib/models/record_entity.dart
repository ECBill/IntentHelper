import 'package:objectbox/objectbox.dart';

@Entity()
class RecordEntity {
  int id;
  String? role;
  String? content;

  @Index()
  String? category;

  @HnswIndex(dimensions: 1536, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? vector;

  @Index()
  int? createdAt;

  static const String categoryDefault = 'Default';
  static const String categoryDialogue = 'Dialogue';
  static const String categoryMeeting = 'Meeting';

  RecordEntity({
    this.id = 0,
    this.role,
    this.content,
    this.category,
    this.vector,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory RecordEntity.fromJson(Map<String, dynamic> json) {
    return RecordEntity(
      id: json['id'] ?? 0,
      role: json['role'],
      content: json['content'],
      category: json['category'],
      vector: (json['vector'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      createdAt: json['createdAt'],
    );
  }
}
