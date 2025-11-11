import 'dart:math';
import 'package:app/models/graph_models.dart';
import 'package:app/services/embedding_service.dart';
import 'package:app/services/objectbox_service.dart';

/// 事件节点动态优先级评分服务
/// 实现基于时间衰减、再激活信号、语义相似度和图结构注意力扩散的综合评分机制
class EventPriorityScoringService {
  static final EventPriorityScoringService _instance = EventPriorityScoringService._internal();
  factory EventPriorityScoringService() => _instance;
  EventPriorityScoringService._internal();

  // 可配置参数
  // 时间衰减参数
  double lambda = 0.01;  // 时间衰减系数 λ ∈ [0.005, 0.02]
  double temporalBoost = 1.0;  // 相对时间表达式时的临时增强因子

  // 再激活信号参数
  double alpha = 1.0;  // 激活强度系数
  double beta = 0.01;  // 遗忘速度系数

  // 图扩散参数
  double gamma = 0.5;  // 扩散衰减因子
  int maxHops = 1;  // 最大跳数（K-hop限制）

  // 权重组合参数（初始建议值）
  double theta1 = 0.3;  // f_time 权重
  double theta2 = 0.4;  // f_react 权重
  double theta3 = 0.2;  // f_sem 权重
  double theta4 = 0.1;  // f_diff 权重

  // 排序策略
  ScoringStrategy strategy = ScoringStrategy.multiplicative;

  final EmbeddingService _embeddingService = EmbeddingService();
  final ObjectBoxService _objectBox = ObjectBoxService();

  /// 1. 时间衰减（Temporal Attentional Decay）
  /// f_time = exp(-λ * Δt)
  /// Δt = now - t_node (单位：天)
  double calculateTemporalDecay(EventNode node, {DateTime? now}) {
    now ??= DateTime.now();
    
    // 使用事件的最后访问时间或创建时间
    final nodeTime = node.lastSeenTime ?? node.startTime ?? node.lastUpdated;
    final deltaTime = now.difference(nodeTime);
    final deltaDays = deltaTime.inHours / 24.0;  // 转换为天数

    // 应用时间衰减公式
    final decay = exp(-lambda * deltaDays);
    
    return decay * temporalBoost;
  }

  /// 2. 再激活信号（Contextual Reinstatement）
  /// f_react = Σ α * exp(-β * Δt_react,i)
  double calculateReactivationSignal(EventNode node, {DateTime? now}) {
    now ??= DateTime.now();
    
    final activations = node.activationHistory;
    if (activations.isEmpty) return 0.0;

    double reactScore = 0.0;
    for (final activation in activations) {
      try {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(
          activation['timestamp'] as int
        );
        final similarity = (activation['similarity'] as num?)?.toDouble() ?? 1.0;
        
        final deltaTime = now.difference(timestamp);
        final deltaDays = deltaTime.inHours / 24.0;
        
        // 可以让 α 与召回相似度成比例
        final alphaScaled = alpha * similarity;
        reactScore += alphaScaled * exp(-beta * deltaDays);
      } catch (e) {
        // 忽略格式错误的激活记录
        continue;
      }
    }

    return reactScore;
  }

  /// 3. 语义相似度（Semantic Alignment）
  /// f_sem = cos(v_q, v_node)
  /// 将余弦相似度从 [-1,1] 线性缩放到 [0,1]
  double calculateSemanticSimilarity(List<double> queryVector, EventNode node) {
    if (node.embedding.isEmpty) return 0.0;
    
    try {
      final cosine = _embeddingService.calculateCosineSimilarity(queryVector, node.embedding);
      // 线性缩放到 [0,1]
      return (cosine + 1.0) / 2.0;
    } catch (e) {
      print('[EventPriorityScoring] 计算语义相似度错误: $e');
      return 0.0;
    }
  }

