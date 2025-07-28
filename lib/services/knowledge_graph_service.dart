import 'dart:convert';
import 'dart:math' as math;
import 'package:app/models/graph_models.dart';
import 'package:app/models/event_relation_entity.dart';
import 'package:app/models/record_entity.dart';
import 'package:app/services/embeddings_service.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/objectbox_service.dart';

class KnowledgeGraphService {
  static final KnowledgeGraphService _instance = KnowledgeGraphService._internal();
  factory KnowledgeGraphService() => _instance;
  KnowledgeGraphService._internal();

  // 从对话文本中提取事件
  static Future<Map<String, List<dynamic>>> extractEventsFromText(String conversationText, {DateTime? conversationTime}) async {
    final now = conversationTime ?? DateTime.now();
    final timeContext = "${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日";
    final eventExtractionPrompt = """
你是一个知识图谱构建助手。请从我提供的对话中提取出结构化的知识图谱信息，由于我给你的对话内容是由语音转文字生成的，所以可能会不太准确或者有些发音的转换错误，请你试着先猜测还原一下。输出格式为 JSON，包含以下部分：

1. nodes：实体节点数组，每个节点结构如下：
{
  "id": "唯一标识（可用name type组合）",
  "name": "实体名称",
  "type": "实体类型（如 手机、人、事件、政策、地点）",
  "attributes": {
    "属性名1": "属性值1",
    "属性名2": "属性值2"
  }
}

2. edges：关系边数组，每个边结构如下：
{
  "source": "源实体ID",
  "relation": "关系类型（如 使用、购买、建议）",
  "target": "目标实体ID或值",
  "context": "可选：上下文描述，如对话原文",
  "timestamp": "可选：时间戳或日期"
}

请保持字段标准化，确保结果可以被 JSON 解析器直接解析,当前对话的发生时间是$timeContext。

对话内容如下：
""";
    try {
      print('[KnowledgeGraphService] 🔍 开始提取事件，对话长度: \\${conversationText.length}');
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: eventExtractionPrompt);
      print('[KnowledgeGraphService] ✅ LLM实例创建成功');
      final response = await llm.createRequest(content: conversationText);
      print('[KnowledgeGraphService] 📝 LLM响应长度: \\${response.length}');
      print('[KnowledgeGraphService] 📄 LLM原始响应: \\${response.substring(0, response.length > 200 ? 200 : response.length)}...');
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        throw FormatException('未找到合法的 JSON 对象');
      }
      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map && decoded['edges'] is List && decoded['nodes'] is List) {
        return {
          'nodes': decoded['nodes'] as List,
          'edges': decoded['edges'] as List,
        };
      } else {
        throw FormatException('返回内容不是包含nodes和edges的对象');
      }
    } catch (e, st) {
      print('[KnowledgeGraphService] ❌ 事件提取错误: $e\n$st');
      return {'nodes': [], 'edges': []};
    }
  }

  // 处理单个三元组事件，写入知识图谱
  static Future<void> processEvent(Map<String, dynamic> eventData, {required String contextId}) async {
    final objectBox = ObjectBoxService();
    // 1. 处理主语节点
    final subject = eventData['subject'] as Map<String, dynamic>?;
    if (subject == null) return;
    final subjectId = subject['id'] ?? (subject['name'] + '_' + subject['type']);
    Node? subjectNode = objectBox.findNodeByNameType(subject['name'], subject['type']);
    if (subjectNode == null) {
      subjectNode = Node(
        id: subjectId,
        name: subject['name'],
        type: subject['type'],
        attributes: Map<String, String>.from(subject['attributes'] ?? {}),
      );
      objectBox.insertNode(subjectNode);
    }
    // 2. 处理宾语节点（如为实体）
    String? objectId;
    Node? objectNode;
    final obj = eventData['object'];
    if (obj is Map<String, dynamic>) {
      objectId = obj['id'] ?? (obj['name'] + '_' + obj['type']);
      objectNode = objectBox.findNodeByNameType(obj['name'], obj['type']);
      if (objectNode == null) {
        objectNode = Node(
          id: objectId ?? '', // 修复类型不匹配
          name: obj['name'],
          type: obj['type'],
          attributes: Map<String, String>.from(obj['attributes'] ?? {}),
        );
        objectBox.insertNode(objectNode);
      }
    } else if (obj is String) {
      objectId = obj;
    }
    // 3. 插入关系边
    final edge = Edge(
      source: subjectId,
      relation: eventData['predicate'] ?? '',
      target: objectId ?? '',
      context: contextId,
      timestamp: eventData['timestamp'] != null ? DateTime.tryParse(eventData['timestamp']) : DateTime.now(),
    );
    objectBox.insertEdge(edge);
    // 4. 插入属性（主语、宾语）
    if (subject['attributes'] != null) {
      subject['attributes'].forEach((k, v) {
        objectBox.insertAttribute(Attribute(
          nodeId: subjectId,
          key: k,
          value: v,
          timestamp: DateTime.now(),
          context: contextId,
        ));
      });
    }
    if (objectNode != null && obj['attributes'] != null) {
      obj['attributes'].forEach((k, v) {
        objectBox.insertAttribute(Attribute(
          nodeId: objectId!,
          key: k,
          value: v,
          timestamp: DateTime.now(),
          context: contextId,
        ));
      });
    }
  }

  // 批量处理事件，写入知识图谱
  static Future<void> processEventsFromConversation(String conversationText, {required String contextId, DateTime? conversationTime}) async {
    try {
      final result = await extractEventsFromText(conversationText, conversationTime: conversationTime);
      final nodes = result['nodes'] ?? [];
      final edges = result['edges'] ?? [];
      final objectBox = ObjectBoxService();
      // 1. 写入节点（查重）
      for (final nodeData in nodes) {
        if (nodeData is Map) {
          final id = nodeData['id']?.toString() ?? (nodeData['name']?.toString() ?? '') + '_' + (nodeData['type']?.toString() ?? '');
          final name = nodeData['name']?.toString() ?? '';
          final type = nodeData['type']?.toString() ?? '';
          final attributes = nodeData['attributes'] is Map ? Map<String, String>.from(nodeData['attributes']) : <String, String>{};
          // 修正查重逻辑，只有查不到节点时才插入
          if (objectBox.findNodeByNameType(name, type) == null) {
            objectBox.insertNode(Node(id: id, name: name, type: type, attributes: attributes));
          }
          // 同步属性到 Attribute 表
          attributes.forEach((k, v) {
            objectBox.insertAttribute(Attribute(
              nodeId: id,
              key: k,
              value: v,
              timestamp: conversationTime ?? DateTime.now(),
              context: contextId,
            ));
          });
        }
      }
      // 2. 写入边
      for (final edgeData in edges) {
        if (edgeData is Map) {
          final source = edgeData['source']?.toString() ?? '';
          final relation = edgeData['relation']?.toString() ?? '';
          final target = edgeData['target']?.toString() ?? '';
          final timestamp = edgeData['timestamp'] != null ? DateTime.tryParse(edgeData['timestamp'].toString()) : (conversationTime ?? DateTime.now());
          objectBox.insertEdge(Edge(
            source: source,
            relation: relation,
            target: target,
            context: contextId,
            timestamp: timestamp,
          ));
        }
      }
      print('[KnowledgeGraphService] 成功写入节点数据: $nodes');
      print('[DialogueSummary] 成功写入节点数据: $nodes');
      print('[KnowledgeGraphService] 成功写入边数据: $edges');
      print('[DialogueSummary] 成功写入边数据: $edges');
    } catch (e) {
      print('[KnowledgeGraphService] Error processing conversation: $e');
    }
  }

  // 按10分钟分段处理对话，逐段调用LLM
  static Future<void> processEventsFromConversationBySegments(List<RecordEntity> records, {int segmentMinutes = 10}) async {
    if (records.isEmpty) return;
    // 1. 按时间排序
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

    print('[KnowledgeGraphService] 分段数量: \\${segments.length}');
    // 2. 逐段处理
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final chatHistoryBuffer = StringBuffer();
      for (final record in seg) {
        if (record.content != null && record.content!.trim().isNotEmpty) {
          final formattedTime = DateTime.fromMillisecondsSinceEpoch(record.createdAt ?? 0).toString();
          chatHistoryBuffer.write('($formattedTime) ${record.role}: ${record.content}\n');
        }
      }
      final chatHistory = chatHistoryBuffer.toString();
      if (chatHistory.trim().isEmpty) continue;
      print('[KnowledgeGraphService] 处理第\\${i+1}段, 长度: \\${chatHistory.length}');
      await processEventsFromConversation(chatHistory, contextId: '${segments[i].first.createdAt}');
    }
  }

  // 获取节点的关联节点（通过边连接）
  static Future<List<Node>> getRelatedNodes(String nodeId) async {
    try {
      final objectBox = ObjectBoxService();
      final edges = objectBox.queryEdges(source: nodeId);
      final targetIds = edges.map((e) => e.target).toSet();
      final relatedNodes = <Node>[];
      for (final id in targetIds) {
        Node? node = objectBox.queryNodes().firstWhere(
          (n) => n.id == id,
          orElse: () => Node(id: '', name: '', type: ''),
        );
        if (node.id.isNotEmpty) relatedNodes.add(node);
      }
      return relatedNodes;
    } catch (e) {
      print('[KnowledgeGraphService] Error getting related nodes: $e');
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
          if (node.name.contains(keyword)) {
            result.add(node);
            // 也可以查找与该节点直接关联的节点
            final edges = objectBox.queryEdges(source: node.id);
            for (final edge in edges) {
              final related = allNodes.firstWhere(
                (n) => n.id == edge.target,
                orElse: () => Node(id: '', name: '', type: ''),
              );
              if (related.id.isNotEmpty) result.add(related);
            }
          }
        }
      }
      return result.toList();
    } catch (e) {
      print('[KnowledgeGraphService] Error in getRelatedNodesByKeywords: $e');
      return [];
    }
  }

}
