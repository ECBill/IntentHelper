import 'dart:convert';
import 'package:objectbox/objectbox.dart';

// graph_models.dart

@Entity()
class Node {
  @Id()
  int obxId = 0;
  @Unique()
  String id;         // 通常用 name + type 的组合
  String name;
  String type;
  // attributes 不能直接存Map，需用 json 字符串存储
  String attributesJson;

  Node({
    this.obxId = 0,
    required this.id,
    required this.name,
    required this.type,
    Map<String, String> attributes = const {},
  }) : attributesJson = jsonEncode(attributes);

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
  }
}

@Entity()
class Edge {
  @Id()
  int obxId = 0;
  String source;     // Node.id
  String relation;
  String target;     // Node.id 或字面值
  String? context;   // optional: 对话上下文
  DateTime? timestamp;

  Edge({
    this.obxId = 0,
    required this.source,
    required this.relation,
    required this.target,
    this.context,
    this.timestamp,
  });
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

  Attribute({
    this.obxId = 0,
    required this.nodeId,
    required this.key,
    required this.value,
    this.timestamp,
    this.context,
  });
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
