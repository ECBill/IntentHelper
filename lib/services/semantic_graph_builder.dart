/// 语义图谱构建器
/// 负责将实体、意图、情绪等组织成三元组图谱，支持存储、查询和更新

import 'dart:async';
import 'dart:convert';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/objectbox_service.dart';

class SemanticGraphBuilder {
  static final SemanticGraphBuilder _instance = SemanticGraphBuilder._internal();
  factory SemanticGraphBuilder() => _instance;
  SemanticGraphBuilder._internal();

  final Map<String, SemanticTriple> _triples = {};
  final Map<String, Set<String>> _entityIndex = {}; // 实体索引
  final Map<String, Set<String>> _predicateIndex = {}; // 谓词索引
  final StreamController<SemanticTriple> _tripleUpdatesController = StreamController.broadcast();

  Timer? _consolidationTimer;
  bool _initialized = false;

  /// 三元组更新流
  Stream<SemanticTriple> get tripleUpdates => _tripleUpdatesController.stream;

  /// 初始化构建器
  Future<void> initialize() async {
    if (_initialized) return;

    print('[SemanticGraphBuilder] 🚀 初始化语义图谱构建器...');

    // 启动定期图谱整合
    _startPeriodicConsolidation();

    _initialized = true;
    print('[SemanticGraphBuilder] ✅ 语义图谱构建器初始化完成');
  }

  /// 构建语义三元组
  Future<List<SemanticTriple>> buildSemanticGraph(
    SemanticAnalysisInput analysis,
    List<Intent> intents,
    List<ConversationTopic> topics,
    List<CausalRelation> causalRelations,
  ) async {
    if (!_initialized) await initialize();

    print('[SemanticGraphBuilder] 🔗 构建语义图谱: "${analysis.content.substring(0, analysis.content.length > 50 ? 50 : analysis.content.length)}..."');

    try {
      final newTriples = <SemanticTriple>[];

      // 1. 从直接对话内容提取三元组
      final directTriples = await _extractDirectTriples(analysis);
      newTriples.addAll(directTriples);

      // 2. 从意图构建三元组
      final intentTriples = _buildIntentTriples(analysis, intents);
      newTriples.addAll(intentTriples);

      // 3. 从主题构建三元组
      final topicTriples = _buildTopicTriples(analysis, topics);
      newTriples.addAll(topicTriples);

      // 4. 从因果关系构建三元组
      final causalTriples = _buildCausalTriples(causalRelations);
      newTriples.addAll(causalTriples);

      // 5. 构建实体间关系三元组
      final entityTriples = await _buildEntityRelationTriples(analysis);
      newTriples.addAll(entityTriples);

      // 6. 存储新三元组
      for (final triple in newTriples) {
        if (!_isDuplicateTriple(triple)) {
          _storeTriple(triple);
        }
      }

      print('[SemanticGraphBuilder] ✅ 图谱构建完成，新增 ${newTriples.length} 个三元组');

      return newTriples;

    } catch (e) {
      print('[SemanticGraphBuilder] ❌ 构建语义图谱失败: $e');
      return [];
    }
  }

