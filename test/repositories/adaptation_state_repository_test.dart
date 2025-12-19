import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';
import 'package:everything_stack_template/repositories/adaptation_state_repository_impl.dart';

void main() {
  group('STTAdaptationStateRepository', () {
    late STTAdaptationStateRepositoryImpl repository;

    setUp(() {
      repository = STTAdaptationStateRepositoryImpl.inMemory();
    });

    test('returns global state as default', () async {
      final state = await repository.getCurrent();

      expect(state.scope, 'global');
      expect(state.confidenceThreshold, 0.65);
    });

    test('returns user state if it exists', () async {
      final userState = STTAdaptationState(
        scope: 'user',
        userId: 'user_123',
      );
      userState.confidenceThreshold = 0.55;

      await repository.save(userState);

      final retrieved = await repository.getCurrent(userId: 'user_123');

      expect(retrieved.scope, 'user');
      expect(retrieved.confidenceThreshold, 0.55);
    });

    test('falls back to global if user state not found', () async {
      final global = STTAdaptationState(scope: 'global');
      global.confidenceThreshold = 0.65;
      await repository.save(global);

      final retrieved = await repository.getCurrent(userId: 'user_456');

      expect(retrieved.scope, 'global');
      expect(retrieved.confidenceThreshold, 0.65);
    });

    test('updates with version check (optimistic locking)', () async {
      final state = STTAdaptationState(scope: 'global');
      state.version = 0;
      await repository.save(state);

      state.version = 0;
      state.confidenceThreshold = 0.70;
      state.version = 1;

      final updated = await repository.updateWithVersion(state);

      expect(updated, true);

      final retrieved = await repository.getCurrent();
      expect(retrieved.confidenceThreshold, 0.70);
      expect(retrieved.version, 1);
    });

    test('version conflict prevents update', () async {
      final state = STTAdaptationState(scope: 'global');
      state.version = 0;
      await repository.save(state);

      // Try to update with wrong version
      state.confidenceThreshold = 0.70;
      state.version = 5; // Wrong version!

      final updated = await repository.updateWithVersion(state);

      expect(updated, false);

      // State should not have changed
      final retrieved = await repository.getCurrent();
      expect(retrieved.confidenceThreshold, 0.65);
    });

    test('tracks update reason and feedback count', () async {
      final state = STTAdaptationState(scope: 'global');
      state.lastUpdateReason = 'trainFromFeedback';
      state.feedbackCountApplied = 15;

      await repository.save(state);

      final retrieved = await repository.getCurrent();
      expect(retrieved.lastUpdateReason, 'trainFromFeedback');
      expect(retrieved.feedbackCountApplied, 15);
    });
  });

  group('IntentAdaptationStateRepository', () {
    late IntentAdaptationStateRepositoryImpl repository;

    setUp(() {
      repository = IntentAdaptationStateRepositoryImpl.inMemory();
    });

    test('stores tool confidence thresholds', () async {
      final state = IntentAdaptationState(scope: 'global');
      state.toolConfidenceThresholds = {
        'reminder': 0.60,
        'message': 0.70,
      };

      await repository.save(state);

      final retrieved = await repository.getCurrent();
      expect(retrieved.toolConfidenceThresholds['reminder'], 0.60);
      expect(retrieved.toolConfidenceThresholds['message'], 0.70);
    });

    test('tracks slot priority', () async {
      final state = IntentAdaptationState(scope: 'global');
      state.slotPriority = ['contact', 'duration', 'time'];

      await repository.save(state);

      final retrieved = await repository.getCurrent();
      expect(retrieved.slotPriority, ['contact', 'duration', 'time']);
    });
  });
}
