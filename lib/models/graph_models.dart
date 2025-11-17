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

  // 动态优先级分数相关字段
  DateTime? lastSeenTime;        // 最后被检索/访问的时间
  String activationHistoryJson;  // 激活历史记录（JSON格式：[{timestamp, similarity}, ...]）
  double cachedPriorityScore;    // 缓存的优先级分数
  
  // 聚类相关字段
  String? clusterId;             // 所属聚类ID (如果为null则未被聚类)
  String? mergedTo;              // 是否被合并到某个聚类摘要节点 (存储摘要节点ID)

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
    this.lastSeenTime,
    String? activationHistoryJson,
    this.cachedPriorityScore = 0.0,
    this.clusterId,
    this.mergedTo,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        embedding = embedding ?? <double>[],
        activationHistoryJson = activationHistoryJson ?? '[]';

  // 生成用于嵌入的文本内容
  // 改进版：覆盖更多事件属性字段，提高向量检索质量
  String getEmbeddingText() {
    final buffer = StringBuffer();

    // 1. 事件名称（最重要，权重最高）
    buffer.write(name);
    buffer.write(' ');
    buffer.write(name); // 重复一次增加权重

    // 2. 事件类型（重要语义标签）
    buffer.write(' 类型：');
    buffer.write(type);

    // 3. 添加描述
    if (description != null && description!.isNotEmpty) {
      buffer.write(' 描述：');
      buffer.write(description!);
    }

    // 4. 添加目的
    if (purpose != null && purpose!.isNotEmpty) {
      buffer.write(' 目的：');
      buffer.write(purpose!);
    }

    // 5. 添加结果
    if (result != null && result!.isNotEmpty) {
      buffer.write(' 结果：');
      buffer.write(result!);
    }

    // 6. 添加地点信息
    if (location != null && location!.isNotEmpty) {
      buffer.write(' 地点：');
      buffer.write(location!);
    }

    // 7. 添加时间信息（转换为可读格式）
    if (startTime != null) {
      final year = startTime!.year;
      final month = startTime!.month;
      final day = startTime!.day;
      final hour = startTime!.hour;
      
      // 添加日期信息
      buffer.write(' 时间：');
      buffer.write('$year年${month}月${day}日');
      
      // 添加时段信息（增强时间语义）
      if (hour >= 0 && hour < 6) {
        buffer.write('凌晨');
      } else if (hour >= 6 && hour < 9) {
        buffer.write('早上');
      } else if (hour >= 9 && hour < 12) {
        buffer.write('上午');
      } else if (hour >= 12 && hour < 13) {
        buffer.write('中午');
      } else if (hour >= 13 && hour < 18) {
        buffer.write('下午');
      } else if (hour >= 18 && hour < 22) {
        buffer.write('晚上');
      } else {
        buffer.write('深夜');
      }
    }

    // 8. 添加持续时间信息
    if (startTime != null && endTime != null) {
      final duration = endTime!.difference(startTime!);
      if (duration.inHours > 0) {
        buffer.write(' 持续${duration.inHours}小时');
      } else if (duration.inMinutes > 0) {
        buffer.write(' 持续${duration.inMinutes}分钟');
      }
    }

    return buffer.toString().trim();
  }

  // 获取激活历史列表
  List<Map<String, dynamic>> get activationHistory {
    try {
      final list = jsonDecode(activationHistoryJson);
      return List<Map<String, dynamic>>.from(list ?? []);
    } catch (_) {
      return [];
    }
  }

  // 设置激活历史列表
  set activationHistory(List<Map<String, dynamic>> history) {
    activationHistoryJson = jsonEncode(history);
  }

  // 添加激活记录
  void addActivation({required DateTime timestamp, double? similarity}) {
    final history = activationHistory;
    history.add({
      'timestamp': timestamp.millisecondsSinceEpoch,
      'similarity': similarity ?? 1.0,
    });
    // 保留最近100条记录，避免无限增长
    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }
    activationHistory = history;
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
    'lastSeenTime': lastSeenTime?.toIso8601String(),
    'activationHistoryJson': activationHistoryJson,
    'cachedPriorityScore': cachedPriorityScore,
    'clusterId': clusterId,
    'mergedTo': mergedTo,
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
    lastSeenTime: json['lastSeenTime'] != null ? DateTime.parse(json['lastSeenTime']) : null,
    activationHistoryJson: json['activationHistoryJson'] ?? '[]',
    cachedPriorityScore: (json['cachedPriorityScore'] as num?)?.toDouble() ?? 0.0,
    clusterId: json['clusterId'],
    mergedTo: json['mergedTo'],
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
  String relationType;  // 关系类型（时间顺序、因果关系、包含关系、revisit、progress_of等）
  String? description;  // 关系描述
  DateTime lastUpdated;

  // 关系类型常量
  static const String RELATION_TEMPORAL = 'temporal_sequence';  // 时间顺序
  static const String RELATION_CAUSAL = 'causal';               // 因果关系
  static const String RELATION_CONTAINS = 'contains';           // 包含关系
  static const String RELATION_REVISIT = 'revisit';             // 重访/回顾关系
  static const String RELATION_PROGRESS_OF = 'progress_of';     // 进展关系

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

