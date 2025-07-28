import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';

// 意图类型枚举
enum IntentType {
  query,        // 查询信息："iPhone 15的价格是多少？"
  purchase,     // 购买意图："我想买iPhone 15"
  compare,      // 比较："iPhone 15和小米14哪个好？"
  recommend,    // 推荐："推荐一款手机"
  general,      // 一般聊天
}

// 实体识别结果
class EntityMatch {
  final String text;           // 原文中的实体文本
  final String entityId;       // 知识图谱中的实体ID
  final String entityName;     // 知识图谱中的实体名称
  final String entityType;     // 实体类型
  final double confidence;     // 置信度

  EntityMatch({
    required this.text,
    required this.entityId,
    required this.entityName,
    required this.entityType,
    required this.confidence,
  });
}

// 意图识别结果
class IntentAnalysis {
  final IntentType intent;
  final List<EntityMatch> entities;
  final List<String> keywords;
  final double confidence;

  IntentAnalysis({
    required this.intent,
    required this.entities,
    required this.keywords,
    required this.confidence,
  });
}

class SmartKGService {
  static final SmartKGService _instance = SmartKGService._internal();
  factory SmartKGService() => _instance;
  SmartKGService._internal();

  // 智能意图和实体识别
  Future<IntentAnalysis> analyzeUserInput(String userInput) async {
    try {
      // 1. 先做基础的实体识别（基于知识图谱中现有的实体）
      final entities = await _recognizeEntities(userInput);

      // 2. 提取关键词（改进版）
      final keywords = _extractSmartKeywords(userInput);

      // 3. 意图识别
      final intent = _classifyIntent(userInput, entities);

      return IntentAnalysis(
        intent: intent,
        entities: entities,
        keywords: keywords,
        confidence: 0.8, // 简化版本使用固定置信度
      );
    } catch (e) {
      print('SmartKGService analyzeUserInput error: $e');
      return IntentAnalysis(
        intent: IntentType.general,
        entities: [],
        keywords: _extractSmartKeywords(userInput),
        confidence: 0.5,
      );
    }
  }

  // 基于知识图谱的实体识别
  Future<List<EntityMatch>> _recognizeEntities(String userInput) async {
    final objectBox = ObjectBoxService();
    final allNodes = objectBox.queryNodes();
    final entities = <EntityMatch>[];

    // 1. 精确匹配
    for (final node in allNodes) {
      if (userInput.contains(node.name)) {
        entities.add(EntityMatch(
          text: node.name,
          entityId: node.id,
          entityName: node.name,
          entityType: node.type,
          confidence: 1.0,
        ));
      }
    }

    // 2. 模糊匹配（处理部分匹配的情况）
    final inputLower = userInput.toLowerCase();
    for (final node in allNodes) {
      final nodeLower = node.name.toLowerCase();

      // 检查是否有部分匹配
      if (!entities.any((e) => e.entityId == node.id)) {
        if (_fuzzyMatch(inputLower, nodeLower)) {
          entities.add(EntityMatch(
            text: node.name,
            entityId: node.id,
            entityName: node.name,
            entityType: node.type,
            confidence: 0.7,
          ));
        }
      }
    }

    // 3. 同义词和别名匹配
    entities.addAll(await _matchSynonyms(userInput, allNodes));

    return entities;
  }

  // 模糊匹配算法
  bool _fuzzyMatch(String input, String target) {
    // 简单的模糊匹配：检查是否包含主要词汇
    final targetWords = target.split(RegExp(r'[^\w\u4e00-\u9fa5]'));
    final inputWords = input.split(RegExp(r'[^\w\u4e00-\u9fa5]'));

    int matchCount = 0;
    for (final word in targetWords) {
      if (word.length > 1 && inputWords.any((w) => w.contains(word) || word.contains(w))) {
        matchCount++;
      }
    }

    return matchCount > 0 && matchCount >= (targetWords.length * 0.5);
  }

