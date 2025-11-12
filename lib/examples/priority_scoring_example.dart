import 'package:app/services/event_priority_scoring_service.dart';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/services/embedding_service.dart';
import 'package:app/models/graph_models.dart';

/// 优先级评分系统使用示例
/// 
/// 本文件展示如何使用动态优先级评分系统进行事件检索和分析
void main() async {
  print('===== 优先级评分系统演示 =====\n');

  // 示例1: 基本使用 - 使用优先级评分检索事件
  await example1BasicUsage();

  // 示例2: 参数配置 - 自定义优先级评分参数
  await example2ParameterConfiguration();

  // 示例3: 时间敏感查询 - 演示自适应时间衰减
  await example3TemporalQuery();

  // 示例4: 激活记录 - 手动记录节点激活
  await example4ActivationTracking();

  // 示例5: 诊断分析 - 分析优先级分数分布
  await example5DiagnosticAnalysis();

  // 示例6: 对比测试 - 传统方法 vs 优先级评分
  await example6ComparisonTest();
}

/// 示例1: 基本使用
Future<void> example1BasicUsage() async {
  print('示例1: 基本使用\n');

  // 使用优先级评分检索（默认启用）
  final results = await KnowledgeGraphService.searchEventsByText(
    '昨天吃了什么',
    topK: 5,
    usePriorityScoring: true,
  );

  print('查询: "昨天吃了什么"');
  print('使用优先级评分，返回 ${results.length} 个结果:\n');

  for (int i = 0; i < results.length; i++) {
    final result = results[i];
    final event = result['event'] as EventNode;
    final priorityScore = result['priority_score'] as double;
    final finalScore = result['final_score'] as double;
    final components = result['components'] as Map<String, dynamic>;

    print('[$i] ${event.name}');
    print('    优先级分数: ${priorityScore.toStringAsFixed(4)}');
    print('    最终排序分数: ${finalScore.toStringAsFixed(4)}');
    print('    组件分解:');
    print('      - 时间衰减: ${components['f_time'].toStringAsFixed(4)}');
    print('      - 再激活: ${components['f_react'].toStringAsFixed(4)}');
    print('      - 语义: ${components['f_sem'].toStringAsFixed(4)}');
    print('');
  }

  print('---\n');
}

/// 示例2: 参数配置
Future<void> example2ParameterConfiguration() async {
  print('示例2: 参数配置\n');

  final priorityService = EventPriorityScoringService();

  // 查看默认配置
  print('默认配置:');
  var config = priorityService.getConfiguration();
  print('  时间衰减: λ=${config['temporal_decay']['lambda']}');
  print('  再激活: α=${config['reactivation']['alpha']}, β=${config['reactivation']['beta']}');
  print('  图扩散: γ=${config['graph_diffusion']['gamma']}');
  print('  权重: θ1=${config['weights']['theta1_time']}, θ2=${config['weights']['theta2_react']}, '
        'θ3=${config['weights']['theta3_sem']}, θ4=${config['weights']['theta4_diff']}');
  print('  策略: ${config['strategy']}');
  print('');

  // 自定义配置 - 强调时效性的场景
  print('调整为"强调时效性"配置:');
  priorityService.updateParameters(
    lambda: 0.02,       // 增大时间衰减系数
    theta1: 0.5,        // 提高时间权重
    theta2: 0.3,        // 降低再激活权重
    theta3: 0.15,       // 降低语义权重
    theta4: 0.05,       // 降低图扩散权重
    strategy: ScoringStrategy.multiplicative,
  );

  config = priorityService.getConfiguration();
  print('  时间衰减: λ=${config['temporal_decay']['lambda']}');
  print('  权重: θ1=${config['weights']['theta1_time']}, θ2=${config['weights']['theta2_react']}, '
        'θ3=${config['weights']['theta3_sem']}, θ4=${config['weights']['theta4_diff']}');
  print('');

  // 恢复默认配置
  priorityService.updateParameters(
    lambda: 0.01,
    theta1: 0.3,
    theta2: 0.4,
    theta3: 0.2,
    theta4: 0.1,
  );

  print('已恢复默认配置\n');
  print('---\n');
}

/// 示例3: 时间敏感查询
Future<void> example3TemporalQuery() async {
  print('示例3: 时间敏感查询（自适应时间衰减）\n');

  final priorityService = EventPriorityScoringService();

  // 测试不同的查询
  final queries = [
    '昨天的会议',
    '上周的任务',
    '吃了水煮面条',  // 无时间表达式
  ];

  for (final query in queries) {
    print('查询: "$query"');
    
    // 检测时间表达式
    priorityService.detectAndBoostTemporalExpression(query);
    
    final config = priorityService.getConfiguration();
    print('  检测到时间表达式: ${config['temporal_decay']['lambda'] > 0.01 ? "是" : "否"}');
    print('  当前 λ: ${config['temporal_decay']['lambda']}');
    print('  时间增强因子: ${config['temporal_decay']['boost']}');
    print('');
  }

  print('说明: 当查询中包含"昨天"、"上周"等相对时间表达式时，');
  print('      系统会临时增大 λ，使时间衰减更敏感，优先返回近期事件。\n');
  print('---\n');
}