// 聚类摘要节点模型 - 用于存储聚类后的抽象摘要
@Entity()
class ClusterNode {
  @Id()
  int obxId = 0;
  @Unique()
  String id;           // 聚类唯一标识
  String name;         // 聚类摘要标题（由LLM生成）
  String type;         // 聚类类型（始终为 "cluster"）
  String description;  // 聚类描述
  DateTime createdAt;  // 聚类创建时间
  DateTime lastUpdated; // 最后更新时间
  int memberCount;     // 成员数量
  String memberIdsJson; // 成员事件ID列表（JSON格式）
  
  @HnswIndex(dimensions: 384)
  @Property(type: PropertyType.floatVector)
  List<double> embedding; // 聚类中心向量（成员embedding的均值）
  
  double avgSimilarity; // 成员间平均相似度
  DateTime? earliestEventTime; // 最早事件时间
  DateTime? latestEventTime;   // 最晚事件时间
  
  // 两阶段聚类支持字段
  int level;           // 聚类层级：1=主题层，2=细分层
  String? parentClusterId; // 父聚类ID（仅level=2时有效）
  
  ClusterNode({
    this.obxId = 0,
    required this.id,
    required this.name,
    this.type = 'cluster',
    required this.description,
    DateTime? createdAt,
    DateTime? lastUpdated,
    this.memberCount = 0,
    String? memberIdsJson,
    List<double>? embedding,
    this.avgSimilarity = 0.0,
    this.earliestEventTime,
    this.latestEventTime,
    this.level = 2,          // 默认为细分层
    this.parentClusterId,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastUpdated = lastUpdated ?? DateTime.now(),
        memberIdsJson = memberIdsJson ?? '[]',
        embedding = embedding ?? <double>[];
  
  // 获取成员ID列表
  List<String> get memberIds {
    try {
      final list = jsonDecode(memberIdsJson);
      return List<String>.from(list ?? []);
    } catch (_) {
      return [];
    }
  }
  
  // 设置成员ID列表
  set memberIds(List<String> ids) {
    memberIdsJson = jsonEncode(ids);
    memberCount = ids.length;
  }
}

// 聚类元数据 - 记录聚类操作历史
@Entity()
class ClusteringMeta {
  @Id()
  int obxId = 0;
  DateTime clusteringTime;     // 聚类执行时间
  int totalEvents;             // 参与聚类的事件总数
  int clustersCreated;         // 创建的聚类数量
  int eventsClustered;         // 被聚类的事件数量
  int eventsUnclustered;       // 未被聚类的事件数量
  String algorithmUsed;        // 使用的聚类算法
  String parametersJson;       // 聚类参数（JSON格式）
  double avgClusterSize;       // 平均聚类大小
  double avgIntraClusterSimilarity; // 平均类内相似度
  
  ClusteringMeta({
    this.obxId = 0,
    DateTime? clusteringTime,
    this.totalEvents = 0,
    this.clustersCreated = 0,
    this.eventsClustered = 0,
    this.eventsUnclustered = 0,
    this.algorithmUsed = 'mini-batch-kmeans',
    String? parametersJson,
    this.avgClusterSize = 0.0,
    this.avgIntraClusterSimilarity = 0.0,
  })  : clusteringTime = clusteringTime ?? DateTime.now(),
        parametersJson = parametersJson ?? '{}';
  
  // 获取参数
  Map<String, dynamic> get parameters {
    try {
      final map = jsonDecode(parametersJson);
      return Map<String, dynamic>.from(map ?? {});
    } catch (_) {
      return {};
    }
  }
  
  // 设置参数
  set parameters(Map<String, dynamic> params) {
    parametersJson = jsonEncode(params);
  }
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
