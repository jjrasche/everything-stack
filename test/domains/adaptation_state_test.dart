import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/adaptation_state.dart';

// Factory functions for component-specific adaptation states
AdaptationState STTAdaptationState({
  String scope = 'global',
  String? userId,
}) =>
    AdaptationState(
      componentType: 'stt',
      scope: scope,
      userId: userId,
      data: {
        'confidenceThreshold': 0.65,
        'minFeedbackCount': 10,
      },
    );

AdaptationState LLMAdaptationState({
  String scope = 'global',
  String? userId,
}) =>
    AdaptationState(
      componentType: 'llm',
      scope: scope,
      userId: userId,
      data: {
        'systemPromptVariant': 'default',
        'temperature': 0.7,
      },
    );

AdaptationState TTSAdaptationState({
  String scope = 'global',
  String? userId,
}) =>
    AdaptationState(
      componentType: 'tts',
      scope: scope,
      userId: userId,
      data: {
        'speechRate': 1.0,
        'voiceId': 'default',
      },
    );

void main() {
  group('AdaptationState (Generic)', () {
    test('creates state with componentType', () {
      final state = AdaptationState(componentType: 'stt');

      expect(state.componentType, 'stt');
      expect(state.dataJson, '{}');
      expect(state.version, 0);
    });

    test('stores and retrieves data as JSON', () {
      final state = AdaptationState(
        componentType: 'stt',
        data: {
          'confidenceThreshold': 0.65,
          'minFeedbackCount': 10,
        },
      );

      expect(state.data['confidenceThreshold'], 0.65);
      expect(state.data['minFeedbackCount'], 10);
      expect(state.dataJson.contains('confidenceThreshold'), true);
    });

    test('tracks version for optimistic locking', () {
      final state = AdaptationState(componentType: 'stt');

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
      expect(state.data['systemPromptVariant'], 'default');
      expect(state.data['temperature'], 0.7);
    });

    test('updates temperature tuning', () {
      final state = LLMAdaptationState(scope: 'global');

      state.data['temperature'] = 0.5;
      expect(state.data['temperature'], 0.5);
    });
  });

  group('TTSAdaptationState', () {
    test('creates state with voice settings', () {
      final state = TTSAdaptationState(scope: 'global');

      expect(state.scope, 'global');
      expect(state.data['speechRate'], 1.0);
      expect(state.data['voiceId'], 'default');
    });

    test('updates voice settings', () {
      final state = TTSAdaptationState(scope: 'global');

      state.data['voiceId'] = 'voice_female_001';
      state.data['speechRate'] = 1.1;

      expect(state.data['voiceId'], 'voice_female_001');
      expect(state.data['speechRate'], 1.1);
    });
  });

  group('Multi-scope state management', () {
    test('global state is shared baseline', () {
      final global = STTAdaptationState(scope: 'global');
      global.data['confidenceThreshold'] = 0.65;

      final user = STTAdaptationState(
        scope: 'user',
        userId: 'user_123',
      );
      user.data['confidenceThreshold'] = global.data['confidenceThreshold'];

      expect(user.data['confidenceThreshold'], global.data['confidenceThreshold']);
    });

    test('user state can diverge from global', () {
      final global = STTAdaptationState(scope: 'global');
      global.data['confidenceThreshold'] = 0.65;

      final user = STTAdaptationState(
        scope: 'user',
        userId: 'user_123',
      );
      user.data['confidenceThreshold'] = 0.55;

      expect(global.data['confidenceThreshold'], 0.65);
      expect(user.data['confidenceThreshold'], 0.55);
    });
  });
}
