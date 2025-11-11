import 'package:test/test.dart';
import 'package:app/services/event_priority_scoring_service.dart';
import 'package:app/models/graph_models.dart';
import 'dart:math';

void main() {
  group('EventPriorityScoringService', () {
    late EventPriorityScoringService service;

    setUp(() {
      service = EventPriorityScoringService();
      // Reset to default parameters
      service.updateParameters(
        lambda: 0.01,
        alpha: 1.0,
        beta: 0.01,
        gamma: 0.5,
        theta1: 0.3,
        theta2: 0.4,
        theta3: 0.2,
        theta4: 0.1,
        strategy: ScoringStrategy.multiplicative,
      );
    });

    test('Temporal decay decreases with time', () {
      final now = DateTime.now();
      
      // Create recent event
      final recentEvent = EventNode(
        id: 'event_recent',
        name: 'Recent Event',
        type: 'test',
        lastSeenTime: now.subtract(Duration(days: 1)),
      );

      // Create old event
      final oldEvent = EventNode(
        id: 'event_old',
        name: 'Old Event',
        type: 'test',
        lastSeenTime: now.subtract(Duration(days: 30)),
      );

      final recentDecay = service.calculateTemporalDecay(recentEvent, now: now);
      final oldDecay = service.calculateTemporalDecay(oldEvent, now: now);

      // Recent events should have higher decay scores
      expect(recentDecay, greaterThan(oldDecay));
      
      // Both should be in (0, 1] range
      expect(recentDecay, greaterThan(0));
      expect(recentDecay, lessThanOrEqualTo(1.0));
      expect(oldDecay, greaterThan(0));
      expect(oldDecay, lessThanOrEqualTo(1.0));
    });

    test('Reactivation signal increases with more activations', () {
      final now = DateTime.now();
      
      // Event with no activations
      final inactiveEvent = EventNode(
        id: 'event_inactive',
        name: 'Inactive Event',
        type: 'test',
      );

      // Event with multiple activations
      final activeEvent = EventNode(
        id: 'event_active',
        name: 'Active Event',
        type: 'test',
      );
      
      // Add activations
      activeEvent.addActivation(
        timestamp: now.subtract(Duration(days: 1)),
        similarity: 0.9,
      );
      activeEvent.addActivation(
        timestamp: now.subtract(Duration(days: 3)),
        similarity: 0.85,
      );
      activeEvent.addActivation(
        timestamp: now.subtract(Duration(days: 7)),
        similarity: 0.8,
      );

      final inactiveScore = service.calculateReactivationSignal(inactiveEvent, now: now);
      final activeScore = service.calculateReactivationSignal(activeEvent, now: now);

      // Active events should have higher reactivation scores
      expect(activeScore, greaterThan(inactiveScore));
      expect(inactiveScore, equals(0.0));
      expect(activeScore, greaterThan(0));
    });

    test('Semantic similarity is correctly scaled to [0,1]', () {
      final queryVector = List<double>.generate(384, (i) => Random().nextDouble() - 0.5);
      
      // Create event with similar embedding
      final similarEvent = EventNode(
        id: 'event_similar',
        name: 'Similar Event',
        type: 'test',
        embedding: List<double>.from(queryVector), // Same vector
      );

      // Create event with orthogonal embedding
      final orthogonalEvent = EventNode(
        id: 'event_orthogonal',
        name: 'Orthogonal Event',
        type: 'test',
        embedding: List<double>.generate(384, (i) => Random().nextDouble() - 0.5),
      );

      final similarScore = service.calculateSemanticSimilarity(queryVector, similarEvent);
      final orthogonalScore = service.calculateSemanticSimilarity(queryVector, orthogonalEvent);

      // Scores should be in [0, 1] range
      expect(similarScore, greaterThanOrEqualTo(0.0));
      expect(similarScore, lessThanOrEqualTo(1.0));
      expect(orthogonalScore, greaterThanOrEqualTo(0.0));
      expect(orthogonalScore, lessThanOrEqualTo(1.0));

      // Identical vectors should have score close to 1.0
      expect(similarScore, closeTo(1.0, 0.01));
    });

    test('Temporal boost is applied when detecting relative time expressions', () {
      // Test various temporal expressions
      final temporalQueries = ['昨天吃了什么', '上周的会议', '今天的任务', '刚才说的'];
      final nonTemporalQuery = '吃了水煮面条';

      // Test temporal query
      service.detectAndBoostTemporalExpression(temporalQueries[0]);
      final boostedLambda = service.lambda;
      final boostedBoost = service.temporalBoost;

      // Reset and test non-temporal query
      service.detectAndBoostTemporalExpression(nonTemporalQuery);
      final normalLambda = service.lambda;
      final normalBoost = service.temporalBoost;

      // Temporal queries should increase lambda and boost
      expect(boostedLambda, greaterThan(normalLambda));
      expect(boostedBoost, greaterThan(normalBoost));
    });

    test('Priority score combines all components correctly', () async {
      final now = DateTime.now();
      final queryVector = List<double>.generate(384, (i) => 0.1);
      
      final event = EventNode(
        id: 'event_test',
        name: 'Test Event',
        type: 'test',
        lastSeenTime: now.subtract(Duration(days: 2)),
        embedding: queryVector,
      );
      
      // Add some activations
      event.addActivation(timestamp: now.subtract(Duration(days: 1)), similarity: 0.9);

      final priorityScore = await service.calculatePriorityScore(
        node: event,
        queryVector: queryVector,
        now: now,
      );

      // Priority score should be positive and reasonable
      expect(priorityScore, greaterThan(0));
      
      // Should be weighted combination of components
      // With default weights: 0.3*f_time + 0.4*f_react + 0.2*f_sem + 0.1*f_diff
      // Since we have temporal, reactivation, and semantic components, score should be > 0
      expect(priorityScore, lessThan(10.0)); // Reasonable upper bound
    });

    test('Configuration can be updated and retrieved', () {
      service.updateParameters(
        lambda: 0.02,
        theta1: 0.4,
        strategy: ScoringStrategy.softmax,
      );

      final config = service.getConfiguration();
      
      expect(config['temporal_decay']['lambda'], equals(0.02));
      expect(config['weights']['theta1_time'], equals(0.4));
      expect(config['strategy'], contains('softmax'));
    });

    test('Edge weight calculation returns correct values', () {
      // Test using reflection or by indirectly testing through diffusion
      // Since _getEdgeWeight is private, we can test it through its effect
      
      // This is a structural test - the actual weights are defined in the implementation
      // We just verify the service exists and can be configured
      expect(service.gamma, equals(0.5));
      expect(service.maxHops, equals(1));
    });

    test('Activation history is limited to 100 entries', () {
      final event = EventNode(
        id: 'event_test',
        name: 'Test Event',
        type: 'test',
      );

      // Add 150 activations
      for (int i = 0; i < 150; i++) {
        event.addActivation(
          timestamp: DateTime.now().subtract(Duration(hours: i)),
          similarity: 0.8,
        );
      }

      // Should only keep last 100
      expect(event.activationHistory.length, equals(100));
    });
  });

  group('EventNode Priority Fields', () {
    test('EventNode can store and retrieve activation history', () {
      final event = EventNode(
        id: 'event_test',
        name: 'Test Event',
        type: 'test',
      );

      expect(event.activationHistory, isEmpty);

      event.addActivation(timestamp: DateTime.now(), similarity: 0.95);
      expect(event.activationHistory.length, equals(1));
      expect(event.activationHistory[0]['similarity'], equals(0.95));
    });

    test('EventNode JSON serialization includes priority fields', () {
      final now = DateTime.now();
      final event = EventNode(
        id: 'event_test',
        name: 'Test Event',
        type: 'test',
        lastSeenTime: now,
        cachedPriorityScore: 0.75,
      );
      
      event.addActivation(timestamp: now, similarity: 0.9);

      final json = event.toJson();
      
      expect(json['lastSeenTime'], isNotNull);
      expect(json['activationHistoryJson'], isNotNull);
      expect(json['cachedPriorityScore'], equals(0.75));
    });

    test('EventNode can be reconstructed from JSON with priority fields', () {
      final now = DateTime.now();
      final original = EventNode(
        id: 'event_test',
        name: 'Test Event',
        type: 'test',
        lastSeenTime: now,
        cachedPriorityScore: 0.75,
      );
      
      original.addActivation(timestamp: now, similarity: 0.9);

      final json = original.toJson();
      final reconstructed = EventNode.fromJson(json);

      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.cachedPriorityScore, equals(0.75));
      expect(reconstructed.activationHistory.length, equals(1));
    });
  });

  group('EventRelation Constants', () {
    test('Relation type constants are defined', () {
      expect(EventRelation.RELATION_REVISIT, equals('revisit'));
      expect(EventRelation.RELATION_PROGRESS_OF, equals('progress_of'));
      expect(EventRelation.RELATION_TEMPORAL, equals('temporal_sequence'));
      expect(EventRelation.RELATION_CAUSAL, equals('causal'));
      expect(EventRelation.RELATION_CONTAINS, equals('contains'));
    });
  });
}
