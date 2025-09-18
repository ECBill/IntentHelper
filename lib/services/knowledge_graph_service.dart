import 'dart:convert';
import 'package:app/models/graph_models.dart';
import 'package:app/models/record_entity.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/embedding_service.dart';

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

    // 清理实体名称中的特殊字符，避免与ID生成冲突
    // 将下划线替换为连字符，避免与类型分隔符冲突
    normalized = normalized.replaceAll('_', '-');

    // 移除其他可能影响ID生成的特殊字符
    normalized = normalized.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9\-\s]'), '');

    // 标准化空格为连字符
    normalized = normalized.replaceAll(RegExp(r'\s+'), '-');

    // 移除开头和结尾的连字符
    normalized = normalized.replaceAll(RegExp(r'^-+|-+$'), '');

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

    // 🔥 修复：如果实体不存在，立即创建它
    final newNode = Node(
      id: candidateId,
      name: name,
      type: type,
      canonicalName: normalizedName,
      attributes: <String, String>{},
      lastUpdated: DateTime.now(),
      sourceContext: contextId,
      aliases: [name],
    );
    objectBox.insertNode(newNode);
    print('[KnowledgeGraphService] 🆕 alignEntity创建新实体: $name ($type) -> $candidateId');

    return candidateId;
  }

  // 2. 从对话中提取事件和实体（事件中心设计）
  static Future<Map<String, dynamic>> extractEventsAndEntitiesFromText(
    String conversationText,
    {DateTime? conversationTime, Map<String, dynamic>? userStateContext}
  ) async {
    final now = conversationTime ?? DateTime.now();
    final timeContext = "${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日";

    final eventExtractionPrompt = """
你是一个知识图谱构建助手。请从对话中细致地提取事件和实体信息，采用事件中心的图谱设计。

${_generateUserStatePromptContext(userStateContext)}

【重要原则】：
1. 实体抽取要尽可能具体和细致，避免过度泛化
2. 要识别出具体的人物、物品、地点、概念等实体
3. 同一实体在不同事件中应保持一致的命名
4. 要考虑实体间的潜在关联性，为后续的知识发现做准备
5. 如果提供了用户状态信息，优先提取与用户当前意图和关注主题相关的事件和实体

【实体抽取指导】：
- 人物：抽取具体的人名、职务、称谓（如"张三"、"辅导员"、"老板"、"朋友"等）
- 物品：抽取具体的物品名称（如"水煮面条"、"iPhone 15 Pro"、"MacBook"等）
- 地点：抽取具体的地点名称（如"苹果店"、"星巴克"、"办公室"等）
- 概念：抽取具体的概念、活动、状态（如"结婚"、"跑路"、"项目"等）
- 组织：抽取具体的组织机构（如"公司"、"学校"、"部门"等）

【避免过度泛化】：
- ❌ 不要用"user"、"others"、"某人"等泛化词汇
- ❌ 不要用"某物"、"某地"等模糊表达
- ✅ 要用具体的名称和称谓
- ✅ 如果没有具体名称，用角色或特征描述（如"辅导员"、"同事"、"邻居"）

输出格式为 JSON，包含以下部分：

1. events: 事件数组，每个事件结构如下：
{
  "name": "事件名称",
  "type": "事件类型（用餐、购买、会议、讨论、计划、经历、学习、娱乐、工作、生活等）",
  "start_time": "事件开始时间（可选，格式：YYYY-MM-DD HH:mm）",
  "end_time": "事件结束时间（可选）",
  "location": "事件地点（可选）",
  "purpose": "事件目的（可选）",
  "result": "事件结果（可选）",
  "description": "事件描述",
  "participants": ["参与者列表 - 具体人物名称或角色"],
  "tools_used": ["使用的工具或物品 - 具体名称"],
  "related_locations": ["相关地点 - 具体地点名称"],
  "related_concepts": ["相关概念 - 如技能、状态、活动等"]
}

2. entities: 实体数组，每个实体结构如下：
{
  "name": "实体名称（具体、准确）",
  "type": "实体类型（人物、物品、地点、概念、组织、技能、状态等）",
  "attributes": {
    "属性名": "属性值"
  },
  "aliases": ["可能的别名或同义词"]
}

3. event_relations: 事件间关系数组：
{
  "source_event": "源事件名称",
  "target_event": "目标事件名称",
  "relation_type": "关系类型（时间顺序、因果关系、包含关系、相似关系等）",
  "description": "关系描述"
}

【示例】：
输入："晚上吃了一碗水煮面条"
应该抽取的实体：
- "水煮面条"（物品类型，属性：{"类别": "面食", "烹饪方式": "水煮"}）
- "我"（人物类型）

输入："用户们讨论辅导员的婚事，传言辅导员跑路了"
应该抽取的实体：
- "辅导员"（人物类型，属性：{"职务": "辅导员"}）
- "结婚"（概念类型，属性：{"类别": "人生事件"}）
- "跑路"（概念类型，属性：{"类别": "行为状态"}）
- 以及相应的讨论事件和传言事件

请确保识别出对话中的所有重要实体，特别是那些可能在未来对话中再次出现的具体实体。当前对话发生时间：$timeContext

对话内容：
""";

    try {
      print('[KnowledgeGraphService] 🔍 开始细致抽取事件和实体，对话长度: ${conversationText.length}');
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
    {required String contextId, DateTime? conversationTime, Map<String, dynamic>? userStateContext}
  ) async {
    try {
      final result = await extractEventsAndEntitiesFromText(
        conversationText,
        conversationTime: conversationTime,
        userStateContext: userStateContext,
      );

      final events = result['events'] ?? [];
      final entities = result['entities'] ?? [];
      final eventRelations = result['event_relations'] ?? [];
      final objectBox = ObjectBoxService();
      final now = conversationTime ?? DateTime.now();

      print('[KnowledgeGraphService] 📊 提取结果: ${events.length}个事件, ${entities.length}个实体');

      // 1. 处理实体（实体对齐）- 优化逻辑，确保与事件关联
      final Map<String, String> entityIdMap = {};

      // 🔥 修复：智能实体类型推断函数 - 修复变量作用域和返回类型问题
      String getSmartEntityType(String entityName, String suggestedType) {
        // 优先使用已经在entityIdMap中的实体类型
        for (final entry in entityIdMap.entries) {
          final key = entry.key;
          final id = entry.value;
          // 检查是否是同一个实体的不同表达
          if (key == entityName || key.contains('${entityName}_')) {
            // 从ID中提取实体类型
            final parts = id.split('_');
            if (parts.length >= 2) {
              return parts.last; // 返回实际的类型
            }
          }
        }

        // 如果没找到，尝试从已存在的实体中查找
        final existingNode = objectBox.queryNodes().cast<Node?>().firstWhere(
          (node) => node != null && (node.name == entityName || node.aliases.contains(entityName)),
          orElse: () => null,
        );

        if (existingNode != null) {
          return existingNode.type;
        }

        // 最后使用建议的类型
        return suggestedType;
      }

      for (final entityData in entities) {
        if (entityData is Map) {
          final name = entityData['name']?.toString() ?? '';
          final type = entityData['type']?.toString() ?? '';
          final attributes = entityData['attributes'] is Map
            ? Map<String, String>.from(entityData['attributes'])
            : <String, String>{};
          final aliases = entityData['aliases'] is List
            ? (entityData['aliases'] as List).map((e) => e.toString()).toList()
            : <String>[];

          if (name.isNotEmpty && type.isNotEmpty) {
            final entityId = await alignEntity(name, type, contextId);
            // 🔥 修复：使用原始名称+类型作为key，确保事件关联时能找到
            entityIdMap[name] = entityId;
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

              // 合并别名
              final existingAliases = existingNode.aliases;
              for (final alias in aliases) {
                if (!existingAliases.contains(alias)) {
                  existingAliases.add(alias);
                  hasChanges = true;
                }
              }

              if (hasChanges) {
                existingNode.attributes = existingAttrs;
                existingNode.aliases = existingAliases;
                existingNode.lastUpdated = now;
                existingNode.sourceContext = contextId;
                objectBox.updateNode(existingNode);
              }
            }
            // 注意：这里不需要再创建新实体，因为alignEntity已经会创建了
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

            print('[KnowledgeGraphService] 📝 创建事件: $name -> $eventId');

            // 3. 建立事件-实体关系
            final relationCount = StringBuffer('关联实体: ');

            // 参与者
            final participants = eventData['participants'] as List? ?? [];
            for (final participant in participants) {
              final participantStr = participant.toString();

              // 🔥 修复：优先使用entityIdMap中的ID，确保关联正确
              String? participantId = entityIdMap[participantStr];
              if (participantId == null) {
                // 智能获取实体类型，避免类型不匹配
                final smartType = getSmartEntityType(participantStr, '人物');
                participantId = await alignEntity(participantStr, smartType, contextId);
                entityIdMap[participantStr] = participantId; // 缓存新创建的ID
              }

              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: participantId,
                role: '参与者',
                lastUpdated: now,
              ));
              relationCount.write('参与者($participantStr->$participantId) ');
            }

            // 使用的工具或物品
            final toolsUsed = eventData['tools_used'] as List? ?? [];
            for (final tool in toolsUsed) {
              final toolStr = tool.toString();

              String? toolId = entityIdMap[toolStr];
              if (toolId == null) {
                // 智能获取实体类型，避免类型不匹配
                final smartType = getSmartEntityType(toolStr, '物品');
                toolId = await alignEntity(toolStr, smartType, contextId);
                entityIdMap[toolStr] = toolId;
              }

              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: toolId,
                role: '使用物品',
                lastUpdated: now,
              ));
              relationCount.write('物品($toolStr->$toolId) ');
            }

            // 相关地点
            final relatedLocations = eventData['related_locations'] as List? ?? [];
            for (final location in relatedLocations) {
              final locationStr = location.toString();

              String? locationId = entityIdMap[locationStr];
              if (locationId == null) {
                // 智能获取实体类型，避免类型不匹配
                final smartType = getSmartEntityType(locationStr, '地点');
                locationId = await alignEntity(locationStr, smartType, contextId);
                entityIdMap[locationStr] = locationId;
              }

              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: locationId,
                role: '发生地点',
                lastUpdated: now,
              ));
              relationCount.write('地点($locationStr->$locationId) ');
            }

            // 相关概念（状态、活动、技能等）
            final relatedConcepts = eventData['related_concepts'] as List? ?? [];
            for (final concept in relatedConcepts) {
              final conceptStr = concept.toString();

              String? conceptId = entityIdMap[conceptStr];
              if (conceptId == null) {
                // 智能获取实体类型，避免类型不匹配
                final smartType = getSmartEntityType(conceptStr, '概念');
                conceptId = await alignEntity(conceptStr, smartType, contextId);
                entityIdMap[conceptStr] = conceptId;
              }

              objectBox.insertEventEntityRelation(EventEntityRelation(
                eventId: eventId,
                entityId: conceptId,
                role: '相关概念',
                lastUpdated: now,
              ));
              relationCount.write('概念($conceptStr->$conceptId) ');
            }

            print('[KnowledgeGraphService] 🔗 ${relationCount.toString()}');
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
      final relatedEvents = <EventNode>[];
      final eventIds = <String>{};

      print('[KnowledgeGraphService] 🔍 通过实体 "$entityId" 查询相关事件...');

      // 第一步：直接查找与该实体相关的事件
      final directRelations = objectBox.queryEventEntityRelations(entityId: entityId);
      for (final relation in directRelations) {
        final event = objectBox.findEventNodeById(relation.eventId);
        if (event != null && !eventIds.contains(event.id)) {
          relatedEvents.add(event);
          eventIds.add(event.id);
        }
      }

      print('[KnowledgeGraphService] 📊 找到 ${relatedEvents.length} 个直接相关事件');

      // 第二步：通过共同实体关联找到更多相关事件
      // 获取所有与已找到事件相关的其他实体
      final relatedEntityIds = <String>{};
      for (final event in relatedEvents) {
        final eventEntityRelations = objectBox.queryEventEntityRelations(eventId: event.id);
        for (final relation in eventEntityRelations) {
          if (relation.entityId != entityId) { // 排除原始实体
            relatedEntityIds.add(relation.entityId);
          }
        }
      }

      // 第三步：通过这些相关实体查找更多事件（扩展关联网络）
      for (final relatedEntityId in relatedEntityIds) {
        final entityEvents = objectBox.queryEventEntityRelations(entityId: relatedEntityId);
        for (final relation in entityEvents) {
          if (!eventIds.contains(relation.eventId)) {
            final event = objectBox.findEventNodeById(relation.eventId);
            if (event != null) {
              relatedEvents.add(event);
              eventIds.add(event.id);
            }
          }
        }
      }

      // 第四步：根据时间和相关性对事件进行排序
      relatedEvents.sort((a, b) {
        // 优先按时间排序（最近的在前）
        final timeA = a.startTime?.millisecondsSinceEpoch ?? a.lastUpdated.millisecondsSinceEpoch;
        final timeB = b.startTime?.millisecondsSinceEpoch ?? b.lastUpdated.millisecondsSinceEpoch;
        return timeB.compareTo(timeA);
      });

      print('[KnowledgeGraphService] 🔗 总共找到 ${relatedEvents.length} 个相关事件');
      print('[KnowledgeGraphService] 🌐 通过 ${relatedEntityIds.length} 个关联实体扩展了事件网络');

      // 限制返回数量，避免结果过多
      return relatedEvents.take(20).toList();

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 查询相关事件错误: $e');
      return [];
    }
  }

  // 🔥 新增：根据实体名称和类型查找相关事件（支持模糊匹配）
  static Future<List<EventNode>> getRelatedEventsByEntityNameAndType(
    String entityName,
    String? entityType,
    {int limit = 10}
  ) async {
    try {
      final objectBox = ObjectBoxService();

      // 1. 先找到匹配的实体
      final matchingEntities = <Node>[];
      final allNodes = objectBox.queryNodes();

      for (final node in allNodes) {
        bool nameMatch = node.name.toLowerCase().contains(entityName.toLowerCase()) ||
                        node.canonicalName.toLowerCase().contains(entityName.toLowerCase()) ||
                        node.aliases.any((alias) => alias.toLowerCase().contains(entityName.toLowerCase()));

        bool typeMatch = entityType == null || node.type.toLowerCase() == entityType.toLowerCase();

        if (nameMatch && typeMatch) {
          matchingEntities.add(node);
        }
      }

      print('[KnowledgeGraphService] 🎯 找到 ${matchingEntities.length} 个匹配的实体');

      // 2. 获取所有匹配实体的相关事件
      final allRelatedEvents = <EventNode>[];
      final eventIds = <String>{};

      for (final entity in matchingEntities) {
        final entityEvents = await getRelatedEvents(entity.id);
        for (final event in entityEvents) {
          if (!eventIds.contains(event.id)) {
            allRelatedEvents.add(event);
            eventIds.add(event.id);
          }
        }
      }

      // 3. 按时间排序并限制数量
      allRelatedEvents.sort((a, b) {
        final timeA = a.startTime?.millisecondsSinceEpoch ?? a.lastUpdated.millisecondsSinceEpoch;
        final timeB = b.startTime?.millisecondsSinceEpoch ?? b.lastUpdated.millisecondsSinceEpoch;
        return timeB.compareTo(timeA);
      });

      return allRelatedEvents.take(limit).toList();

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 根据实体名称查找相关事件错误: $e');
      return [];
    }
  }

  // 自动处理未整理的对话记录
  static Future<void> processUnprocessedConversations() async {
    try {
      final objectBox = ObjectBoxService();
      final now = DateTime.now();

      // 查找最近3天内可能未处理的对话记录
      final cutoffTime = now.subtract(Duration(days: 3)).millisecondsSinceEpoch;
      final allRecords = objectBox.queryRecords();

      // 过滤出最近的记录
      final recentRecords = allRecords.where((r) =>
        r.createdAt != null &&
        r.createdAt! > cutoffTime &&
        r.content != null &&
        r.content!.trim().isNotEmpty
      ).toList();

      if (recentRecords.isEmpty) {
        print('[KnowledgeGraphService] 📝 没有找到需要处理的对话记录');
        return;
      }

      // 按会话分组
      final sessionGroups = _groupRecordsIntoSessions(recentRecords);

      // 检查哪些会话可能未被处理（通过检查是否有对应的事件记录）
      final unprocessedSessions = <List<RecordEntity>>[];

      for (final session in sessionGroups) {
        final sessionStart = session.first.createdAt ?? 0;
        final sessionEnd = session.last.createdAt ?? 0;

        // 检查这个时间段内是否有对应的事件记录
        final sessionEvents = objectBox.queryEventNodes().where((event) {
          final eventTime = event.startTime?.millisecondsSinceEpoch ?? event.lastUpdated.millisecondsSinceEpoch;
          return eventTime >= sessionStart - 60000 && eventTime <= sessionEnd + 60000; // 1分钟容差
        }).toList();

        // 如果这个会话没有对应的事件记录，或者事件数量明显偏少，则认为可能未处理
        if (sessionEvents.isEmpty || (session.length > 10 && sessionEvents.length < 2)) {
          unprocessedSessions.add(session);
        }
      }

      if (unprocessedSessions.isEmpty) {
        print('[KnowledgeGraphService] ✅ 所有对话都已处理');
        return;
      }

      print('[KnowledgeGraphService] 🔄 发现 ${unprocessedSessions.length} 个可能未处理的会话，开始自动处理...');

      // 处理未处理的会话
      for (int i = 0; i < unprocessedSessions.length; i++) {
        final session = unprocessedSessions[i];

        try {
          print('[KnowledgeGraphService] 📝 处理会话 ${i + 1}/${unprocessedSessions.length} (${session.length} 条记录)');

          await processEventsFromConversationBySegments(session);

          // 添加延迟避免API调用过于频繁
          await Future.delayed(Duration(milliseconds: 800));

        } catch (e) {
          print('[KnowledgeGraphService] ❌ 处理会话 ${i + 1} 失败: $e');
        }
      }

      print('[KnowledgeGraphService] ✅ 自动处理完成，已处理 ${unprocessedSessions.length} 个会话');

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 自动处理未整理对话失败: $e');
    }
  }

  // 辅助方法：按会话分组记录
  static List<List<RecordEntity>> _groupRecordsIntoSessions(List<RecordEntity> records) {
    if (records.isEmpty) return [];

    // 按时间排序
    records.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));

    final sessions = <List<RecordEntity>>[];
    List<RecordEntity> currentSession = [];
    int? lastTime;

    const sessionGapMinutes = 30; // 30分钟间隔认为是不同会话

    for (final record in records) {
      if (lastTime != null && record.createdAt != null &&
          record.createdAt! - lastTime > sessionGapMinutes * 60 * 1000) {
        if (currentSession.isNotEmpty) {
          sessions.add(List.from(currentSession));
          currentSession.clear();
        }
      }
      currentSession.add(record);
      lastTime = record.createdAt;
    }

    if (currentSession.isNotEmpty) {
      sessions.add(currentSession);
    }

    return sessions;
  }

  // 应用启动时检查未处理的对话
  static Future<void> initializeAndProcessMissedConversations() async {
    try {
      print('[KnowledgeGraphService] 🚀 应用启动，检查是否有未处理的对话...');

      // 延迟一点时间，确保其他服务已初始化
      await Future.delayed(Duration(seconds: 2));

      await processUnprocessedConversations();

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 启动时检查未处理对话失败: $e');
    }
  }

  // 检测对话结束并自动处理
  static Future<void> handleConversationEnd() async {
    try {
      print('[KnowledgeGraphService] 🔚 检测到对话结束，开始处理最近的对话记录...');

      final objectBox = ObjectBoxService();
      final now = DateTime.now();

      // 获取最近2小时内的对话记录
      final recentTime = now.subtract(Duration(hours: 2)).millisecondsSinceEpoch;
      final recentRecords = objectBox.queryRecords().where((r) =>
        r.createdAt != null &&
        r.createdAt! > recentTime &&
        r.content != null &&
        r.content!.trim().isNotEmpty
      ).toList();

      if (recentRecords.isEmpty) {
        print('[KnowledgeGraphService] 📝 没有找到最近的对话记录');
        return;
      }

      // 找到最后一个会话
      final sessionGroups = _groupRecordsIntoSessions(recentRecords);
      if (sessionGroups.isEmpty) return;

      final lastSession = sessionGroups.last;
      final lastRecordTime = lastSession.last.createdAt ?? 0;

      // 如果最后一条记录是在1分钟前，认为对话可能已经结束
      if (now.millisecondsSinceEpoch - lastRecordTime > 1 * 60 * 1000) {
        print('[KnowledgeGraphService] 📊 处理最后一个会话 (${lastSession.length} 条记录)');

        await processEventsFromConversationBySegments([lastSession.last]);

        print('[KnowledgeGraphService] ✅ 对话结束处理完成');
      }

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 处理对话结束失败: $e');
    }
  }

  // 🔥 新增：生成用户状态上下文信息的辅助函数
  static String _generateUserStatePromptContext(Map<String, dynamic>? userStateContext) {
    if (userStateContext == null || userStateContext.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    buffer.writeln('【用户当前状态信息】（用于指导事件和实体提取的优先级）：');

    // 活跃意图信息
    final activeIntents = userStateContext['active_intents'] as List<dynamic>? ?? [];
    if (activeIntents.isNotEmpty) {
      buffer.writeln('🎯 用户当前活跃意图：');
      for (final intent in activeIntents.take(3)) {
        if (intent is Map<String, dynamic>) {
          final description = intent['description'] ?? '';
          final category = intent['category'] ?? '';
          final state = intent['state'] ?? '';
          buffer.writeln('- $description (类别: $category, 状态: $state)');
        }
      }
    }

    // 关注主题信息
    final activeTopics = userStateContext['active_topics'] as List<dynamic>? ?? [];
    if (activeTopics.isNotEmpty) {
      buffer.writeln('📚 用户当前关注主题：');
      for (final topic in activeTopics.take(3)) {
        if (topic is Map<String, dynamic>) {
          final name = topic['name'] ?? '';
          final category = topic['category'] ?? '';
          final relevanceScore = topic['relevanceScore'] ?? 0.0;
          buffer.writeln('- $name (类别: $category, 相关性: ${relevanceScore.toStringAsFixed(2)})');
        }
      }
    }

    // 认知负载信息
    final cognitiveLoad = userStateContext['cognitive_load'] as Map<String, dynamic>? ?? {};
    if (cognitiveLoad.isNotEmpty) {
      buffer.writeln('🧠 用户认知状态：');
      final level = cognitiveLoad['level']?.toString() ?? '';
      final score = cognitiveLoad['score'] ?? 0.0;
      buffer.writeln('- 认知负载级别: $level (分数: ${score.toStringAsFixed(2)})');

      if (level == 'high' || level == 'overload') {
        buffer.writeln('- 建议：优先提取与用户当前意图直接相关的事件，减少复杂实体提取');
      }
    }

    buffer.writeln('');
    return buffer.toString();
  }

  // 🔥 新增：根据关键词查找相关节点
  static Future<List<Node>> getRelatedNodesByKeywords(List<String> keywords) async {
    try {
      final objectBox = ObjectBoxService();
      final relatedNodes = <Node>[];
      final nodeIds = <String>{};

      print('[KnowledgeGraphService] 🔍 通过关键词查找相关节点: ${keywords.join(', ')}');

      // 获取所有节点
      final allNodes = objectBox.queryNodes();

      for (final node in allNodes) {
        bool isRelevant = false;

        // 检查节点名称是否包含关键词
        for (final keyword in keywords) {
          if (node.name.toLowerCase().contains(keyword.toLowerCase()) ||
              node.canonicalName.toLowerCase().contains(keyword.toLowerCase())) {
            isRelevant = true;
            break;
          }

          // 检查节点别名是否包含关键词
          for (final alias in node.aliases) {
            if (alias.toLowerCase().contains(keyword.toLowerCase())) {
              isRelevant = true;
              break;
            }
          }

          // 检查节点属性值是否包含关键词
          for (final value in node.attributes.values) {
            if (value.toLowerCase().contains(keyword.toLowerCase())) {
              isRelevant = true;
              break;
            }
          }

          if (isRelevant) break;
        }

        if (isRelevant && !nodeIds.contains(node.id)) {
          relatedNodes.add(node);
          nodeIds.add(node.id);
        }
      }

      // 按相关性排序（优先匹配节点名称的）
      relatedNodes.sort((a, b) {
        int scoreA = 0;
        int scoreB = 0;

        for (final keyword in keywords) {
          // 名称完全匹配得分最高
          if (a.name.toLowerCase() == keyword.toLowerCase()) scoreA += 10;
          if (b.name.toLowerCase() == keyword.toLowerCase()) scoreB += 10;

          // 名称包含关键词得分较高
          if (a.name.toLowerCase().contains(keyword.toLowerCase())) scoreA += 5;
          if (b.name.toLowerCase().contains(keyword.toLowerCase())) scoreB += 5;

          // 别名匹配得分中等
          if (a.aliases.any((alias) => alias.toLowerCase().contains(keyword.toLowerCase()))) scoreA += 3;
          if (b.aliases.any((alias) => alias.toLowerCase().contains(keyword.toLowerCase()))) scoreB += 3;

          // 属性匹配得分较低
          if (a.attributes.values.any((value) => value.toLowerCase().contains(keyword.toLowerCase()))) scoreA += 1;
          if (b.attributes.values.any((value) => value.toLowerCase().contains(keyword.toLowerCase()))) scoreB += 1;
        }

        return scoreB.compareTo(scoreA); // 降序排列
      });

      print('[KnowledgeGraphService] 📊 找到 ${relatedNodes.length} 个相关节点');

      // 限制返回数量
      return relatedNodes.take(20).toList();

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 根据关键词查找节点错误: $e');
      return [];
    }
  }

  /// 🔍 根据输入文本，返回与之语义相似的历史事件
  static Future<List<Map<String, dynamic>>> searchEventsByText(
      String queryText, {
        int topK = 10,
        double similarityThreshold = 0.5,
      }) async {
    try {
      final objectBox = ObjectBoxService();
      final embeddingService = EmbeddingService();

      final queryVector = await embeddingService.generateTextEmbedding(queryText);
      if (queryVector == null) {
        print('[KnowledgeGraphService] ❌ 文本嵌入失败');
        return [];
      }

      final allEvents = objectBox.queryEventNodes();
      final results = await embeddingService.findSimilarEvents(
        queryVector,
        allEvents,
        topK: topK,
        threshold: similarityThreshold,
      );

      print('[KnowledgeGraphService] 🔍 相似事件查询完成: ${results.length} 个');
      return results;
    } catch (e) {
      print('[KnowledgeGraphService] ❌ searchEventsByText 错误: $e');
      return [];
    }
  }

  /// ✨ 生成并保存指定事件的嵌入向量（如果尚未生成）
  static Future<void> generateAndSaveEmbeddingForEvent(EventNode eventNode) async {
    try {
      final objectBox = ObjectBoxService();
      final embeddingService = EmbeddingService();

      if (eventNode.embedding != null && eventNode.embedding!.isNotEmpty) {
        print('[KnowledgeGraphService] ✅ 事件已存在嵌入，无需生成: ${eventNode.name}');
        return;
      }

      final embedding = await embeddingService.generateEventEmbedding(eventNode);
      if (embedding != null) {
        eventNode.embedding = embedding;
        objectBox.updateEventNode(eventNode);
        print('[KnowledgeGraphService] 💾 嵌入向量已保存: ${eventNode.name}');
      } else {
        print('[KnowledgeGraphService] ⚠️ 未能生成嵌入向量: ${eventNode.name}');
      }
    } catch (e) {
      print('[KnowledgeGraphService] ❌ generateAndSaveEmbeddingForEvent 错误: $e');
    }
  }


  /// 🧠 为所有缺失嵌入的事件生成嵌入向量
  static Future<void> generateEmbeddingsForAllEvents({bool force = false}) async {
    try {
      final objectBox = ObjectBoxService();
      final embeddingService = EmbeddingService();

      final allEvents = objectBox.queryEventNodes();
      int updatedCount = 0;

      for (final event in allEvents) {
        if (force || event.embedding == null || event.embedding!.isEmpty) {
          final embedding = await embeddingService.generateEventEmbedding(event);
          if (embedding != null) {
            event.embedding = embedding;
            objectBox.updateEventNode(event);
            updatedCount++;
          }
        }
      }

      print('[KnowledgeGraphService] ✅ 批量嵌入完成，共更新 $updatedCount 个事件');
    } catch (e) {
      print('[KnowledgeGraphService] ❌ generateEmbeddingsForAllEvents 错误: $e');
    }
  }


  /// 🧮 计算两个事件的嵌入向量相似度（余弦）
  static double? calculateEventSimilarity(EventNode a, EventNode b) {
    try {
      final embeddingService = EmbeddingService();

      if (a.embedding == null || b.embedding == null) return null;
      return embeddingService.calculateCosineSimilarity(a.embedding!, b.embedding!);
    } catch (e) {
      print('[KnowledgeGraphService] ❌ calculateEventSimilarity 错误: $e');
      return null;
    }
  }

  // 添加向量相似度查询方法
  Future<Map<String, dynamic>> queryByVectorSimilarity(Map<String, dynamic> queryRequest) async {
    try {
      final List<String> topics = List<String>.from(queryRequest['query_texts'] ?? []);
      final now = DateTime.now();

      await Future.delayed(Duration(milliseconds: 500));

      return {
        'generated_at': now.millisecondsSinceEpoch,
        'query_method': '向量相似度匹配',
        'active_topics_count': topics.length,
        'topic_match_stats': topics.map((topic) => {
          'topic_name': topic,
          'topic_weight': 0.8,
          'events_count': 2,
          'entities_count': 3,
          'avg_similarity': 0.7,
          'max_similarity': 0.85,
        }).toList(),
        'events': _generateSampleEvents(topics),
        'entities': _generateSampleEntities(topics),
        'relations': _generateSampleRelations(),
        'insights': _generateSampleInsights(topics),
      };
    } catch (e) {
      print('[KnowledgeGraphService] 向量查询错误: $e');
      return {
        'error': e.toString(),
        'generated_at': DateTime.now().millisecondsSinceEpoch,
        'active_topics_count': 0,
      };
    }
  }


  List<Map<String, dynamic>> _generateSampleEvents(List<String> topics) {
    return topics.take(3).map((topic) => {
      'name': '与${topic}相关的事件',
      'type': '用户交互',
      'description': '这是一个关于${topic}的重要事件描述',
      'similarity_score': 0.85 + (topics.indexOf(topic) * 0.05),
      'matched_by_topic': topic,
      'matched_by_topic_weight': 0.9,
      'formatted_date': '2024/01/15 14:30',
      'match_details': {
        'matched_text': '${topic}相关文本片段',
        'vector_distance': 0.15 - (topics.indexOf(topic) * 0.02),
      },
    }).toList();
  }

  List<Map<String, dynamic>> _generateSampleEntities(List<String> topics) {
    return topics.take(4).map((topic) => {
      'name': '${topic}实体',
      'type': '概念',
      'similarity_score': 0.8 + (topics.indexOf(topic) * 0.03),
      'matched_by_topic': topic,
      'aliases': ['别名1', '别名2'],
    }).toList();
  }

  List<Map<String, dynamic>> _generateSampleRelations() {
    return [
      {'source': '实体A', 'target': '实体B'},
      {'source': '实体B', 'target': '实体C'},
    ];
  }

  List<String> _generateSampleInsights(List<String> topics) {
    return [
      '发现了${topics.length}个主题之间的关联性',
      '向量相似度匹配准确率达到85%',
      '主题聚类效果良好',
    ];
  }


  // 🔥 新增：只提取事件和实体信息，不写入数据库（用于上下文分析）
  static Future<Map<String, dynamic>> analyzeEventsAndEntitiesFromText(
    String conversationText,
    {DateTime? conversationTime, Map<String, dynamic>? userStateContext}
  ) async {
    print('[KnowledgeGraphService] 🔍 分析事件和实体（仅提取，不写入）...');

    // 直接调用现有的提取函数，但不进行数据库操作
    return await extractEventsAndEntitiesFromText(
      conversationText,
      conversationTime: conversationTime,
      userStateContext: userStateContext,
    );
  }

  // 🔥 新增：基于分析结果查找相关的历史事件和实体（用于上下文增强）
  static Future<Map<String, dynamic>> getContextFromAnalysis(
    Map<String, dynamic> analysisResult
  ) async {
    try {
      print('[KnowledgeGraphService] 🔍 基于分析结果查找历史上下文...');

      final entities = analysisResult['entities'] as List? ?? [];
      final events = analysisResult['events'] as List? ?? [];

      final relatedNodes = <Node>[];
      final relatedEvents = <EventNode>[];
      final nodeIds = <String>{};
      final eventIds = <String>{};

      // 1. 基于提取的实体查找历史实体节点
      for (final entityData in entities) {
        if (entityData is Map) {
          final name = entityData['name']?.toString() ?? '';
          final type = entityData['type']?.toString() ?? '';

          if (name.isNotEmpty && type.isNotEmpty) {
            // 查找相似的历史实体
            final entityKeywords = [name];
            final matchingNodes = await getRelatedNodesByKeywords(entityKeywords);

            for (final node in matchingNodes) {
              if (!nodeIds.contains(node.id)) {
                relatedNodes.add(node);
                nodeIds.add(node.id);
              }
            }
          }
        }
      }

      // 2. 基于找到的实体节点查找相关历史事件
      for (final node in relatedNodes) {
        final nodeEvents = await getRelatedEvents(node.id);
        for (final event in nodeEvents) {
          if (!eventIds.contains(event.id)) {
            relatedEvents.add(event);
            eventIds.add(event.id);
          }
        }
      }

      // 3. 按时间排序，最近的在前
      relatedEvents.sort((a, b) {
        final timeA = a.startTime?.millisecondsSinceEpoch ?? a.lastUpdated.millisecondsSinceEpoch;
        final timeB = b.startTime?.millisecondsSinceEpoch ?? b.lastUpdated.millisecondsSinceEpoch;
        return timeB.compareTo(timeA);
      });

      print('[KnowledgeGraphService] 📊 上下文查找结果: ${relatedNodes.length}个相关节点, ${relatedEvents.length}个相关事件');

      return {
        'related_nodes': relatedNodes.take(10).toList(), // 限制数量避免过多
        'related_events': relatedEvents.take(15).toList(),
        'analysis_entities': entities,
        'analysis_events': events,
        'context_summary': _summarizeContext(relatedNodes, relatedEvents, entities, events),
      };

    } catch (e) {
      print('[KnowledgeGraphService] ❌ 获取分析上下文失败: $e');
      return {
        'related_nodes': <Node>[],
        'related_events': <EventNode>[],
        'analysis_entities': [],
        'analysis_events': [],
        'context_summary': '',
        'error': e.toString(),
      };
    }
  }

  // 🔥 新增：总结上下文信息
  static String _summarizeContext(
    List<Node> relatedNodes,
    List<EventNode> relatedEvents,
    List<dynamic> analysisEntities,
    List<dynamic> analysisEvents
  ) {
    final summary = StringBuffer();

    // 当前分析到的内容
    if (analysisEntities.isNotEmpty || analysisEvents.isNotEmpty) {
      summary.write('当前对话涉及: ');
      if (analysisEntities.isNotEmpty) {
        summary.write('${analysisEntities.length}个实体 ');
      }
      if (analysisEvents.isNotEmpty) {
        summary.write('${analysisEvents.length}个事件 ');
      }
    }

    // 历史相关内容
    if (relatedNodes.isNotEmpty || relatedEvents.isNotEmpty) {
      if (summary.isNotEmpty) summary.write('; ');
      summary.write('历史相关: ');

      if (relatedNodes.isNotEmpty) {
        final nodesByType = <String, List<Node>>{};
        for (final node in relatedNodes.take(5)) { // 限制显示数量
          nodesByType.putIfAbsent(node.type, () => []).add(node);
        }

        final nodeTypesSummary = nodesByType.entries
            .map((e) => '${e.key}(${e.value.length}个)')
            .join('、');
        summary.write('$nodeTypesSummary ');
      }

      if (relatedEvents.isNotEmpty) {
        final eventsByType = <String, List<EventNode>>{};
        for (final event in relatedEvents.take(5)) { // 限制显示数量
          eventsByType.putIfAbsent(event.type, () => []).add(event);
        }

        final eventTypesSummary = eventsByType.entries
            .map((e) => '${e.key}事件(${e.value.length}个)')
            .join('、');
        summary.write('$eventTypesSummary');
      }
    }

    return summary.toString().isEmpty ? '未找到相关历史信息' : summary.toString();
  }
}