  /// 4. 注意力扩散（Attention Diffusion via Graph）
  /// f_diff(u) = Σ_{v∈N(u)} w_uv * P(v)
  /// 利用图结构把注意力从被激活节点扩散到其邻居
  Future<double> calculateAttentionDiffusion(
    EventNode node,
    Map<String, double> nodePriorityMap,
  ) async {
    try {
      // 获取节点的邻居（通过事件关系）
      final relations = _objectBox.queryEventRelations(sourceEventId: node.id);
      
      double diffusionScore = 0.0;
      int neighborCount = 0;

      for (final relation in relations) {
        // 获取邻居的优先级分数
        final neighborPriority = nodePriorityMap[relation.targetEventId] ?? 0.0;
        
        // 边权重：基于边类型
        final edgeWeight = _getEdgeWeight(relation.relationType);
        
        // 累加扩散分数（应用衰减）
        diffusionScore += edgeWeight * neighborPriority * gamma;
        neighborCount++;
      }

      // 平均扩散分数（避免度数过大的节点得分过高）
      return neighborCount > 0 ? diffusionScore / neighborCount : 0.0;
    } catch (e) {
      print('[EventPriorityScoring] 计算注意力扩散错误: $e');
      return 0.0;
    }
  }

  /// 获取边类型对应的权重
  double _getEdgeWeight(String relationType) {
    // 不同关系类型的权重
    switch (relationType) {
      case EventRelation.RELATION_REVISIT:
      case EventRelation.RELATION_PROGRESS_OF:
        return 1.0;  // 重访和进展关系权重最高
      case EventRelation.RELATION_CAUSAL:
        return 0.8;  // 因果关系次之
      case EventRelation.RELATION_TEMPORAL:
        return 0.6;  // 时间顺序关系
      case EventRelation.RELATION_CONTAINS:
        return 0.7;  // 包含关系
      default:
        return 0.5;  // 其他关系
    }
  }

  /// 5. 综合计算优先级分数
  /// P_tilde = θ1*f_time + θ2*f_react + θ3*f_sem + θ4*f_diff
  Future<double> calculatePriorityScore({
    required EventNode node,
    required List<double> queryVector,
    Map<String, double>? nodePriorityMap,
    DateTime? now,
  }) async {
    final fTime = calculateTemporalDecay(node, now: now);
    final fReact = calculateReactivationSignal(node, now: now);
    final fSem = calculateSemanticSimilarity(queryVector, node);
    
    // 图扩散需要整体的优先级映射，如果没有提供则跳过
    double fDiff = 0.0;
    if (nodePriorityMap != null) {
      fDiff = await calculateAttentionDiffusion(node, nodePriorityMap);
    }

    final pTilde = theta1 * fTime + theta2 * fReact + theta3 * fSem + theta4 * fDiff;
    
    return pTilde;
  }

  /// 批量计算所有候选节点的优先级分数（支持图扩散）
  Future<Map<String, double>> calculateBatchPriorityScores({
    required List<EventNode> nodes,
    required List<double> queryVector,
    DateTime? now,
    bool enableDiffusion = true,
  }) async {
    final priorityMap = <String, double>{};
    
    // 第一轮：计算基础分数（不含图扩散）
    for (final node in nodes) {
      final score = await calculatePriorityScore(
        node: node,
        queryVector: queryVector,
        now: now,
      );
      priorityMap[node.id] = score;
    }

    // 第二轮：如果启用图扩散，更新分数
    if (enableDiffusion && theta4 > 0) {
      final updatedMap = <String, double>{};
      for (final node in nodes) {
        final fTime = calculateTemporalDecay(node, now: now);
        final fReact = calculateReactivationSignal(node, now: now);
        final fSem = calculateSemanticSimilarity(queryVector, node);
        final fDiff = await calculateAttentionDiffusion(node, priorityMap);
        
        final pTilde = theta1 * fTime + theta2 * fReact + theta3 * fSem + theta4 * fDiff;
        updatedMap[node.id] = pTilde;
      }
      return updatedMap;
    }

    return priorityMap;
  }

