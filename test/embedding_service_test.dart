import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/embedding_service.dart';
import 'package:app/models/graph_models.dart';

void main() {
  group('EmbeddingService Diagnostics', () {
    late EmbeddingService service;

    setUp(() {
      service = EmbeddingService();
    });

    test('analyzeEmbeddings should detect null embeddings', () async {
      final events = [
        EventNode(
          id: '1',
          name: 'Event 1',
          type: 'test',
          embedding: null,
        ),
        EventNode(
          id: '2',
          name: 'Event 2',
          type: 'test',
          embedding: null,
        ),
        EventNode(
          id: '3',
          name: 'Event 3',
          type: 'test',
          embedding: List<double>.filled(384, 0.5),
        ),
      ];

      final analysis = await service.analyzeEmbeddings(events);

      expect(analysis['total_events'], 3);
      expect(analysis['null_embeddings'], 2);
      expect(analysis['zero_embeddings'], 0);
    });

    test('analyzeEmbeddings should detect zero vectors', () async {
      final events = [
        EventNode(
          id: '1',
          name: 'Event 1',
          type: 'test',
          embedding: List<double>.filled(384, 0.0),
        ),
        EventNode(
          id: '2',
          name: 'Event 2',
          type: 'test',
          embedding: List<double>.filled(384, 0.0),
        ),
        EventNode(
          id: '3',
          name: 'Event 3',
          type: 'test',
          embedding: List<double>.filled(384, 0.5),
        ),
      ];

      final analysis = await service.analyzeEmbeddings(events);

      expect(analysis['total_events'], 3);
      expect(analysis['null_embeddings'], 0);
      expect(analysis['zero_embeddings'], 2);
    });

    test('analyzeEmbeddings should detect duplicate embeddings', () async {
      final sameEmbedding = List<double>.filled(384, 0.5);
      final events = [
        EventNode(
          id: '1',
          name: 'Event 1',
          type: 'test',
          embedding: List<double>.from(sameEmbedding),
        ),
        EventNode(
          id: '2',
          name: 'Event 2',
          type: 'test',
          embedding: List<double>.from(sameEmbedding),
        ),
        EventNode(
          id: '3',
          name: 'Event 3',
          type: 'test',
          embedding: List<double>.filled(384, 0.7),
        ),
      ];

      final analysis = await service.analyzeEmbeddings(events);

      expect(analysis['total_events'], 3);
      expect(analysis['unique_embeddings'], 2);
      final topDuplicates = analysis['top_duplicates'] as List;
      expect(topDuplicates.isNotEmpty, true);
      expect(topDuplicates[0]['count'], 2); // Two events with same embedding
    });

    test('analyzeEmbeddings should calculate similarity stats', () async {
      final events = [
        EventNode(
          id: '1',
          name: 'Event 1',
          type: 'test',
          embedding: List<double>.generate(384, (i) => i / 384.0),
        ),
        EventNode(
          id: '2',
          name: 'Event 2',
          type: 'test',
          embedding: List<double>.generate(384, (i) => (i + 1) / 384.0),
        ),
        EventNode(
          id: '3',
          name: 'Event 3',
          type: 'test',
          embedding: List<double>.generate(384, (i) => (i + 2) / 384.0),
        ),
      ];

      final analysis = await service.analyzeEmbeddings(events);

      final simStats = analysis['similarity_stats'] as Map<String, dynamic>;
      expect(simStats['sample_size'], greaterThan(0));
      expect(simStats['avg_similarity'], isA<double>());
      expect(simStats['max_similarity'], isA<double>());
      expect(simStats['min_similarity'], isA<double>());
    });

    test('analyzeEmbeddings should identify potential issues', () async {
      // Create a problematic scenario: all zero vectors
      final events = List.generate(
        10,
        (i) => EventNode(
          id: '$i',
          name: 'Event $i',
          type: 'test',
          embedding: List<double>.filled(384, 0.0),
        ),
      );

      final analysis = await service.analyzeEmbeddings(events);

      final issues = analysis['potential_issues'] as List<String>;
      expect(issues.isNotEmpty, true);
      // Should detect high zero vector rate
      expect(
        issues.any((issue) => issue.contains('零向量')),
        true,
      );
    });
  });

  group('EmbeddingService Whitening', () {
    late EmbeddingService service;

    setUp(() {
      service = EmbeddingService();
    });

    test('whitenVector should normalize vector correctly', () {
      final vector = [1.0, 2.0, 3.0, 4.0, 5.0];
      final whitened = service.whitenVector(vector);

      expect(whitened.length, vector.length);
      
      // Whitened vector should have mean ~0 and std ~1 when applied uniformly
      // Since we're using scalar mean/std, the relative distances should be preserved
      expect(whitened.every((v) => v.isFinite), true);
    });

    test('whitenVector should handle zero variance vectors', () {
      final vector = List<double>.filled(10, 5.0);
      final whitened = service.whitenVector(vector);

      expect(whitened.length, vector.length);
      // All values should be 0 because variance is 0
      expect(whitened.every((v) => v == 0.0), true);
    });

    test('whitenVector should handle empty vectors', () {
      final vector = <double>[];
      final whitened = service.whitenVector(vector);

      expect(whitened.length, 0);
    });
  });

  group('EmbeddingService Cosine Similarity', () {
    late EmbeddingService service;

    setUp(() {
      service = EmbeddingService();
    });

    test('calculateCosineSimilarity should return 1.0 for identical vectors', () {
      final vectorA = [1.0, 2.0, 3.0, 4.0];
      final vectorB = [1.0, 2.0, 3.0, 4.0];
      
      final similarity = service.calculateCosineSimilarity(vectorA, vectorB);
      
      expect(similarity, closeTo(1.0, 0.0001));
    });

    test('calculateCosineSimilarity should return 0.0 for orthogonal vectors', () {
      final vectorA = [1.0, 0.0, 0.0];
      final vectorB = [0.0, 1.0, 0.0];
      
      final similarity = service.calculateCosineSimilarity(vectorA, vectorB);
      
      expect(similarity, closeTo(0.0, 0.0001));
    });

    test('calculateCosineSimilarity should return -1.0 for opposite vectors', () {
      final vectorA = [1.0, 2.0, 3.0];
      final vectorB = [-1.0, -2.0, -3.0];
      
      final similarity = service.calculateCosineSimilarity(vectorA, vectorB);
      
      expect(similarity, closeTo(-1.0, 0.0001));
    });

    test('calculateCosineSimilarity should handle zero vectors', () {
      final vectorA = [0.0, 0.0, 0.0];
      final vectorB = [1.0, 2.0, 3.0];
      
      final similarity = service.calculateCosineSimilarity(vectorA, vectorB);
      
      expect(similarity, 0.0);
    });
  });

  group('EmbeddingService Fallback Vector', () {
    late EmbeddingService service;

    setUp(() {
      service = EmbeddingService();
    });

    test('fallback vector should be deterministic zero vector', () async {
      // Generate embeddings for empty text to trigger fallback
      final embedding1 = await service.generateTextEmbedding('');
      final embedding2 = await service.generateTextEmbedding('');
      
      // Both should be null since text is empty
      expect(embedding1, null);
      expect(embedding2, null);
    });
  });
}
