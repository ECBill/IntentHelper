import 'dart:convert';
import 'package:objectbox/objectbox.dart';

// graph_models.dart

@Entity()
class Node {
  @Id()
  int obxId = 0;
  @Unique()
  String id;         // 标准化ID：<name>_<type>
  String name;       // 实体名称
  String type;       // 实体类型
  String canonicalName; // 规范化名称（用于实体对齐）
  String attributesJson; // 属性JSON
  DateTime lastUpdated;  // 最后更新时间
  String? sourceContext; // 来源上下文
  String aliasesJson;    // 别名列表JSON（用于指代消解）

  Node({
    this.obxId = 0,
    required this.id,
    required this.name,
    required this.type,
    String? canonicalName,
    Map<String, String> attributes = const {},
    DateTime? lastUpdated,
    this.sourceContext,
    List<String> aliases = const [],
  }) : attributesJson = jsonEncode(attributes),
       lastUpdated = lastUpdated ?? DateTime.now(),
       canonicalName = canonicalName ?? name,
       aliasesJson = jsonEncode(aliases);

  Map<String, String> get attributes {
    try {
      final map = jsonDecode(attributesJson);
      return Map<String, String>.from(map ?? {});
    } catch (_) {
      return {};
    }
  }

  set attributes(Map<String, String> attrs) {
    attributesJson = jsonEncode(attrs);
    lastUpdated = DateTime.now();
  }

  List<String> get aliases {
    try {
      final list = jsonDecode(aliasesJson);
      return List<String>.from(list ?? []);
    } catch (_) {
      return [];
    }
  }

  set aliases(List<String> aliasesList) {
    aliasesJson = jsonEncode(aliasesList);
    lastUpdated = DateTime.now();
  }
}

@Entity()
class Edge {
  @Id()
  int obxId = 0;
  String source;     // 源节点ID
  String relation;   // 关系类型
  String target;     // 目标节点ID
  String? context;   // 上下文描述
  DateTime? timestamp; // 关系建立时间
  DateTime lastUpdated; // 最后更新时间
  String? sourceContext; // 来源上下文ID
  double confidence; // 关系置信度 (0.0-1.0)

