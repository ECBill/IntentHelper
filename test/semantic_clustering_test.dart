import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/graph_models.dart';

void main() {
  group('Two-Stage Clustering Model Tests', () {
    test('ClusterNode should support level and parentClusterId', () {
      final cluster = ClusterNode(
        id: 'test_cluster',
        name: 'Test Cluster',
        description: 'Test description',
        level: 1,
        parentClusterId: 'parent_123',
      );

      expect(cluster.level, 1);
      expect(cluster.parentClusterId, 'parent_123');
      expect(cluster.type, 'cluster');
    });

    test('ClusterNode default level should be 2', () {
      final cluster = ClusterNode(
        id: 'test_cluster',
        name: 'Test Cluster',
        description: 'Test description',
      );

      expect(cluster.level, 2);
      expect(cluster.parentClusterId, null);
    });

    test('EventNode should have correct embedding text', () {
      final event = EventNode(
        id: 'test_event',
        name: '讨论海底捞',
        type: '饮食',
        description: '今天去了海底捞，服务很好',
        purpose: '聚餐',
        result: '很满意',
      );

      final embeddingText = event.getEmbeddingText();
      
      expect(embeddingText, contains('讨论海底捞'));
      expect(embeddingText, contains('今天去了海底捞'));
      expect(embeddingText, contains('聚餐'));
      expect(embeddingText, contains('很满意'));
    });

    test('EventNode should support clusterId assignment', () {
      final event = EventNode(
        id: 'test_event',
        name: 'Test Event',
        type: 'test',
        clusterId: 'cluster_1',
      );

      expect(event.clusterId, 'cluster_1');
      
      event.clusterId = 'cluster_2';
      expect(event.clusterId, 'cluster_2');
    });
  });

  group('ClusteringMeta Tests', () {
    test('ClusteringMeta should store two-stage parameters', () {
      final meta = ClusteringMeta(
        algorithmUsed: 'two-stage-agglomerative',
        totalEvents: 100,
        clustersCreated: 10,
      );

      meta.parameters = {
        'stage1_similarity_threshold': 0.70,
        'stage2_similarity_threshold': 0.85,
        'stage1_min_cluster_size': 3,
        'stage2_min_cluster_size': 2,
      };

      expect(meta.algorithmUsed, 'two-stage-agglomerative');
      expect(meta.parameters['stage1_similarity_threshold'], 0.70);
      expect(meta.parameters['stage2_similarity_threshold'], 0.85);
    });
  });
}