  // 同义词匹配
  Future<List<EntityMatch>> _matchSynonyms(String userInput, List<Node> allNodes) async {
    final entities = <EntityMatch>[];

    // 定义一些常见的同义词映射
    final synonyms = {
      '手机': ['电话', '移动电话', '智能机', '机子'],
      'iPhone': ['苹果手机', '爱疯', 'iphone'],
      '小米': ['MI', 'mi', '雷军手机'],
      '购买': ['买', '入手', '下单', '订购', '采购'],
      '价格': ['多少钱', '费用', '成本', '价位', '售价'],
    };

    for (final node in allNodes) {
      if (synonyms.containsKey(node.name)) {
        for (final synonym in synonyms[node.name]!) {
          if (userInput.contains(synonym)) {
            entities.add(EntityMatch(
              text: synonym,
              entityId: node.id,
              entityName: node.name,
              entityType: node.type,
              confidence: 0.8,
            ));
          }
        }
      }
    }

    return entities;
  }

  // 改进的关键词提取
  List<String> _extractSmartKeywords(String userInput) {
    // 1. 基础分词
    final basicKeywords = RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]+')
        .allMatches(userInput)
        .map((m) => m.group(0)!)
        .toList();

    // 2. 过滤停用词
    final stopWords = {'的', '是', '我', '你', '他', '她', '它', '这', '那', '了', '吗', '呢', '吧', '一', '个', '在', 'and', 'or', 'the', 'a', 'an'};
    final filteredKeywords = basicKeywords.where((word) =>
        word.length > 1 && !stopWords.contains(word.toLowerCase())).toList();

    // 3. 添加数字和品牌词的特殊处理
    final enhancedKeywords = <String>[];
    enhancedKeywords.addAll(filteredKeywords);

    // 提取价格相关的数字
    final pricePattern = RegExp(r'\d+(?:元|块|万|千)?');
    final priceMatches = pricePattern.allMatches(userInput);
    for (final match in priceMatches) {
      enhancedKeywords.add(match.group(0)!);
    }

    // 提取型号信息（如iPhone 15, 小米14）
    final modelPattern = RegExp(r'[A-Za-z]+\s*\d+|[\u4e00-\u9fa5]+\d+');
    final modelMatches = modelPattern.allMatches(userInput);
    for (final match in modelMatches) {
      enhancedKeywords.add(match.group(0)!);
    }

