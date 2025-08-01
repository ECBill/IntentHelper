import 'dart:convert';
import 'package:app/models/graph_models.dart';
import 'package:app/models/record_entity.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/objectbox_service.dart';

class KnowledgeGraphService {
  static final KnowledgeGraphService _instance = KnowledgeGraphService._internal();
  factory KnowledgeGraphService() => _instance;
  KnowledgeGraphService._internal();

  // 指代消解映射表
  static const Map<String, List<String>> pronounMap = {
    '我': ['自己', '本人', '我自己'],
    '你': ['您', '你们'],
    '他': ['这位', '那位', '这个人', '那个人'],
    '她': ['这位女士', '那位女士', '这个女生', '那个女生'],
    '它': ['这个', '那个', '这件事', '那件事'],
  };

  // 1. 实体对齐与唯一标识机制
  static String generateEntityId(String name, String type) {
    final normalizedName = _normalizeEntityName(name);
    return '${normalizedName}_$type';
  }

  static String _normalizeEntityName(String name) {
    // 标准化实体名称，处理常见的指代消解
    String normalized = name.trim().toLowerCase();

    // 处理指代消解
    for (final entry in pronounMap.entries) {
      if (entry.value.contains(normalized)) {
        return entry.key;
      }
    }

    return normalized;
  }

  // 实体对齐：查找或创建规范实体
  static Future<String> alignEntity(String name, String type, String contextId) async {
    final objectBox = ObjectBoxService();
    final normalizedName = _normalizeEntityName(name);
    final candidateId = generateEntityId(normalizedName, type);

    // 查找现有实体
    final existingNode = objectBox.findNodeByNameType(normalizedName, type);
    if (existingNode != null) {
      // 更新别名列表
      final aliases = existingNode.aliases;
      if (!aliases.contains(name) && name != normalizedName) {
        aliases.add(name);
        existingNode.aliases = aliases;
        objectBox.updateNode(existingNode);
      }
      return existingNode.id;
    }

    // 检查是否有对齐记录
    final alignments = objectBox.queryEntityAlignments(aliasName: name);
    if (alignments.isNotEmpty) {
      return alignments.first.canonicalId;
    }

    return candidateId;
  }