  /// 使用优先级分数对事件进行排序
  /// 策略A：Softmax归一化后的注意力分布
  /// 策略B：直接乘法 score = cos(v_q, v_node) * (1 + P_tilde)
  Future<List<Map<String, dynamic>>> rankEventsByPriority({
    required List<EventNode> candidates,
    required List<double> queryVector,
    DateTime? now,
    int topK = 10,
    bool enableDiffusion = true,
  }) async {
    if (candidates.isEmpty) return [];

    // 批量计算优先级分数
    final priorityScores = await calculateBatchPriorityScores(
      nodes: candidates,
      queryVector: queryVector,
      now: now,
      enableDiffusion: enableDiffusion,
    );

    // 计算每个候选节点的最终排序分数
    final results = <Map<String, dynamic>>[];
    for (final node in candidates) {
      final pTilde = priorityScores[node.id] ?? 0.0;
      final cosineSim = _embeddingService.calculateCosineSimilarity(queryVector, node.embedding);
      
      double finalScore;
      if (strategy == ScoringStrategy.multiplicative) {
        // 策略B：乘法增强
        finalScore = cosineSim * (1.0 + pTilde);
      } else {
        // 策略A：Softmax（需要所有分数计算后归一化，这里先用原始分数）
        finalScore = pTilde;
      }

      results.add({
        'event': node,
        'priority_score': pTilde,
        'cosine_similarity': cosineSim,
        'final_score': finalScore,
        'components': {
          'f_time': calculateTemporalDecay(node, now: now),
          'f_react': calculateReactivationSignal(node, now: now),
          'f_sem': calculateSemanticSimilarity(queryVector, node),
        },
      });
    }

    // 如果使用Softmax策略，进行归一化
    if (strategy == ScoringStrategy.softmax) {
      _applySoftmax(results);
    }

    // 按最终分数降序排序
    results.sort((a, b) => (b['final_score'] as double).compareTo(a['final_score'] as double));

    // 返回前K个结果
    return results.take(topK).toList();
  }

  /// 应用Softmax归一化
  void _applySoftmax(List<Map<String, dynamic>> results) {
    if (results.isEmpty) return;

    final scores = results.map((r) => r['priority_score'] as double).toList();
    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    
    // 计算 exp(score - maxScore) 以提高数值稳定性
    final expScores = scores.map((s) => exp(s - maxScore)).toList();
    final sumExp = expScores.reduce((a, b) => a + b);
    
    // 归一化并更新 final_score
    for (int i = 0; i < results.length; i++) {
      final attention = expScores[i] / sumExp;
      final cosineSim = results[i]['cosine_similarity'] as double;
      results[i]['final_score'] = cosineSim * attention;
      results[i]['attention_weight'] = attention;
    }
  }

  /// 检测查询中的相对时间表达式，并临时调整 lambda
  void detectAndBoostTemporalExpression(String query) {
    // 中文相对时间表达式
    final temporalExpressions = [
      '昨天', '今天', '明天', '刚才', '刚刚', 
      '上周', '本周', '下周', '上月', '本月', '下月',
      '最近', '近期', '早上', '中午', '晚上', '前天', '后天'
    ];

    bool hasTemporalExpression = false;
    for (final expr in temporalExpressions) {
      if (query.contains(expr)) {
        hasTemporalExpression = true;
        break;
      }
    }

    if (hasTemporalExpression) {
      // 临时放大 lambda（增加时间衰减的敏感度）
      lambda = lambda * 3.0;
      temporalBoost = 2.0;
      print('[EventPriorityScoring] 检测到相对时间表达式，lambda临时调整为 $lambda，boost调整为 $temporalBoost');
    } else {
      // 重置为默认值
      lambda = 0.01;
      temporalBoost = 1.0;
    }
  }

  /// 记录节点被召回并判定为相关时的激活事件
  Future<void> recordActivation({
    required EventNode node,
    required double similarity,
    EventNode? relatedOldNode,
  }) async {
    try {
      // 添加激活记录
      node.addActivation(
        timestamp: DateTime.now(),
        similarity: similarity,
      );
      
      // 更新最后访问时间
      node.lastSeenTime = DateTime.now();
      
      // 保存到数据库
      _objectBox.updateEventNode(node);

      // 如果有旧节点，建立 revisit 或 progress_of 关系
      if (relatedOldNode != null) {
        await _createRevisitRelation(oldNode: relatedOldNode, newNode: node);
      }

      print('[EventPriorityScoring] 记录节点激活: ${node.name}, similarity=$similarity');
    } catch (e) {
      print('[EventPriorityScoring] 记录激活失败: $e');
    }
  }

