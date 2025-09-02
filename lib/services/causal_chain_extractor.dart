/// 因果链提取器
/// 负责从用户对话中提取因果关系、动机和触发因子

import 'dart:async';
import 'dart:convert';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';

class CausalChainExtractor {
  static final CausalChainExtractor _instance = CausalChainExtractor._internal();
  factory CausalChainExtractor() => _instance;
  CausalChainExtractor._internal();

  final List<CausalRelation> _causalRelations = [];
  final StreamController<CausalRelation> _causalUpdatesController = StreamController.broadcast();

  Timer? _cleanupTimer;
  bool _initialized = false;

  /// 因果关系更新流
  Stream<CausalRelation> get causalUpdates => _causalUpdatesController.stream;

  /// 初始化提取器
  Future<void> initialize() async {
    if (_initialized) return;

    print('[CausalChainExtractor] 🚀 初始化因果链提取器...');

    // 启动定期清理
    _startPeriodicCleanup();

    _initialized = true;
    print('[CausalChainExtractor] ✅ 因果链提取器初始化完成');
  }

  /// 处理对话内容，提取因果关系
  Future<List<CausalRelation>> extractCausalRelations(SemanticAnalysisInput analysis) async {
    if (!_initialized) await initialize();

    print('[CausalChainExtractor] 🔗 分析因果关系: "${analysis.content.substring(0, analysis.content.length > 50 ? 50 : analysis.content.length)}..."');

    try {
      // 1. 提取显式因果关系
      final explicitRelations = await _extractExplicitCausalRelations(analysis);

      // 2. 推断隐式因果关系
      final implicitRelations = await _inferImplicitCausalRelations(analysis);

      // 3. 识别动机链条
      final motivationChains = await _extractMotivationChains(analysis);

      // 4. 合并所有因果关系
      final allRelations = <CausalRelation>[];
      allRelations.addAll(explicitRelations);
      allRelations.addAll(implicitRelations);
      allRelations.addAll(motivationChains);

      // 5. 存储新的因果关系
      for (final relation in allRelations) {
        if (!_isDuplicateRelation(relation)) {
          _causalRelations.add(relation);
          _causalUpdatesController.add(relation);
        }
      }

      print('[CausalChainExtractor] ✅ 提取完成，新增 ${allRelations.length} 个因果关系');

      return allRelations;

    } catch (e) {
      print('[CausalChainExtractor] ❌ 提取因果关系失败: $e');
      return [];
    }
  }

