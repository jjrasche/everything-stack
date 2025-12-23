import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';

void main() {
  group('STTAdaptationState', () {
    test('creates global state with defaults', () {
      final state = STTAdaptationState(scope: 'global');

      expect(state.scope, 'global');
      expect(state.userId, null);
      expect(state.confidenceThreshold, 0.65);
      expect(state.minFeedbackCount, 10);
      expect(state.version, 0);
    });

    test('creates user-scoped state', () {
      final state = STTAdaptationState(
        scope: 'user',
        userId: 'user_123',
      );

      expect(state.scope, 'user');
      expect(state.userId, 'user_123');
    });

    test('tracks version for optimistic locking', () {
      final state = STTAdaptationState(scope: 'global');

      state.version = 0;
      expect(state.version, 0);

      state.version = 1;
      expect(state.version, 1);
    });

    test('records last update reason', () {
      final state = STTAdaptationState(scope: 'global');

      state.lastUpdateReason = 'user_marked_turn_bad';
      expect(state.lastUpdateReason, 'user_marked_turn_bad');
    });
  });

  // IntentAdaptationState tests deferred to Phase 1 (Intent not implemented)

  group('LLMAdaptationState', () {
    test('creates state with prompt version', () {
      final state = LLMAdaptationState(scope: 'global');

      expect(state.scope, 'global');
      expect(state.systemPromptVariant, 'default');
      expect(state.temperature, 0.7);
    });

    test('updates temperature tuning', () {
      final state = LLMAdaptationState(scope: 'global');

      state.temperature = 0.5;
      expect(state.temperature, 0.5);
    });
  });

  group('TTSAdaptationState', () {
    test('creates state with voice settings', () {
      final state = TTSAdaptationState(scope: 'global');

      expect(state.scope, 'global');
      expect(state.speechRate, 1.0);
      expect(state.voiceId, 'default');
    });

    test('updates voice settings', () {
      final state = TTSAdaptationState(scope: 'global');

      state.voiceId = 'voice_female_001';
      state.speechRate = 1.1;

      expect(state.voiceId, 'voice_female_001');
      expect(state.speechRate, 1.1);
    });
  });

  group('Multi-scope state management', () {
    test('global state is shared baseline', () {
      final global = STTAdaptationState(scope: 'global');
      global.confidenceThreshold = 0.65;

      final user = STTAdaptationState(
        scope: 'user',
        userId: 'user_123',
      );
      user.confidenceThreshold = global.confidenceThreshold;

      expect(user.confidenceThreshold, global.confidenceThreshold);
    });

    test('user state can diverge from global', () {
      final global = STTAdaptationState(scope: 'global');
      global.confidenceThreshold = 0.65;

      final user = STTAdaptationState(
        scope: 'user',
        userId: 'user_123',
      );
      user.confidenceThreshold = 0.55;

      expect(global.confidenceThreshold, 0.65);
      expect(user.confidenceThreshold, 0.55);
    });
  });
}