  Edge({
    this.obxId = 0,
    required this.source,
    required this.relation,
    required this.target,
    this.context,
    this.timestamp,
    DateTime? lastUpdated,
    this.sourceContext,
    this.confidence = 1.0,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}

// 新增：事件节点模型 - 事件中心的图谱设计
@Entity()
class EventNode {
  @Id()
  int obxId = 0;
  @Unique()
  String id;           // 事件唯一标识
  String name;         // 事件名称
  String type;         // 事件类型（如：会议、购买、计划、经历等）
  DateTime? startTime; // 事件开始时间
  DateTime? endTime;   // 事件结束时间
  String? location;    // 事件地点
  String? purpose;     // 事件目的
  String? result;      // 事件结果
  String? description; // 事件描述
  DateTime lastUpdated; // 最后更新时间
  String? sourceContext; // 来源上下文ID

  @HnswIndex(dimensions: 384)
  @Property(type: PropertyType.floatVector)
  List<double> embedding;

  EventNode({
    this.obxId = 0,
    required this.id,
    required this.name,
    required this.type,
    this.startTime,
    this.endTime,
    this.location,
    this.purpose,
    this.result,
    this.description,
    DateTime? lastUpdated,
    this.sourceContext,
    List<double>? embedding,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        embedding = embedding ?? <double>[];

  // 生成用于嵌入的文本内容
  String getEmbeddingText() {
    final buffer = StringBuffer();

    // 事件名称
    buffer.write(name);

    // 添加描述
    if (description != null && description!.isNotEmpty) {
      buffer.write(' ');
      buffer.write(description!);
    }

    // 添加目的
    if (purpose != null && purpose!.isNotEmpty) {
      buffer.write(' 目的：');
      buffer.write(purpose!);
    }

    // 添加结果
    if (result != null && result!.isNotEmpty) {
      buffer.write(' 结果：');
      buffer.write(result!);
    }

    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() => {
    'obxId': obxId,
    'id': id,
    'name': name,
    'type': type,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'location': location,
    'purpose': purpose,
    'result': result,
    'description': description,
    'lastUpdated': lastUpdated.toIso8601String(),
    'sourceContext': sourceContext,
    'embedding': embedding,
  };

  factory EventNode.fromJson(Map<String, dynamic> json) => EventNode(
    obxId: json['obxId'] ?? 0,
    id: json['id'],
    name: json['name'],
    type: json['type'],
    startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    location: json['location'],
    purpose: json['purpose'],
    result: json['result'],
    description: json['description'],
    lastUpdated: json['lastUpdated'] != null ? DateTime.parse(json['lastUpdated']) : DateTime.now(),
    sourceContext: json['sourceContext'],
    embedding: (json['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList(),
  );
}

// 事件-实体关系模型
@Entity()
class EventEntityRelation {
  @Id()
  int obxId = 0;
  String eventId;    // 事件ID
  String entityId;   // 实体ID
  String role;       // 实体在事件中的角色（参与者、地点、工具等）
  String? description; // 角色描述
  DateTime lastUpdated;

  EventEntityRelation({
    this.obxId = 0,
    required this.eventId,
    required this.entityId,
    required this.role,
    this.description,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}

// 事件间关系模型
@Entity()
class EventRelation {
  @Id()
  int obxId = 0;
  String sourceEventId; // 源事件ID
  String targetEventId; // 目标事件ID
  String relationType;  // 关系类型（时间顺序、因果关系、包含关系等）
  String? description;  // 关系描述
  DateTime lastUpdated;

  EventRelation({
    this.obxId = 0,
    required this.sourceEventId,
    required this.targetEventId,
    required this.relationType,
    this.description,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}

// 实体对齐记录
@Entity()
class EntityAlignment {
  @Id()
  int obxId = 0;
  String canonicalId;   // 规范实体ID
  String aliasId;       // 别名实体ID
  String alignmentType; // 对齐类型（指代消解、同义词等）
  double confidence;    // 对齐置信度
  DateTime createdAt;
  String? sourceContext;

  EntityAlignment({
    this.obxId = 0,
    required this.canonicalId,
    required this.aliasId,
    required this.alignmentType,
    this.confidence = 1.0,
    DateTime? createdAt,
    this.sourceContext,
  }) : createdAt = createdAt ?? DateTime.now();
}

@Entity()
class Attribute {
  @Id()
  int obxId = 0;
  String nodeId;     // Node.id
  String key;
  String value;
  DateTime? timestamp;
  String? context;
  DateTime lastUpdated; // 新增：最后更新时间

  Attribute({
    this.obxId = 0,
    required this.nodeId,
    required this.key,
    required this.value,
    this.timestamp,
    this.context,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}

@Entity()
class Context {
  @Id()
  int obxId = 0;
  String cid; // 唯一标识
  String title;
  DateTime timestamp;
  String sourceText;

  Context({
    this.obxId = 0,
    required this.cid,
    required this.title,
    required this.timestamp,
    required this.sourceText,
  });
}

class NodeEntity {
  int id;
  String? label;
  Map<String, dynamic>? properties;
  int? createdAt;

  NodeEntity({
    this.id = 0,
    this.label,
    this.properties,
    this.createdAt,
  });

  factory NodeEntity.fromJson(Map<String, dynamic> json) {
    int idValue = 0;
    if (json['id'] is int) {
      idValue = json['id'];
    } else if (json['id'] is String) {
      idValue = int.tryParse(json['id']) ?? 0;
    }
    return NodeEntity(
      id: idValue,
      label: json['label'],
      properties: (json['properties'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)),
      createdAt: json['createdAt'],
    );
  }
}
