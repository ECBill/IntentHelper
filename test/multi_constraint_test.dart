import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/models/constraint_models.dart';
import 'package:app/services/multi_constraint_retrieval.dart';

void main() {
  group('Constraint Evaluation Tests', () {
    late EventNode testNode;
    late RetrievalContext testContext;

    setUp(() {
      // 创建测试事件节点
      testNode = EventNode(
        id: 'test_event_1',
        name: '测试会议',
        type: 'meeting',
        startTime: DateTime(2024, 1, 15, 10, 0),
        endTime: DateTime(2024, 1, 15, 12, 0),
        location: '上海办公室',
        description: '这是一个测试会议',
      );

      // 创建测试上下文
      testContext = RetrievalContext(
        focusTopics: ['会议', '工作'],
        queryTime: DateTime(2024, 1, 15, 11, 0),
        targetLocation: '上海',
      );
    });

    test('TimeWindowConstraint - 节点在时间窗口内应通过', () {
      final constraint = TimeWindowConstraint(
        startTime: DateTime(2024, 1, 15, 9, 0),
        endTime: DateTime(2024, 1, 15, 13, 0),
      );

      final result = constraint.evaluate(testNode, testContext);
      expect(result.passes, true);
    });

    test('TimeWindowConstraint - 节点在时间窗口外应失败', () {
      final constraint = TimeWindowConstraint(
        startTime: DateTime(2024, 1, 16, 9, 0),
        endTime: DateTime(2024, 1, 16, 13, 0),
      );

      final result = constraint.evaluate(testNode, testContext);
      expect(result.passes, false);
    });

    test('TemporalProximityConstraint - 时间接近度应正确计算', () {
      final constraint = TemporalProximityConstraint(
        targetTime: DateTime(2024, 1, 15, 11, 0),
        maxDistance: Duration(days: 1),
        weight: 1.0,
      );

      final result = constraint.evaluate(testNode, testContext);
      expect(result.passes, true);
      expect(result.scoreContribution, greaterThan(0.9)); // 很接近目标时间
    });

    test('LocationMatchConstraint - 精确地点匹配应通过', () {
      final constraint = LocationMatchConstraint(
        requiredLocation: '上海',
      );

      final result = constraint.evaluate(testNode, testContext);
      expect(result.passes, true);
    });

    test('LocationMatchConstraint - 不匹配的地点应失败', () {
      final constraint = LocationMatchConstraint(
        requiredLocation: '北京',
      );

      final result = constraint.evaluate(testNode, testContext);
      expect(result.passes, false);
    });

    test('LocationSimilarityConstraint - 部分匹配应有分数', () {
      final constraint = LocationSimilarityConstraint(
        targetLocation: '上海',
        weight: 1.0,
      );

      final result = constraint.evaluate(testNode, testContext);
      expect(result.passes, true);
      expect(result.scoreContribution, greaterThan(0.0));
    });

    test('FreshnessBoostConstraint - 最近更新的节点应得到奖励', () {
      // 创建一个最近访问的节点
      final recentNode = EventNode(
        id: 'recent_event',
        name: '最近事件',
        type: 'task',
        lastSeenTime: DateTime.now().subtract(Duration(hours: 1)),
      );

      final constraint = FreshnessBoostConstraint(
        recentWindow: Duration(hours: 24),
        weight: 1.0,
      );

      final result = constraint.evaluate(recentNode, testContext);
      expect(result.passes, true);
      expect(result.scoreContribution, greaterThan(0.9)); // 很新鲜
    });
  });

  group('ScoredNode Tests', () {
    test('computeCompositeScore - 综合得分计算正确', () {
      final node = EventNode(
        id: 'test_node',
        name: '测试节点',
        type: 'event',
      );

      final scoredNode = ScoredNode(
        node: node,
        embeddingScore: 0.8,
        constraintScores: {
          'TemporalProximity': 0.6,
          'LocationSimilarity': 0.4,
          'FreshnessBoost': 0.5,
        },
      );

      scoredNode.computeCompositeScore(
        embeddingWeight: 0.4,
        constraintWeight: 0.5,
        recencyWeight: 0.1,
      );

      // 验证综合得分在合理范围内
      expect(scoredNode.compositeScore, greaterThan(0.0));
      expect(scoredNode.compositeScore, lessThanOrEqual(1.0));
    });
  });

  group('MultiConstraintRetrievalService Tests', () {
    test('mergeAndPrune - 节点池合并和裁剪正确', () {
      final service = MultiConstraintRetrievalService();

      // 创建现有节点池
      final existingPool = [
        ScoredNode(
          node: EventNode(id: 'node1', name: 'Node 1', type: 'event'),
          embeddingScore: 0.8,
          compositeScore: 0.8,
        ),
        ScoredNode(
          node: EventNode(id: 'node2', name: 'Node 2', type: 'event'),
          embeddingScore: 0.6,
          compositeScore: 0.6,
        ),
      ];

      // 创建新节点（包含一个重复的和一个新的）
      final newNodes = [
        ScoredNode(
          node: EventNode(id: 'node2', name: 'Node 2 Updated', type: 'event'),
          embeddingScore: 0.9,
          compositeScore: 0.9, // 更高的分数
        ),
        ScoredNode(
          node: EventNode(id: 'node3', name: 'Node 3', type: 'event'),
          embeddingScore: 0.7,
          compositeScore: 0.7,
        ),
      ];

      final merged = service.mergeAndPrune(
        existingPool: existingPool,
        newNodes: newNodes,
        maxPoolSize: 3,
      );

      // 验证结果
      expect(merged.length, 3);
      expect(merged[0].node.id, 'node2'); // 最高分
      expect(merged[0].compositeScore, 0.9); // 使用更新的分数
      expect(merged[1].node.id, 'node1');
      expect(merged[2].node.id, 'node3');
    });

    test('mergeAndPrune - 限制池大小工作正确', () {
      final service = MultiConstraintRetrievalService();

      final existingPool = List.generate(
        15,
        (i) => ScoredNode(
          node: EventNode(id: 'node$i', name: 'Node $i', type: 'event'),
          compositeScore: i.toDouble() / 15,
        ),
      );

      final newNodes = List.generate(
        10,
        (i) => ScoredNode(
          node: EventNode(id: 'new_node$i', name: 'New Node $i', type: 'event'),
          compositeScore: (i + 10).toDouble() / 15,
        ),
      );

      final merged = service.mergeAndPrune(
        existingPool: existingPool,
        newNodes: newNodes,
        maxPoolSize: 20,
      );

      // 应该保留前20个最高分的节点
      expect(merged.length, 20);
      // 验证按分数降序排列
      for (int i = 0; i < merged.length - 1; i++) {
        expect(merged[i].compositeScore, greaterThanOrEqualTo(merged[i + 1].compositeScore));
      }
    });

    test('createDefaultConstraints - 创建默认约束集', () {
      final service = MultiConstraintRetrievalService();

      final constraints = service.createDefaultConstraints(
        targetTime: DateTime.now(),
        targetLocation: '北京',
      );

      expect(constraints.length, greaterThan(0));
      // 应该包含时间接近度约束
      expect(constraints.any((c) => c.name.contains('Temporal')), true);
      // 应该包含地点相似度约束
      expect(constraints.any((c) => c.name.contains('Location')), true);
      // 应该包含新鲜度约束
      expect(constraints.any((c) => c.name.contains('Freshness')), true);
    });

    test('createStrictConstraints - 创建严格约束集', () {
      final service = MultiConstraintRetrievalService();

      final constraints = service.createStrictConstraints(
        startTime: DateTime(2024, 1, 1),
        endTime: DateTime(2024, 1, 31),
        requiredLocation: '上海',
      );

      // 严格约束应该都是硬约束
      expect(constraints.every((c) => c.isHard), true);
    });
  });
}
