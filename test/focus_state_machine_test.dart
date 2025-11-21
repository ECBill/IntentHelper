import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/focus_models.dart';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/focus_state_machine.dart';
import 'package:app/services/focus_drift_model.dart';

void main() {
  group('Focus State Machine Tests', () {
    late FocusStateMachine stateMachine;

    setUp(() {
      stateMachine = FocusStateMachine();
    });

    tearDown(() {
      stateMachine.dispose();
    });

    test('FocusStateMachine should initialize correctly', () async {
      await stateMachine.initialize();
      
      final activeFocuses = stateMachine.getActiveFocuses();
      final latentFocuses = stateMachine.getLatentFocuses();
      
      expect(activeFocuses, isEmpty);
      expect(latentFocuses, isEmpty);
    });

    test('FocusStateMachine should ingest utterance and create focus points', () async {
      await stateMachine.initialize();
      
      final analysis = SemanticAnalysisInput(
        entities: ['Flutter', 'AI'],
        intent: 'learning',
        emotion: 'curious',
        content: '我想学习Flutter和AI相关的知识',
        timestamp: DateTime.now(),
      );
      
      await stateMachine.ingestUtterance(analysis);
      
      final allFocuses = stateMachine.getAllFocuses();
      expect(allFocuses, isNotEmpty);
      
      // Should have created focuses for intent, entities, and topics
      final hasIntent = allFocuses.any((f) => f.canonicalLabel == 'learning');
      final hasEntity = allFocuses.any((f) => f.canonicalLabel == 'Flutter' || f.canonicalLabel == 'AI');
      
      expect(hasIntent || hasEntity, isTrue);
    });

    test('FocusPoint should merge with similar focus', () {
      final focus1 = FocusPoint(
        type: FocusType.topic,
        canonicalLabel: 'Flutter开发',
        mentionCount: 3,
      );
      
      final focus2 = FocusPoint(
        type: FocusType.topic,
        canonicalLabel: 'Flutter',
        mentionCount: 2,
      );
      
      focus1.mergeWith(focus2);
      
      expect(focus1.mentionCount, 5);
      expect(focus1.aliases.contains('Flutter'), isTrue);
    });

    test('FocusPoint should calculate scores correctly', () async {
      await stateMachine.initialize();
      
      final analysis = SemanticAnalysisInput(
        entities: ['测试实体'],
        intent: 'testing',
        emotion: 'positive',
        content: '这是一个测试内容',
        timestamp: DateTime.now(),
      );
      
      await stateMachine.ingestUtterance(analysis);
      
      final activeFocuses = stateMachine.getActiveFocuses();
      if (activeFocuses.isNotEmpty) {
        final focus = activeFocuses.first;
        
        // All scores should be between 0 and 1
        expect(focus.salienceScore, greaterThanOrEqualTo(0.0));
        expect(focus.salienceScore, lessThanOrEqualTo(1.0));
        expect(focus.recencyScore, greaterThanOrEqualTo(0.0));
        expect(focus.recencyScore, lessThanOrEqualTo(1.0));
        expect(focus.repetitionScore, greaterThanOrEqualTo(0.0));
        expect(focus.repetitionScore, lessThanOrEqualTo(1.0));
      }
    });

    test('FocusStateMachine should limit active focuses', () async {
      await stateMachine.initialize();
      
      // Create many utterances to generate many focuses
      for (int i = 0; i < 20; i++) {
        final analysis = SemanticAnalysisInput(
          entities: ['实体$i'],
          intent: 'intent_$i',
          emotion: 'neutral',
          content: '内容 $i',
          timestamp: DateTime.now(),
        );
        
        await stateMachine.ingestUtterance(analysis);
      }
      
      final activeFocuses = stateMachine.getActiveFocuses();
      
      // Should be limited to max active focuses (12)
      expect(activeFocuses.length, lessThanOrEqualTo(12));
    });

    test('FocusStateMachine should return statistics', () async {
      await stateMachine.initialize();
      
      final analysis = SemanticAnalysisInput(
        entities: ['实体A'],
        intent: 'testing',
        emotion: 'neutral',
        content: '测试统计功能',
        timestamp: DateTime.now(),
      );
      
      await stateMachine.ingestUtterance(analysis);
      
      final stats = stateMachine.getStatistics();
      
      expect(stats, isNotEmpty);
      expect(stats.containsKey('active_focuses_count'), isTrue);
      expect(stats.containsKey('latent_focuses_count'), isTrue);
      expect(stats.containsKey('total_focuses_count'), isTrue);
      expect(stats.containsKey('focus_type_distribution'), isTrue);
    });
  });

  group('Focus Drift Model Tests', () {
    late FocusDriftModel driftModel;

    setUp(() {
      driftModel = FocusDriftModel();
    });

    tearDown(() {
      driftModel.clear();
    });

    test('FocusDriftModel should record transitions', () {
      final transition = FocusTransition(
        timestamp: DateTime.now(),
        fromFocusId: 'focus1',
        toFocusId: 'focus2',
        transitionStrength: 0.8,
        reason: 'test',
      );
      
      driftModel.recordTransition(transition);
      
      final history = driftModel.getTransitionHistory(limit: 10);
      expect(history, isNotEmpty);
      expect(history.first.toFocusId, 'focus2');
    });

    test('FocusDriftModel should track recent sequence', () {
      final transition1 = FocusTransition(
        timestamp: DateTime.now(),
        fromFocusId: 'focus1',
        toFocusId: 'focus2',
        transitionStrength: 0.8,
      );
      
      final transition2 = FocusTransition(
        timestamp: DateTime.now(),
        fromFocusId: 'focus2',
        toFocusId: 'focus3',
        transitionStrength: 0.7,
      );
      
      driftModel.recordTransition(transition1);
      driftModel.recordTransition(transition2);
      
      final sequence = driftModel.getRecentSequence();
      expect(sequence, contains('focus2'));
      expect(sequence, contains('focus3'));
    });

    test('FocusDriftModel should provide statistics', () {
      final transition = FocusTransition(
        timestamp: DateTime.now(),
        fromFocusId: 'focus1',
        toFocusId: 'focus2',
        transitionStrength: 0.8,
      );
      
      driftModel.recordTransition(transition);
      
      final stats = driftModel.getTransitionStats();
      
      expect(stats, isNotEmpty);
      expect(stats['total_transitions'], greaterThan(0));
      expect(stats.containsKey('unique_focuses'), isTrue);
    });
  });

  group('Focus Models Tests', () {
    test('FocusPoint should create with default values', () {
      final focus = FocusPoint(
        type: FocusType.topic,
        canonicalLabel: '测试主题',
      );
      
      expect(focus.type, FocusType.topic);
      expect(focus.canonicalLabel, '测试主题');
      expect(focus.state, FocusState.emerging);
      expect(focus.mentionCount, 1);
      expect(focus.linkedFocusIds, isEmpty);
    });

    test('FocusPoint should record mentions', () {
      final focus = FocusPoint(
        type: FocusType.entity,
        canonicalLabel: '实体',
        mentionCount: 1,
      );
      
      focus.recordMention();
      focus.recordMention();
      
      expect(focus.mentionCount, 3);
      expect(focus.mentionTimestamps.length, greaterThanOrEqualTo(3));
    });

    test('FocusPoint should update state', () {
      final focus = FocusPoint(
        type: FocusType.event,
        canonicalLabel: '事件',
      );
      
      expect(focus.state, FocusState.emerging);
      
      focus.updateState(FocusState.active);
      expect(focus.state, FocusState.active);
    });

    test('FocusPoint should serialize to JSON', () {
      final focus = FocusPoint(
        type: FocusType.topic,
        canonicalLabel: '主题',
        aliases: {'别名1', '别名2'},
      );
      
      final json = focus.toJson();
      
      expect(json['id'], isNotEmpty);
      expect(json['canonicalLabel'], '主题');
      expect(json['type'], contains('topic'));
      expect(json['aliases'], isA<List>());
    });

    test('FocusTransition should create correctly', () {
      final transition = FocusTransition(
        timestamp: DateTime.now(),
        fromFocusId: 'from',
        toFocusId: 'to',
        transitionStrength: 0.9,
        reason: '测试原因',
      );
      
      expect(transition.fromFocusId, 'from');
      expect(transition.toFocusId, 'to');
      expect(transition.transitionStrength, 0.9);
      expect(transition.reason, '测试原因');
    });
  });
}