    return enhancedKeywords.toSet().toList();
  }

  // 意图分类
  IntentType _classifyIntent(String userInput, List<EntityMatch> entities) {
    final input = userInput.toLowerCase();

    // 购买意图关键词
    if (RegExp(r'想买|要买|购买|入手|下单|订购').hasMatch(input)) {
      return IntentType.purchase;
    }

    // 比较意图关键词
    if (RegExp(r'比较|对比|哪个好|选择|vs|和.*比').hasMatch(input) || entities.length >= 2) {
      return IntentType.compare;
    }

    // 推荐意图关键词
    if (RegExp(r'推荐|建议|介绍.*给|什么.*好').hasMatch(input)) {
      return IntentType.recommend;
    }

    // 查询意图关键词
    if (RegExp(r'多少钱|价格|怎么样|如何|什么是|告诉我').hasMatch(input)) {
      return IntentType.query;
    }

    return IntentType.general;
  }

  // 基于意图和实体的智能知识图谱检索
  Future<List<Node>> getRelevantNodes(IntentAnalysis analysis) async {
    final objectBox = ObjectBoxService();
    final relevantNodes = <Node>{};

    // 1. 直接实体匹配
    for (final entity in analysis.entities) {
      final node = objectBox.findNodeById(entity.entityId);
      if (node != null) {
        relevantNodes.add(node);
      }
    }

    // 2. 基于意图的扩展检索
    switch (analysis.intent) {
      case IntentType.purchase:
        // 购买意图：添加相关的产品信息、价格信息
        await _addPurchaseRelatedNodes(relevantNodes, analysis);
        break;

      case IntentType.compare:
        // 比较意图：添加同类型的产品
        await _addComparisonNodes(relevantNodes, analysis);
        break;

      case IntentType.recommend:
        // 推荐意图：根据用户历史和偏好添加推荐
        await _addRecommendationNodes(relevantNodes, analysis);
        break;

      case IntentType.query:
        // 查询意图：添加相关属性和关联信息
        await _addQueryRelatedNodes(relevantNodes, analysis);
        break;

      case IntentType.general:
        // 一般聊天：基于关键词的基础匹配
        await _addGeneralNodes(relevantNodes, analysis);
        break;
    }

    return relevantNodes.toList();
  }

  // 购买相关节点扩展
  Future<void> _addPurchaseRelatedNodes(Set<Node> nodes, IntentAnalysis analysis) async {
    final objectBox = ObjectBoxService();

    for (final entity in analysis.entities) {
      // 添加产品的详细信息
      final relatedEdges = objectBox.queryEdges(source: entity.entityId);
      for (final edge in relatedEdges) {
        final targetNode = objectBox.findNodeById(edge.target);
        if (targetNode != null) {
          nodes.add(targetNode);
        }
      }

      // 添加同类型产品进行比较
      final sameTypeNodes = objectBox.queryNodes().where((n) =>
          n.type == entity.entityType && n.id != entity.entityId).toList();
      nodes.addAll(sameTypeNodes.take(3)); // 限制数量
    }
  }

  // 比较相关节点扩展
  Future<void> _addComparisonNodes(Set<Node> nodes, IntentAnalysis analysis) async {
    final objectBox = ObjectBoxService();

    // 获取所有涉及实体的同类型产品
    final entityTypes = analysis.entities.map((e) => e.entityType).toSet();
    for (final type in entityTypes) {
      final sameTypeNodes = objectBox.queryNodes().where((n) => n.type == type).toList();
      nodes.addAll(sameTypeNodes);
    }
  }

  // 推荐相关节点扩展
  Future<void> _addRecommendationNodes(Set<Node> nodes, IntentAnalysis analysis) async {
    final objectBox = ObjectBoxService();

    // 基于关键词推荐相关产品
    for (final keyword in analysis.keywords) {
      final matchingNodes = objectBox.queryNodes().where((n) =>
          n.name.contains(keyword) ||
          n.type.contains(keyword) ||
          n.attributes.values.any((v) => v.contains(keyword))).toList();
      nodes.addAll(matchingNodes.take(5)); // 限制推荐数量
    }
  }

  // 查询相关节点扩展
  Future<void> _addQueryRelatedNodes(Set<Node> nodes, IntentAnalysis analysis) async {
    final objectBox = ObjectBoxService();

    for (final entity in analysis.entities) {
      // 添加与查询实体相关的所有信息
      final incomingEdges = objectBox.queryEdges(target: entity.entityId);
      final outgoingEdges = objectBox.queryEdges(source: entity.entityId);

      for (final edge in [...incomingEdges, ...outgoingEdges]) {
        final sourceNode = objectBox.findNodeById(edge.source);
        final targetNode = objectBox.findNodeById(edge.target);
        if (sourceNode != null) nodes.add(sourceNode);
        if (targetNode != null) nodes.add(targetNode);
      }
    }
  }

  // 一般聊天节点扩展
  Future<void> _addGeneralNodes(Set<Node> nodes, IntentAnalysis analysis) async {
    final objectBox = ObjectBoxService();

    // 基于关键词的基础匹配
    for (final keyword in analysis.keywords) {
      final matchingNodes = objectBox.queryNodes().where((n) =>
          n.name.contains(keyword)).toList();
      nodes.addAll(matchingNodes.take(3)); // 限制数量
    }
  }
}