  /// 提取显式因果关系
  Future<List<CausalRelation>> _extractExplicitCausalRelations(SemanticAnalysisInput analysis) async {
    final explicitCausalPrompt = '''
你是一个因果关系识别专家。请从用户的对话中识别明确的因果关系表述。

【识别重点】：
1. 寻找因果关系指示词：因为、所以、由于、导致、造成、引起、结果、因此、故而等
2. 识别条件关系：如果...那么、只要...就、除非...否则等
3. 识别时间序列中的因果：先...后...、在...之后等
4. 识别目的关系：为了...、打算...、希望通过...等

【因果关系类型】：
- direct_cause: 直接因果（A直接导致B）
- indirect_cause: 间接因果（A通过中介导致B）
- enabler: 使能条件（A使B成为可能）
- inhibitor: 抑制条件（A阻止B发生）
- correlation: 相关性（A和B相关但不确定因果）

输出格式为JSON数组：
[
  {
    "cause": "原因描述",
    "effect": "结果描述", 
    "type": "因果关系类型",
    "confidence": 0.8,
    "evidence_phrases": ["支持这个因果关系的短语"],
    "involved_entities": ["涉及的实体"],
    "context": {
      "temporal_order": "时间顺序信息",
      "emotional_context": "情感背景"
    }
  }
]

如��没有明确的因果关系，返回空数组 []。

用户对话：
"${analysis.content}"

检测到的实体：${analysis.entities}
检测到的情绪：${analysis.emotion}
''';

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: explicitCausalPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) {
        return [];
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> relationsData = jsonDecode(jsonStr);

      final relations = <CausalRelation>[];
      for (final relationData in relationsData) {
        if (relationData is Map) {
          final cause = relationData['cause']?.toString() ?? '';
          final effect = relationData['effect']?.toString() ?? '';
          final typeStr = relationData['type']?.toString() ?? 'direct_cause';
          final confidence = (relationData['confidence'] as num?)?.toDouble() ?? 0.5;
          final evidencePhrases = (relationData['evidence_phrases'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final involvedEntities = (relationData['involved_entities'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final context = (relationData['context'] as Map?) ?? {};

          if (cause.isNotEmpty && effect.isNotEmpty) {
            final relation = CausalRelation(
              cause: cause,
              effect: effect,
              type: _parseCausalRelationType(typeStr),
              confidence: confidence,
              sourceText: analysis.content,
              involvedEntities: involvedEntities,
              context: {
                'evidence_phrases': evidencePhrases,
                'extraction_type': 'explicit',
                'source_emotion': analysis.emotion,
                ...context,
              },
            );

            relations.add(relation);
            print('[CausalChainExtractor] 🔗 显式因果关系: $cause -> $effect');
          }
        }
      }

      return relations;

    } catch (e) {
      print('[CausalChainExtractor] ❌ 提取显式因果关系失败: $e');
      return [];
    }
  }

  /// 推断隐式因果关系
  Future<List<CausalRelation>> _inferImplicitCausalRelations(SemanticAnalysisInput analysis) async {
    final implicitCausalPrompt = '''
你是一个隐式因果关系推理专家。请从用户对话中推断可能的隐式因果关系。

【推理原则】：
1. 基于常识和逻辑推理
2. 考虑情感状态变化的原因
3. 分析行为动机和目���
4. 识别问题-解决方案关系
5. 只推断高置信度的因果关系

【推理场景】：
- 情绪变化：用户表达某种情绪，推断可能的触发原因
- 行为决策：用户做出某个决定，推断背后的动机
- 问题困扰：用户提到问题，推断可能的根本原因
- 计划制定：用户制定计划，推断驱动因素

输出格式为JSON数组：
[
  {
    "cause": "推断的原因",
    "effect": "观察到的结果",
    "type": "因果关系类型", 
    "confidence": 0.6,
    "reasoning": "推理过程说明",
    "involved_entities": ["涉及的实体"],
    "uncertainty_factors": ["不确定性因素"]
  }
]

注意：只输出置信度 > 0.5 的推断结果。

用户对话：
"${analysis.content}"

检测到的实体：${analysis.entities}
检测到的情绪：${analysis.emotion}
''';

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: implicitCausalPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) {
        return [];
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> relationsData = jsonDecode(jsonStr);

      final relations = <CausalRelation>[];
      for (final relationData in relationsData) {
        if (relationData is Map) {
          final cause = relationData['cause']?.toString() ?? '';
          final effect = relationData['effect']?.toString() ?? '';
          final typeStr = relationData['type']?.toString() ?? 'correlation';
          final confidence = (relationData['confidence'] as num?)?.toDouble() ?? 0.5;
          final reasoning = relationData['reasoning']?.toString() ?? '';
          final involvedEntities = (relationData['involved_entities'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final uncertaintyFactors = (relationData['uncertainty_factors'] as List?)?.map((e) => e.toString()).toList() ?? [];

          if (cause.isNotEmpty && effect.isNotEmpty && confidence > 0.5) {
            final relation = CausalRelation(
              cause: cause,
              effect: effect,
              type: _parseCausalRelationType(typeStr),
              confidence: confidence,
              sourceText: analysis.content,
              involvedEntities: involvedEntities,
              context: {
                'extraction_type': 'implicit',
                'reasoning': reasoning,
                'uncertainty_factors': uncertaintyFactors,
                'source_emotion': analysis.emotion,
              },
            );

            relations.add(relation);
            print('[CausalChainExtractor] 🧠 隐式因果关系: $cause -> $effect (推理)');
          }
        }
      }

      return relations;

    } catch (e) {
      print('[CausalChainExtractor] ❌ 推断隐式因果关系失败: $e');
      return [];
    }
  }

  /// 提取动机链条
  Future<List<CausalRelation>> _extractMotivationChains(SemanticAnalysisInput analysis) async {
    final motivationPrompt = '''
你是一个动机分析专家。请从用户对话中识别动机链条和深层驱动因素。

【动机分析维度】：
1. 需求层次：生理需求、安全需求、社交需求、尊重需求、自我实现需求
2. 情感驱动：追求快乐、避免痛苦、寻求认同、恐惧焦虑等
3. 目标导向：短期目标、长期愿景、价值实现等
4. 外部压力：社会期望、时间压力、竞争压力等

【识别模式】：
- 目标-手段链：为了X，所以做Y
- 问题-动机链：因为遇到X问题，所以想要Y
- 价值-行为链：因为认为X重要，所以选择Y
- 情感-行为链：感到X情绪，所以倾向于Y

输出格式为JSON数组：
[
  {
    "deep_motivation": "深层动机/需求",
    "surface_behavior": "表面行为/表达", 
    "type": "enabler",
    "confidence": 0.7,
    "motivation_category": "需求类别",
    "emotional_driver": "情感驱动因素",
    "chain_depth": "动机链条深度（1-3）"
  }
]

用户对话：
"${analysis.content}"

检测到的实体：${analysis.entities}
检测到的情绪：${analysis.emotion}
''';

    try {
      final llm = await LLM.create('gpt-4-turbo-preview', systemPrompt: motivationPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) {
        return [];
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> motivationsData = jsonDecode(jsonStr);

      final relations = <CausalRelation>[];
      for (final motivationData in motivationsData) {
        if (motivationData is Map) {
          final deepMotivation = motivationData['deep_motivation']?.toString() ?? '';
          final surfaceBehavior = motivationData['surface_behavior']?.toString() ?? '';
          final typeStr = motivationData['type']?.toString() ?? 'enabler';
          final confidence = (motivationData['confidence'] as num?)?.toDouble() ?? 0.5;
          final motivationCategory = motivationData['motivation_category']?.toString() ?? '';
          final emotionalDriver = motivationData['emotional_driver']?.toString() ?? '';
          final chainDepth = motivationData['chain_depth']?.toString() ?? '1';

          if (deepMotivation.isNotEmpty && surfaceBehavior.isNotEmpty) {
            final relation = CausalRelation(
              cause: deepMotivation,
              effect: surfaceBehavior,
              type: _parseCausalRelationType(typeStr),
              confidence: confidence,
              sourceText: analysis.content,
              involvedEntities: analysis.entities,
              context: {
                'extraction_type': 'motivation',
                'motivation_category': motivationCategory,
                'emotional_driver': emotionalDriver,
                'chain_depth': chainDepth,
                'source_emotion': analysis.emotion,
              },
            );

            relations.add(relation);
            print('[CausalChainExtractor] 💡 动机链条: $deepMotivation -> $surfaceBehavior');
          }
        }
      }

      return relations;

    } catch (e) {
      print('[CausalChainExtractor] ❌ 提取动机链条失败: $e');
      return [];
    }
  }

  /// 解析因果关系类型
  CausalRelationType _parseCausalRelationType(String typeStr) {
    switch (typeStr.toLowerCase()) {
      case 'direct_cause':
        return CausalRelationType.directCause;
      case 'indirect_cause':
        return CausalRelationType.indirectCause;
      case 'enabler':
        return CausalRelationType.enabler;
      case 'inhibitor':
        return CausalRelationType.inhibitor;
      case 'correlation':
        return CausalRelationType.correlation;
      default:
        return CausalRelationType.directCause;
    }
  }

  /// 检查是否为重复的因果关系
  bool _isDuplicateRelation(CausalRelation newRelation) {
    return _causalRelations.any((existing) {
      final causeSimilarity = _calculateSimilarity(existing.cause, newRelation.cause);
      final effectSimilarity = _calculateSimilarity(existing.effect, newRelation.effect);
      return causeSimilarity > 0.8 && effectSimilarity > 0.8;
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

  /// 分析因果链条
  List<List<CausalRelation>> analyzeCausalChains() {
    final chains = <List<CausalRelation>>[];
    final processedRelations = <String>{};

    for (final relation in _causalRelations) {
      if (processedRelations.contains(relation.id)) continue;

      final chain = _buildCausalChain(relation, processedRelations);
      if (chain.length > 1) {
        chains.add(chain);
      }
    }

    return chains;
  }

  /// 构建因果链条
  List<CausalRelation> _buildCausalChain(CausalRelation startRelation, Set<String> processed) {
    final chain = <CausalRelation>[startRelation];
    processed.add(startRelation.id);

    // 向前追溯（找到导致当前原因的关系）
    var currentCause = startRelation.cause;
    while (true) {
      final precedingRelation = _causalRelations
          .where((r) => !processed.contains(r.id) && _isEffectSimilar(r.effect, currentCause))
          .firstOrNull;

      if (precedingRelation == null) break;

      chain.insert(0, precedingRelation);
      processed.add(precedingRelation.id);
      currentCause = precedingRelation.cause;
    }

    // 向后延伸（找到由当前结果导致的关系）
    var currentEffect = startRelation.effect;
    while (true) {
      final followingRelation = _causalRelations
          .where((r) => !processed.contains(r.id) && _isCauseSimilar(r.cause, currentEffect))
          .firstOrNull;

      if (followingRelation == null) break;

      chain.add(followingRelation);
      processed.add(followingRelation.id);
      currentEffect = followingRelation.effect;
    }

    return chain;
  }

  /// 检查效果是否相似
  bool _isEffectSimilar(String effect1, String effect2) {
    return _calculateSimilarity(effect1, effect2) > 0.7;
  }

  /// 检查原因是否相似
  bool _isCauseSimilar(String cause1, String cause2) {
    return _calculateSimilarity(cause1, cause2) > 0.7;
  }

  /// 获取最近的因果关系
  List<CausalRelation> getRecentCausalRelations({int limit = 10}) {
    final sortedRelations = List<CausalRelation>.from(_causalRelations);
    sortedRelations.sort((a, b) => b.extractedAt.compareTo(a.extractedAt));
    return sortedRelations.take(limit).toList();
  }

  /// 按类型获取因果关系
  List<CausalRelation> getCausalRelationsByType(CausalRelationType type) {
    return _causalRelations.where((relation) => relation.type == type).toList();
  }

  /// 搜索因果关系
  List<CausalRelation> searchCausalRelations(String query) {
    final queryLower = query.toLowerCase();
    return _causalRelations
        .where((relation) =>
            relation.cause.toLowerCase().contains(queryLower) ||
            relation.effect.toLowerCase().contains(queryLower) ||
            relation.involvedEntities.any((entity) => entity.toLowerCase().contains(queryLower)))
        .toList();
  }

  /// 获取涉及特定实体的因果关系
  List<CausalRelation> getCausalRelationsByEntity(String entity) {
    return _causalRelations
        .where((relation) => relation.involvedEntities.contains(entity))
        .toList();
  }

  /// 获取因果关系统计信息
  Map<String, dynamic> getCausalStatistics() {
    final typeDistribution = <String, int>{};
    final confidenceDistribution = <String, int>{};
    final extractionTypeDistribution = <String, int>{};

    for (final relation in _causalRelations) {
      final type = relation.type.toString().split('.').last;
      final confidenceRange = _getConfidenceRange(relation.confidence);
      final extractionType = relation.context['extraction_type']?.toString() ?? 'unknown';

      typeDistribution[type] = (typeDistribution[type] ?? 0) + 1;
      confidenceDistribution[confidenceRange] = (confidenceDistribution[confidenceRange] ?? 0) + 1;
      extractionTypeDistribution[extractionType] = (extractionTypeDistribution[extractionType] ?? 0) + 1;
    }

    final chains = analyzeCausalChains();

    return {
      'total_relations': _causalRelations.length,
      'causal_chains': chains.length,
      'longest_chain': chains.isEmpty ? 0 : chains.map((c) => c.length).reduce((a, b) => a > b ? a : b),
      'type_distribution': typeDistribution,
      'confidence_distribution': confidenceDistribution,
      'extraction_type_distribution': extractionTypeDistribution,
      'average_confidence': _causalRelations.isEmpty ? 0.0 :
          _causalRelations.map((r) => r.confidence).reduce((a, b) => a + b) / _causalRelations.length,
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

  /// 启动定期清理
  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(Duration(hours: 24), (timer) {
      _performCleanup();
    });
  }

  /// 执行清理操作
  void _performCleanup() {
    final now = DateTime.now();
    final cutoffDate = now.subtract(Duration(days: 30));

    final beforeCount = _causalRelations.length;
    _causalRelations.removeWhere((relation) => relation.extractedAt.isBefore(cutoffDate));
    final afterCount = _causalRelations.length;

    if (beforeCount != afterCount) {
      print('[CausalChainExtractor] 🧹 清理了 ${beforeCount - afterCount} 个过期因果关系');
    }
  }

  /// 释放资源
  void dispose() {
    _cleanupTimer?.cancel();
    _causalUpdatesController.close();
    _causalRelations.clear();
    _initialized = false;
    print('[CausalChainExtractor] 🔌 因果链提取器已释放');
  }
}

// 扩展方法
extension on Iterable<CausalRelation> {
  CausalRelation? get firstOrNull {
    return isEmpty ? null : first;
  }
}