  /// 从直接对话内容提取三元组
  Future<List<SemanticTriple>> _extractDirectTriples(SemanticAnalysisInput analysis) async {
    final tripleExtractionPrompt = '''
你是一个语义三元组提取专家。请从用户对话中提取结构化的三元组关系。

【三元组结构】：
主语(Subject) - 谓词(Predicate) - 宾语(Object)

【提取原则】：
1. 主语和宾语应该是具体的实体（人、物、概念、地点等）
2. 谓词应该是描述关系或属性的动词或介词短语
3. 优先提取有意义、有价值的关系
4. 避免过于琐碎或显而易见的关系

【谓词类型示例】：
- 属性关系：是、有、属于、包含
- 行为关系：做、使用、去、来、买、卖
- 情感关系：喜欢、讨厌、担心、期待
- 时间关系：在...之前、在...之后、同时
- 空间关系：在、附近、远离
- 因果关系：导致、引起、由于、影响
- 社会关系：认识、是朋友、是同事、是家人

输出格式为JSON数组：
[
  {
    "subject": "主语",
    "predicate": "谓词", 
    "object": "宾语",
    "confidence": 0.8,
    "evidence": "支持这个三元组的文本片段",
    "triple_type": "semantic|temporal|causal|emotional|spatial"
  }
]

用户对话：
"${analysis.content}"

检测到的实体：${analysis.entities}
''';

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: tripleExtractionPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) {
        return [];
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> triplesData = jsonDecode(jsonStr);

      final triples = <SemanticTriple>[];
      for (final tripleData in triplesData) {
        if (tripleData is Map) {
          final subject = tripleData['subject']?.toString() ?? '';
          final predicate = tripleData['predicate']?.toString() ?? '';
          final object = tripleData['object']?.toString() ?? '';
          final confidence = (tripleData['confidence'] as num?)?.toDouble() ?? 0.5;
          final evidence = tripleData['evidence']?.toString() ?? '';
          final tripleType = tripleData['triple_type']?.toString() ?? 'semantic';

          if (subject.isNotEmpty && predicate.isNotEmpty && object.isNotEmpty) {
            final triple = SemanticTriple(
              subject: subject,
              predicate: predicate,
              object: object,
              confidence: confidence,
              sourceContext: analysis.content,
              supportingEvidence: [evidence],
              attributes: {
                'triple_type': tripleType,
                'extraction_method': 'direct',
                'source_emotion': analysis.emotion,
                'timestamp': analysis.timestamp.toIso8601String(),
              },
            );

            triples.add(triple);
            print('[SemanticGraphBuilder] 📝 直接三元组: ($subject, $predicate, $object)');
          }
        }
      }

      return triples;

    } catch (e) {
      print('[SemanticGraphBuilder] ❌ 提取直接三元组失败: $e');
      return [];
    }
  }

  /// 从意图构建三元组
  List<SemanticTriple> _buildIntentTriples(SemanticAnalysisInput analysis, List<Intent> intents) {
    final triples = <SemanticTriple>[];

    for (final intent in intents) {
      // 用户-意图关系
      triples.add(SemanticTriple(
        subject: '用户',
        predicate: '有意图',
        object: intent.description,
        confidence: intent.confidence,
        sourceContext: analysis.content,
        attributes: {
          'intent_id': intent.id,
          'intent_category': intent.category,
          'intent_state': intent.state.toString(),
          'extraction_method': 'intent_derived',
        },
      ));

      // 意图-状态关系
      triples.add(SemanticTriple(
        subject: intent.description,
        predicate: '处于状态',
        object: intent.state.toString().split('.').last,
        confidence: 0.9,
        sourceContext: analysis.content,
        attributes: {
          'intent_id': intent.id,
          'extraction_method': 'intent_derived',
        },
      ));

      // 意图-实体关系
      for (final entity in intent.relatedEntities) {
        triples.add(SemanticTriple(
          subject: intent.description,
          predicate: '涉及',
          object: entity,
          confidence: intent.confidence * 0.8,
          sourceContext: analysis.content,
          attributes: {
            'intent_id': intent.id,
            'extraction_method': 'intent_derived',
          },
        ));
      }
    }

    return triples;
  }

  /// 从主题构建三元组
  List<SemanticTriple> _buildTopicTriples(SemanticAnalysisInput analysis, List<ConversationTopic> topics) {
    final triples = <SemanticTriple>[];

    for (final topic in topics) {
      // 用户-主题关系
      triples.add(SemanticTriple(
        subject: '用户',
        predicate: '讨论',
        object: topic.name,
        confidence: topic.relevanceScore,
        sourceContext: analysis.content,
        attributes: {
          'topic_id': topic.id,
          'topic_category': topic.category,
          'topic_state': topic.state.toString(),
          'extraction_method': 'topic_derived',
        },
      ));

      // 主题-关键词关系
      for (final keyword in topic.keywords) {
        triples.add(SemanticTriple(
          subject: topic.name,
          predicate: '包含关键词',
          object: keyword,
          confidence: topic.relevanceScore * 0.7,
          sourceContext: analysis.content,
          attributes: {
            'topic_id': topic.id,
            'extraction_method': 'topic_derived',
          },
        ));
      }

      // 主题-实体关系
      for (final entity in topic.entities) {
        triples.add(SemanticTriple(
          subject: topic.name,
          predicate: '涉及实体',
          object: entity,
          confidence: topic.relevanceScore * 0.8,
          sourceContext: analysis.content,
          attributes: {
            'topic_id': topic.id,
            'extraction_method': 'topic_derived',
          },
        ));
      }
    }

    return triples;
  }

  /// 从因果关系构建三元组
  List<SemanticTriple> _buildCausalTriples(List<CausalRelation> causalRelations) {
    final triples = <SemanticTriple>[];

    for (final relation in causalRelations) {
      String predicate;
      switch (relation.type) {
        case CausalRelationType.directCause:
          predicate = '直接导致';
          break;
        case CausalRelationType.indirectCause:
          predicate = '间接导致';
          break;
        case CausalRelationType.enabler:
          predicate = '使能';
          break;
        case CausalRelationType.inhibitor:
          predicate = '抑制';
          break;
        case CausalRelationType.correlation:
          predicate = '相关';
          break;
      }

      triples.add(SemanticTriple(
        subject: relation.cause,
        predicate: predicate,
        object: relation.effect,
        confidence: relation.confidence,
        sourceContext: relation.sourceText,
        attributes: {
          'causal_relation_id': relation.id,
          'causal_type': relation.type.toString(),
          'extraction_method': 'causal_derived',
        },
      ));
    }

    return triples;
  }

  /// 构建实体间关系三元组
  Future<List<SemanticTriple>> _buildEntityRelationTriples(SemanticAnalysisInput analysis) async {
    if (analysis.entities.length < 2) return [];

    final entityRelationPrompt = '''
你是一个实体关系识别专家。请分析用户对话中实体之间的关系。

【实体关系类型】：
- 所有关系：属于、拥有、包含
- 位置关系：在、附近、远离
- 时间关系：之前、之后、同时
- 社会关系：是朋友、是同事、是家人、认识
- 功能关系：用于、服务于、支持
- 比较关系：比...更、类似、不同于

输出格式为JSON数组：
[
  {
    "entity1": "实体1",
    "relation": "关系类型",
    "entity2": "实体2", 
    "confidence": 0.7,
    "evidence": "支持证据"
  }
]

对话内容：
"${analysis.content}"

实体列表：${analysis.entities}
''';

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: entityRelationPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) {
        return [];
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> relationsData = jsonDecode(jsonStr);

      final triples = <SemanticTriple>[];
      for (final relationData in relationsData) {
        if (relationData is Map) {
          final entity1 = relationData['entity1']?.toString() ?? '';
          final relation = relationData['relation']?.toString() ?? '';
          final entity2 = relationData['entity2']?.toString() ?? '';
          final confidence = (relationData['confidence'] as num?)?.toDouble() ?? 0.5;
          final evidence = relationData['evidence']?.toString() ?? '';

          if (entity1.isNotEmpty && relation.isNotEmpty && entity2.isNotEmpty) {
            triples.add(SemanticTriple(
              subject: entity1,
              predicate: relation,
              object: entity2,
              confidence: confidence,
              sourceContext: analysis.content,
              supportingEvidence: [evidence],
              attributes: {
                'extraction_method': 'entity_relation',
                'source_emotion': analysis.emotion,
              },
            ));
          }
        }
      }

      return triples;

    } catch (e) {
      print('[SemanticGraphBuilder] ❌ 构建实体关系三元组失败: $e');
      return [];
    }
  }

  /// 存储三元组
  void _storeTriple(SemanticTriple triple) {
    _triples[triple.id] = triple;

    // 更新索引
    _entityIndex.putIfAbsent(triple.subject, () => {}).add(triple.id);
    _entityIndex.putIfAbsent(triple.object, () => {}).add(triple.id);
    _predicateIndex.putIfAbsent(triple.predicate, () => {}).add(triple.id);

    _tripleUpdatesController.add(triple);
  }

  /// 添加语义三元组（新增方法）
  Future<void> addTriple(String subject, String predicate, String object) async {
    if (!_initialized) await initialize();

    try {
      // 创建三元组
      final triple = SemanticTriple(
        subject: subject,
        predicate: predicate,
        object: object,
        confidence: 0.8,
        sourceContext: 'manual_add',
        attributes: {'manual_add': true},
      );

      // 检查是否已存在
      if (!_triples.containsKey(triple.id)) {
        _triples[triple.id] = triple;

        // 更新索引
        _updateEntityIndex(subject, triple.id);
        _updateEntityIndex(object, triple.id);
        _updatePredicateIndex(predicate, triple.id);

        _tripleUpdatesController.add(triple);
        print('[SemanticGraphBuilder] ➕ 添加三元组: $subject -> $predicate -> $object');
      }
    } catch (e) {
      print('[SemanticGraphBuilder] ❌ 添加三元组失败: $e');
    }
  }

  /// 清除所有三元组（新增方法）
  Future<void> clearAllTriples() async {
    try {
      _triples.clear();
      _entityIndex.clear();
      _predicateIndex.clear();
      print('[SemanticGraphBuilder] 🧹 已清除所有三元组');
    } catch (e) {
      print('[SemanticGraphBuilder] ❌ 清除三元组失败: $e');
    }
  }

  /// 更新实体索引
  void _updateEntityIndex(String entity, String tripleId) {
    _entityIndex.putIfAbsent(entity, () => <String>{}).add(tripleId);
  }

  /// 更新谓词索引
  void _updatePredicateIndex(String predicate, String tripleId) {
    _predicateIndex.putIfAbsent(predicate, () => <String>{}).add(tripleId);
  }

  /// 检查是否为重复三元组
  bool _isDuplicateTriple(SemanticTriple newTriple) {
    return _triples.values.any((existing) {
      final subjectSimilarity = _calculateSimilarity(existing.subject, newTriple.subject);
      final predicateSimilarity = _calculateSimilarity(existing.predicate, newTriple.predicate);
      final objectSimilarity = _calculateSimilarity(existing.object, newTriple.object);

      return subjectSimilarity > 0.9 && predicateSimilarity > 0.9 && objectSimilarity > 0.9;
    });
  }

  /// 简单的字符串相似性计算
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    if (str1.isEmpty || str2.isEmpty) return 0.0;

    final words1 = str1.toLowerCase().split(' ').toSet();
    final words2 = str2.toLowerCase().split(' ').toSet();

    final intersection = words1.intersection(words2);
    final union = words1.union(words2);

    return intersection.length / union.length;
  }

  /// 查询三元组
  List<SemanticTriple> queryTriples({
    String? subject,
    String? predicate,
    String? object,
    double minConfidence = 0.0,
  }) {
    var results = _triples.values.where((triple) => triple.confidence >= minConfidence);

    if (subject != null) {
      results = results.where((triple) => triple.subject.contains(subject));
    }

    if (predicate != null) {
      results = results.where((triple) => triple.predicate.contains(predicate));
    }

    if (object != null) {
      results = results.where((triple) => triple.object.contains(object));
    }

    return results.toList()..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  /// 获取实体的所有关系
  List<SemanticTriple> getEntityRelations(String entity) {
    final tripleIds = <String>{};
    tripleIds.addAll(_entityIndex[entity] ?? {});

    return tripleIds.map((id) => _triples[id]).where((triple) => triple != null).cast<SemanticTriple>().toList();
  }

  /// 获取谓词的所有实例
  List<SemanticTriple> getPredicateInstances(String predicate) {
    final tripleIds = _predicateIndex[predicate] ?? {};
    return tripleIds.map((id) => _triples[id]).where((triple) => triple != null).cast<SemanticTriple>().toList();
  }

  /// 路径查询（查找两个实体间的路径）
  List<List<SemanticTriple>> findPath(String fromEntity, String toEntity, {int maxDepth = 3}) {
    final paths = <List<SemanticTriple>>[];
    final visited = <String>{};

    _findPathRecursive(fromEntity, toEntity, [], paths, visited, maxDepth);

    return paths;
  }

  /// 递归查找路径
  void _findPathRecursive(
    String current,
    String target,
    List<SemanticTriple> currentPath,
    List<List<SemanticTriple>> allPaths,
    Set<String> visited,
    int remainingDepth,
  ) {
    if (remainingDepth <= 0 || visited.contains(current)) return;

    visited.add(current);

    final currentRelations = getEntityRelations(current);

    for (final triple in currentRelations) {
      final nextEntity = triple.subject == current ? triple.object : triple.subject;
      final newPath = [...currentPath, triple];

      if (nextEntity == target) {
        allPaths.add(newPath);
      } else if (remainingDepth > 1) {
        _findPathRecursive(nextEntity, target, newPath, allPaths, visited, remainingDepth - 1);
      }
    }

    visited.remove(current);
  }

  /// 图谱聚合分析
  Map<String, dynamic> performGraphAnalysis() {
    final entityFrequency = <String, int>{};
    final predicateFrequency = <String, int>{};
    final confidenceDistribution = <String, int>{};

    for (final triple in _triples.values) {
      entityFrequency[triple.subject] = (entityFrequency[triple.subject] ?? 0) + 1;
      entityFrequency[triple.object] = (entityFrequency[triple.object] ?? 0) + 1;
      predicateFrequency[triple.predicate] = (predicateFrequency[triple.predicate] ?? 0) + 1;

      final confidenceRange = _getConfidenceRange(triple.confidence);
      confidenceDistribution[confidenceRange] = (confidenceDistribution[confidenceRange] ?? 0) + 1;
    }

    // 找出核心实体（出现频率最高的实体）
    final coreEntities = entityFrequency.entries
        .where((entry) => entry.value >= 3)
        .map((entry) => entry.key)
        .toList();

    // 找出关键谓词
    final keyPredicates = predicateFrequency.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toList();

    return {
      'total_triples': _triples.length,
      'unique_entities': entityFrequency.length,
      'unique_predicates': predicateFrequency.length,
      'core_entities': coreEntities,
      'key_predicates': keyPredicates,
      'entity_frequency': entityFrequency,
      'predicate_frequency': predicateFrequency,
      'confidence_distribution': confidenceDistribution,
      'average_confidence': _triples.isEmpty ? 0.0 :
          _triples.values.map((t) => t.confidence).reduce((a, b) => a + b) / _triples.length,
      'last_update': DateTime.now().toIso8601String(),
    };
  }

  /// 获取置信度范围
  String _getConfidenceRange(double confidence) {
    if (confidence >= 0.8) return 'high';
    if (confidence >= 0.6) return 'medium';
    if (confidence >= 0.4) return 'low';
    return 'very_low';
  }

  /// 启动定期图谱整合
  void _startPeriodicConsolidation() {
    _consolidationTimer = Timer.periodic(Duration(hours: 6), (timer) {
      _performGraphConsolidation();
    });
  }

  /// 执行图谱整合
  Future<void> _performGraphConsolidation() async {
    print('[SemanticGraphBuilder] 🔄 开始图谱整合...');

    try {
      // 1. 合并相似三元组
      await _mergeSimilarTriples();

      // 2. 清理低置信度三元组
      _cleanupLowConfidenceTriples();

      // 3. 更新实体统计
      _updateEntityStatistics();

      print('[SemanticGraphBuilder] ✅ 图谱整合完成');

    } catch (e) {
      print('[SemanticGraphBuilder] ❌ 图谱整合失败: $e');
    }
  }

  /// 合并相似三元组
  Future<void> _mergeSimilarTriples() async {
    final triplesToMerge = <String, List<SemanticTriple>>{};

    for (final triple in _triples.values) {
      final signature = '${triple.subject}_${triple.predicate}_${triple.object}';
      triplesToMerge.putIfAbsent(signature, () => []).add(triple);
    }

    for (final entry in triplesToMerge.entries) {
      if (entry.value.length > 1) {
        final mergedTriple = _mergeTriples(entry.value);

        // 移除旧三元组
        for (final oldTriple in entry.value) {
          _triples.remove(oldTriple.id);
        }

        // 添加合并后的三元组
        _storeTriple(mergedTriple);
      }
    }
  }

  /// 合并多个三元组
  SemanticTriple _mergeTriples(List<SemanticTriple> triples) {
    final first = triples.first;
    final allEvidence = <String>[];
    final allAttributes = <String, dynamic>{};

    double totalConfidence = 0.0;
    for (final triple in triples) {
      totalConfidence += triple.confidence;
      allEvidence.addAll(triple.supportingEvidence);
      allAttributes.addAll(triple.attributes);
    }

    return SemanticTriple(
      subject: first.subject,
      predicate: first.predicate,
      object: first.object,
      confidence: totalConfidence / triples.length,
      sourceContext: '合并的三元组',
      supportingEvidence: allEvidence.toSet().toList(),
      attributes: {
        ...allAttributes,
        'merged_count': triples.length,
        'merged_at': DateTime.now().toIso8601String(),
      },
    );
  }

  /// 清理低置信度三元组
  void _cleanupLowConfidenceTriples() {
    final toRemove = <String>[];

    for (final entry in _triples.entries) {
      if (entry.value.confidence < 0.2) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      _triples.remove(id);
    }

    if (toRemove.isNotEmpty) {
      print('[SemanticGraphBuilder] 🧹 清理了 ${toRemove.length} 个低置信度三元组');
    }
  }

  /// 更新实体统计
  void _updateEntityStatistics() {
    // 重建索引
    _entityIndex.clear();
    _predicateIndex.clear();

    for (final triple in _triples.values) {
      _entityIndex.putIfAbsent(triple.subject, () => {}).add(triple.id);
      _entityIndex.putIfAbsent(triple.object, () => {}).add(triple.id);
      _predicateIndex.putIfAbsent(triple.predicate, () => {}).add(triple.id);
    }
  }

  /// 获取最近的三元组
  List<SemanticTriple> getRecentTriples({int limit = 20}) {
    final sortedTriples = _triples.values.toList();
    sortedTriples.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sortedTriples.take(limit).toList();
  }

  /// 获取图谱统计信息
  Map<String, dynamic> getGraphStatistics() {
    return performGraphAnalysis();
  }

  /// 导出图谱数据
  Map<String, dynamic> exportGraph() {
    return {
      'triples': _triples.values.map((t) => t.toJson()).toList(),
      'entity_index': _entityIndex.map((k, v) => MapEntry(k, v.toList())),
      'predicate_index': _predicateIndex.map((k, v) => MapEntry(k, v.toList())),
      'exported_at': DateTime.now().toIso8601String(),
    };
  }

  /// 释放资源
  void dispose() {
    _consolidationTimer?.cancel();
    _tripleUpdatesController.close();
    _triples.clear();
    _entityIndex.clear();
    _predicateIndex.clear();
    _initialized = false;
    print('[SemanticGraphBuilder] 🔌 语义图谱构建器已释放');
  }
}