/// 示例4: 激活记录
Future<void> example4ActivationTracking() async {
  print('示例4: 激活记录（模拟场景）\n');

  final priorityService = EventPriorityScoringService();

  // 创建一个模拟的事件节点
  final event = EventNode(
    id: 'event_demo',
    name: '讨论项目进展',
    type: '会议',
    startTime: DateTime.now().subtract(Duration(days: 7)),
    embedding: List<double>.generate(384, (i) => 0.1),
  );

  print('事件: ${event.name}');
  print('初始激活历史: ${event.activationHistory.length} 条\n');

  // 模拟多次激活
  print('模拟3次激活事件:');
  for (int i = 0; i < 3; i++) {
    await priorityService.recordActivation(
      node: event,
      similarity: 0.9 - i * 0.05,
    );
    print('  第${i + 1}次激活: similarity=${(0.9 - i * 0.05).toStringAsFixed(2)}');
  }

  print('\n更新后的激活历史: ${event.activationHistory.length} 条');
  print('最后访问时间: ${event.lastSeenTime}');
  
  // 计算再激活信号
  final reactScore = priorityService.calculateReactivationSignal(event);
  print('再激活信号分数: ${reactScore.toStringAsFixed(4)}');
  print('');
  print('说明: 每次节点被召回并判定为相关时，系统会自动记录激活事件。');
  print('      激活历史会影响 f_react 分数，使频繁访问的节点获得更高优先级。\n');
  print('---\n');
}

/// 示例5: 诊断分析
Future<void> example5DiagnosticAnalysis() async {
  print('示例5: 诊断分析\n');

  // 模拟一些候选节点
  final candidates = <EventNode>[];
  for (int i = 0; i < 20; i++) {
    final event = EventNode(
      id: 'event_$i',
      name: '事件$i',
      type: 'test',
      lastSeenTime: DateTime.now().subtract(Duration(days: i)),
      embedding: List<double>.generate(384, (j) => (i + j) % 10 * 0.1),
    );
    
    // 为一些节点添加激活历史
    if (i % 3 == 0) {
      event.addActivation(
        timestamp: DateTime.now().subtract(Duration(days: i ~/ 2)),
        similarity: 0.8 + (i % 5) * 0.02,
      );
    }
    
    candidates.add(event);
  }

  final priorityService = EventPriorityScoringService();
  final queryVector = List<double>.generate(384, (i) => 0.5);

  print('分析 ${candidates.length} 个候选节点的优先级分数分布...\n');

  final analysis = await priorityService.analyzePriorityDistribution(
    nodes: candidates,
    queryVector: queryVector,
  );

  print('统计结果:');
  print('  总节点数: ${analysis['total_nodes']}');
  print('  最小分数: ${(analysis['min_score'] as double).toStringAsFixed(4)}');
  print('  最大分数: ${(analysis['max_score'] as double).toStringAsFixed(4)}');
  print('  平均分数: ${(analysis['avg_score'] as double).toStringAsFixed(4)}');
  print('  中位数: ${(analysis['median_score'] as double).toStringAsFixed(4)}');
  print('');

  final dist = analysis['score_distribution'] as Map<String, dynamic>;
  print('分数分布:');
  print('  低分 (< 0.2): ${dist['low (< 0.2)']} 个');
  print('  中分 (0.2-0.5): ${dist['medium (0.2-0.5)']} 个');
  print('  高分 (0.5-0.8): ${dist['high (0.5-0.8)']} 个');
  print('  极高分 (>= 0.8): ${dist['very_high (>= 0.8)']} 个');
  print('');

  print('说明: 通过分析优先级分数分布，可以了解评分系统的区分度。');
  print('      理想情况下，分数应呈现合理的分布，避免过度集中。\n');
  print('---\n');
}

/// 示例6: 对比测试
Future<void> example6ComparisonTest() async {
  print('示例6: 对比测试 - 传统方法 vs 优先级评分\n');

  final query = '昨天吃了什么';
  
  print('查询: "$query"\n');

  // 方法1: 传统混合检索
  print('[方法1] 传统混合检索（语义+词法+领域）');
  final traditionalResults = await KnowledgeGraphService.searchEventsByText(
    query,
    topK: 3,
    usePriorityScoring: false,
  );
  
  for (int i = 0; i < traditionalResults.length; i++) {
    final result = traditionalResults[i];
    final event = result['event'] as EventNode;
    final score = result['score'] ?? result['similarity'];
    print('  [$i] ${event.name} (score: ${score.toStringAsFixed(4)})');
  }
  print('');

  // 方法2: 优先级评分
  print('[方法2] 动态优先级评分');
  final priorityResults = await KnowledgeGraphService.searchEventsByText(
    query,
    topK: 3,
    usePriorityScoring: true,
  );
  
  for (int i = 0; i < priorityResults.length; i++) {
    final result = priorityResults[i];
    final event = result['event'] as EventNode;
    final finalScore = result['final_score'];
    final components = result['components'];
    print('  [$i] ${event.name}');
    print('      最终分数: ${finalScore.toStringAsFixed(4)}');
    print('      (时间=${components['f_time'].toStringAsFixed(3)}, '
          '再激活=${components['f_react'].toStringAsFixed(3)}, '
          '语义=${components['f_sem'].toStringAsFixed(3)})');
  }
  print('');

  print('说明: 优先级评分方法综合考虑了时间、激活历史、语义和图结构，');
  print('      对于时间敏感的查询（如"昨天"），能够给予近期事件更高的权重。\n');
  print('---\n');
}

/// 辅助函数: 打印事件详情
void printEventDetails(EventNode event) {
  print('  事件ID: ${event.id}');
  print('  名称: ${event.name}');
  print('  类型: ${event.type}');
  print('  创建时间: ${event.startTime ?? event.lastUpdated}');
  print('  最后访问: ${event.lastSeenTime ?? "从未访问"}');
  print('  激活次数: ${event.activationHistory.length}');
  print('  缓存优先级: ${event.cachedPriorityScore.toStringAsFixed(4)}');
}