  /// 创建 revisit/progress_of 关系边
  Future<void> _createRevisitRelation({
    required EventNode oldNode,
    required EventNode newNode,
  }) async {
    try {
      // 检查是否已存在该关系
      final existingRelations = _objectBox.queryEventRelations(
        sourceEventId: oldNode.id,
      );
      
      final alreadyExists = existingRelations.any(
        (r) => r.targetEventId == newNode.id && 
               (r.relationType == EventRelation.RELATION_REVISIT || 
                r.relationType == EventRelation.RELATION_PROGRESS_OF)
      );

      if (!alreadyExists) {
        // 创建新的关系
        final relation = EventRelation(
          sourceEventId: oldNode.id,
          targetEventId: newNode.id,
          relationType: EventRelation.RELATION_REVISIT,
          description: '从旧事件重访/进展到新事件',
        );
        
        _objectBox.insertEventRelation(relation);
        print('[EventPriorityScoring] 创建revisit关系: ${oldNode.name} -> ${newNode.name}');
      }
    } catch (e) {
      print('[EventPriorityScoring] 创建revisit关系失败: $e');
    }
  }

  /// 诊断：分析优先级分数分布
  Future<Map<String, dynamic>> analyzePriorityDistribution({
    required List<EventNode> nodes,
    required List<double> queryVector,
  }) async {
    if (nodes.isEmpty) {
      return {'error': '节点列表为空'};
    }

    final scores = await calculateBatchPriorityScores(
      nodes: nodes,
      queryVector: queryVector,
      enableDiffusion: true,
    );

    final scoreValues = scores.values.toList()..sort();
    
    return {
      'total_nodes': nodes.length,
      'min_score': scoreValues.isNotEmpty ? scoreValues.first : 0.0,
      'max_score': scoreValues.isNotEmpty ? scoreValues.last : 0.0,
      'avg_score': scoreValues.isNotEmpty 
        ? scoreValues.reduce((a, b) => a + b) / scoreValues.length 
        : 0.0,
      'median_score': scoreValues.isNotEmpty 
        ? scoreValues[scoreValues.length ~/ 2] 
        : 0.0,
      'score_distribution': {
        'low (< 0.2)': scoreValues.where((s) => s < 0.2).length,
        'medium (0.2-0.5)': scoreValues.where((s) => s >= 0.2 && s < 0.5).length,
        'high (0.5-0.8)': scoreValues.where((s) => s >= 0.5 && s < 0.8).length,
        'very_high (>= 0.8)': scoreValues.where((s) => s >= 0.8).length,
      },
    };
  }

  /// 更新配置参数
  void updateParameters({
    double? lambda,
    double? alpha,
    double? beta,
    double? gamma,
    double? theta1,
    double? theta2,
    double? theta3,
    double? theta4,
    ScoringStrategy? strategy,
  }) {
    if (lambda != null) this.lambda = lambda;
    if (alpha != null) this.alpha = alpha;
    if (beta != null) this.beta = beta;
    if (gamma != null) this.gamma = gamma;
    if (theta1 != null) this.theta1 = theta1;
    if (theta2 != null) this.theta2 = theta2;
    if (theta3 != null) this.theta3 = theta3;
    if (theta4 != null) this.theta4 = theta4;
    if (strategy != null) this.strategy = strategy;
    
    print('[EventPriorityScoring] 参数已更新');
  }

  /// 获取当前配置
  Map<String, dynamic> getConfiguration() {
    return {
      'temporal_decay': {'lambda': lambda, 'boost': temporalBoost},
      'reactivation': {'alpha': alpha, 'beta': beta},
      'graph_diffusion': {'gamma': gamma, 'max_hops': maxHops},
      'weights': {
        'theta1_time': theta1,
        'theta2_react': theta2,
        'theta3_sem': theta3,
        'theta4_diff': theta4,
      },
      'strategy': strategy.toString(),
    };
  }
}

/// 排序策略枚举
enum ScoringStrategy {
  softmax,         // 策略A：Softmax归一化注意力分布
  multiplicative,  // 策略B：乘法增强 score = cos * (1 + P)
}