  // 2. 从对话中提取事件和实体（事件中心设计）
  static Future<Map<String, dynamic>> extractEventsAndEntitiesFromText(
    String conversationText,
    {DateTime? conversationTime}
  ) async {
    final now = conversationTime ?? DateTime.now();
    final timeContext = "${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日";

    final eventExtractionPrompt = """
你是一个知识图谱构建助手。请从对话中提取事件和实体信息，采用事件中心的图谱设计。

输出格式为 JSON，包含以下部分：

1. events: 事件数组，每个事件结构如下：
{
  "name": "事件名称",
  "type": "事件类型（会议、购买、计划、经历、讨论等）",
  "start_time": "事件开始时间（可选，格式：YYYY-MM-DD HH:mm）",
  "end_time": "事件结束时间（可选）",
  "location": "事件地点（可选）",
  "purpose": "事件目的（可选）",
  "result": "事件结果（可选）",
  "description": "事件描述",
  "participants": ["参与者列表"],
  "tools_used": ["使用的工具或物品"],
  "related_locations": ["相关地点"]
}

2. entities: 实体数组，每个实体结构如下：
{
  "name": "实体名称",
  "type": "实体类型（人、物品、地点、概念等）",
  "attributes": {
    "属性名": "属性值"
  }
}

3. event_relations: 事件间关系数组：
{
  "source_event": "源事件名称",
  "target_event": "目标事件名称",
  "relation_type": "关系类型（时间顺序、因果关系、包含关系等）",
  "description": "关系描述"
}

请确保识别出对话中的所有重要事件，以及参与这些事件的人物、地点、工具等实体。当前对话发生时间：$timeContext

对话内容：
""";

    try {
      print('[KnowledgeGraphService] 🔍 开始提取事件和实体，对话长度: ${conversationText.length}');
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: eventExtractionPrompt);
      final response = await llm.createRequest(content: conversationText);

      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        throw FormatException('未找到合法的 JSON 对象');
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final decoded = jsonDecode(jsonStr);

      if (decoded is Map) {
        return {
          'events': decoded['events'] ?? [],
          'entities': decoded['entities'] ?? [],
          'event_relations': decoded['event_relations'] ?? [],
        };
      } else {
        throw FormatException('返回内容格式不正确');
      }
    } catch (e, st) {
      print('[KnowledgeGraphService] ❌ 事件提取错误: $e\n$st');
      return {'events': [], 'entities': [], 'event_relations': []};
    }
  }

  // 3. 图谱更新与演化机制
  static Future<void> processEventsFromConversation(
    String conversationText,
    {required String contextId, DateTime? conversationTime}
  ) async {
    try {
      final result = await extractEventsAndEntitiesFromText(
        conversationText,
        conversationTime: conversationTime
      );

      final events = result['events'] ?? [];
      final entities = result['entities'] ?? [];
      final eventRelations = result['event_relations'] ?? [];
      final objectBox = ObjectBoxService();
      final now = conversationTime ?? DateTime.now();

      print('[KnowledgeGraphService] 📊 提取结果: ${events.length}个事件, ${entities.length}个实体');

      // 1. 处理实体（实体对齐）
      final Map<String, String> entityIdMap = {};
      for (final entityData in entities) {
        if (entityData is Map) {
          final name = entityData['name']?.toString() ?? '';
          final type = entityData['type']?.toString() ?? '';
          final attributes = entityData['attributes'] is Map
            ? Map<String, String>.from(entityData['attributes'])
            : <String, String>{};

          if (name.isNotEmpty && type.isNotEmpty) {
            final entityId = await alignEntity(name, type, contextId);
            entityIdMap['${name}_$type'] = entityId;

            // 检查是否需要更新或创建实体
            final existingNode = objectBox.findNodeById(entityId);
            if (existingNode != null) {
              // 合并属性（时间戳策略）
              final existingAttrs = existingNode.attributes;
              bool hasChanges = false;

              for (final entry in attributes.entries) {
                if (!existingAttrs.containsKey(entry.key) ||
                    existingAttrs[entry.key] != entry.value) {
                  existingAttrs[entry.key] = entry.value;
                  hasChanges = true;
                }
              }

              if (hasChanges) {
                existingNode.attributes = existingAttrs;
                existingNode.lastUpdated = now;
                existingNode.sourceContext = contextId;
                objectBox.updateNode(existingNode);
              }
            } else {
              // 创建新实体
              final newNode = Node(
                id: entityId,
                name: name,
                type: type,
                canonicalName: _normalizeEntityName(name),
                attributes: attributes,
                lastUpdated: now,
                sourceContext: contextId,
                aliases: [name],
              );
              objectBox.insertNode(newNode);
            }
          }
        }
      }

      // 2. 处理事件（事件中心设计）
      final Map<String, String> eventIdMap = {};
      for (final eventData in events) {
        if (eventData is Map) {
          final name = eventData['name']?.toString() ?? '';
          final type = eventData['type']?.toString() ?? '';
          final description = eventData['description']?.toString();
          final location = eventData['location']?.toString();
          final purpose = eventData['purpose']?.toString();
          final result = eventData['result']?.toString();

          if (name.isNotEmpty && type.isNotEmpty) {
            final eventId = 'event_${name.replaceAll(' ', '_')}_${now.millisecondsSinceEpoch}';
            eventIdMap[name] = eventId;

            // 解析时间
            DateTime? startTime;
            DateTime? endTime;
            try {
              if (eventData['start_time'] != null) {
                startTime = DateTime.parse(eventData['start_time'].toString());
              }
              if (eventData['end_time'] != null) {
                endTime = DateTime.parse(eventData['end_time'].toString());
              }
            } catch (e) {
              print('[KnowledgeGraphService] 时间解析错误: $e');
            }

            // 创建事件节点
            final eventNode = EventNode(
              id: eventId,
              name: name,
              type: type,
              startTime: startTime,
              endTime: endTime,
              location: location,
              purpose: purpose,
              result: result,
              description: description,
              lastUpdated: now,
              sourceContext: contextId,
            );
            objectBox.insertEventNode(eventNode);

            // 3. 建立事件-实体关系
            // 参与者
            final participants = eventData['participants'] as List? ?? [];
            for (final participant in participants) {
              final participantStr = participant.toString();
              final participantId = await alignEntity(participantStr, '人', contextId);
              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: participantId,
                role: '参与者',
                lastUpdated: now,
              ));
            }

            // 使用的工具
            final toolsUsed = eventData['tools_used'] as List? ?? [];
            for (final tool in toolsUsed) {
              final toolStr = tool.toString();
              final toolId = await alignEntity(toolStr, '工具', contextId);
              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: toolId,
                role: '使用工具',
                lastUpdated: now,
              ));
            }

            // 相关地点
            final relatedLocations = eventData['related_locations'] as List? ?? [];
            for (final location in relatedLocations) {
              final locationStr = location.toString();
              final locationId = await alignEntity(locationStr, '地点', contextId);
              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: locationId,
                role: '发生地点',
                lastUpdated: now,
              ));
            }
          }
        }
      }

      // 4. 处理事件间关系
      for (final relationData in eventRelations) {
        if (relationData is Map) {
          final sourceEvent = relationData['source_event']?.toString() ?? '';
          final targetEvent = relationData['target_event']?.toString() ?? '';
          final relationType = relationData['relation_type']?.toString() ?? '';
          final description = relationData['description']?.toString();

          final sourceEventId = eventIdMap[sourceEvent];
          final targetEventId = eventIdMap[targetEvent];

          if (sourceEventId != null && targetEventId != null && relationType.isNotEmpty) {
            objectBox.insertEventRelation(EventRelation(
              sourceEventId: sourceEventId,
              targetEventId: targetEventId,
              relationType: relationType,
              description: description,
              lastUpdated: now,
            ));
          }
        }
      }

      print('[KnowledgeGraphService] ✅ 成功处理对话知识图谱');
    } catch (e) {
      print('[KnowledgeGraphService] ❌ 处理对话错误: $e');
    }
  }

  // 按时间分段处理对话
  static Future<void> processEventsFromConversationBySegments(
    List<RecordEntity> records,
    {int segmentMinutes = 10}
  ) async {
    if (records.isEmpty) return;

    records.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
    final List<List<RecordEntity>> segments = [];
    List<RecordEntity> currentSegment = [];
    int? lastTime;

    for (final record in records) {
      if (lastTime != null && record.createdAt != null &&
          record.createdAt! - lastTime > segmentMinutes * 60 * 1000) {
        if (currentSegment.isNotEmpty) segments.add(List.from(currentSegment));
        currentSegment.clear();
      }
      currentSegment.add(record);
      lastTime = record.createdAt;
    }
    if (currentSegment.isNotEmpty) segments.add(currentSegment);

    print('[KnowledgeGraphService] 📝 分段处理: ${segments.length}个时间段');

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final chatHistoryBuffer = StringBuffer();
      DateTime? segmentTime;

      for (final record in seg) {
        if (record.content != null && record.content!.trim().isNotEmpty) {
          final recordTime = DateTime.fromMillisecondsSinceEpoch(record.createdAt ?? 0);
          segmentTime ??= recordTime;
          chatHistoryBuffer.write('${record.role}: ${record.content}\n');
        }
      }

      final chatHistory = chatHistoryBuffer.toString();
      if (chatHistory.trim().isEmpty) continue;

      print('[KnowledgeGraphService] 🔄 处理第${i+1}段, 长度: ${chatHistory.length}');
      await processEventsFromConversation(
        chatHistory,
        contextId: 'segment_${seg.first.createdAt}',
        conversationTime: segmentTime,
      );
    }
  }

  // 图谱完整性校验器
  static Future<Map<String, List<String>>> validateGraphIntegrity() async {
    final objectBox = ObjectBoxService();
    final issues = <String, List<String>>{
      'orphaned_nodes': [],
      'duplicate_edges': [],
      'invalid_references': [],
      'outdated_entities': [],
    };

    try {
      // 检查孤立节点
      final allNodes = objectBox.queryNodes();
      final allEdges = objectBox.queryEdges();
      final referencedNodeIds = <String>{};

      for (final edge in allEdges) {
        referencedNodeIds.add(edge.source);
        referencedNodeIds.add(edge.target);
      }

      for (final node in allNodes) {
        if (!referencedNodeIds.contains(node.id)) {
          issues['orphaned_nodes']!.add(node.id);
        }
      }

      // 检查重复边
      final edgeSignatures = <String, List<String>>{};
      for (final edge in allEdges) {
        final signature = '${edge.source}_${edge.relation}_${edge.target}';
        edgeSignatures.putIfAbsent(signature, () => []).add('${edge.obxId}');
      }

      for (final entry in edgeSignatures.entries) {
        if (entry.value.length > 1) {
          issues['duplicate_edges']!.add(entry.key);
        }
      }

      // 检查无效引用
      final nodeIds = allNodes.map((n) => n.id).toSet();
      for (final edge in allEdges) {
        if (!nodeIds.contains(edge.source)) {
          issues['invalid_references']!.add('Edge ${edge.obxId}: invalid source ${edge.source}');
        }
        if (!nodeIds.contains(edge.target)) {
          issues['invalid_references']!.add('Edge ${edge.obxId}: invalid target ${edge.target}');
        }
      }

      print('[KnowledgeGraphService] 🔍 图谱完整性检查完成');
      return issues;
    } catch (e) {
      print('[KnowledgeGraphService] ❌ 图谱完整性检查错误: $e');
      return issues;
    }
  }

  // 查询相关事件
  static Future<List<EventNode>> getRelatedEvents(String entityId) async {
    try {
      final objectBox = ObjectBoxService();
      final relations = objectBox.queryEventEntityRelations(entityId: entityId);
      final eventIds = relations.map((r) => r.eventId).toSet();
      final events = <EventNode>[];

      for (final eventId in eventIds) {
        final event = objectBox.findEventNodeById(eventId);
        if (event != null) events.add(event);
      }

      return events;
    } catch (e) {
      print('[KnowledgeGraphService] ❌ 查询相关事件错误: $e');
      return [];
    }
  }

  // 根据关键词查找相关节点
  static Future<List<Node>> getRelatedNodesByKeywords(List<String> keywords) async {
    try {
      final objectBox = ObjectBoxService();
      final allNodes = objectBox.queryNodes();
      final Set<Node> result = {};

      for (final keyword in keywords) {
        for (final node in allNodes) {
          // 检查节点名称是否包含关键词
          if (node.name.contains(keyword)) {
            result.add(node);
            // 查找与该节点直接关联的节点
            final edges = objectBox.queryEdges(source: node.id);
            for (final edge in edges) {
              final related = allNodes.where((n) => n.id == edge.target).firstOrNull;
              if (related != null) result.add(related);
            }

            // 查找指向该节点的边
            final incomingEdges = objectBox.queryEdges(target: node.id);
            for (final edge in incomingEdges) {
              final related = allNodes.where((n) => n.id == edge.source).firstOrNull;
              if (related != null) result.add(related);
            }
          }

          // 检查节点属性是否包含关键词
          final attributes = node.attributes;
          for (final value in attributes.values) {
            if (value.contains(keyword)) {
              result.add(node);
              break;
            }
          }

          // 检查别名是否包含关键词
          final aliases = node.aliases;
          for (final alias in aliases) {
            if (alias.contains(keyword)) {
              result.add(node);
              break;
            }
          }
        }
      }

      return result.toList();
    } catch (e) {
      print('[KnowledgeGraphService] ❌ 根据关键词查找相关节点错误: $e');
      return [];
    }
  }
}
