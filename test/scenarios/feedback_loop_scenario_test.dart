/// # Feedback Loop End-to-End Scenario Test
///
/// Validates the complete feedback loop from user perspective:
/// 1. Turn with 4 invocations (STT, Intent, LLM, TTS)
/// 2. User provides feedback on each
/// 3. System trains on feedback
/// 4. Adaptation state is updated

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/intent_engine_trainable.dart';
import 'package:everything_stack_template/services/llm_service_trainable.dart';
import 'package:everything_stack_template/services/tts_service_trainable.dart';
import 'package:everything_stack_template/repositories/turn_repository_impl.dart';
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';
import 'package:everything_stack_template/repositories/adaptation_state_repository_impl.dart';

void main() {
  group('Feedback Loop End-to-End Scenario', () {
    late TurnRepositoryImpl turnRepo;
    late STTInvocationRepositoryImpl sttInvocationRepo;
    late IntentInvocationRepositoryImpl intentInvocationRepo;
    late LLMInvocationRepositoryImpl llmInvocationRepo;
    late TTSInvocationRepositoryImpl ttsInvocationRepo;
    late FeedbackRepositoryImpl feedbackRepo;
    late STTAdaptationStateRepositoryImpl sttStateRepo;
    late IntentAdaptationStateRepositoryImpl intentStateRepo;
    late LLMAdaptationStateRepositoryImpl llmStateRepo;
    late TTSAdaptationStateRepositoryImpl ttsStateRepo;

    late STTService sttService;
    late IntentEngineTrainable intentService;
    late LLMServiceTrainable llmService;
    late TTSServiceTrainable ttsService;

    setUp(() {
      // Initialize repositories
      turnRepo = TurnRepositoryImpl.inMemory();
      sttInvocationRepo = STTInvocationRepositoryImpl.inMemory();
      intentInvocationRepo = IntentInvocationRepositoryImpl.inMemory();
      llmInvocationRepo = LLMInvocationRepositoryImpl.inMemory();
      ttsInvocationRepo = TTSInvocationRepositoryImpl.inMemory();
      feedbackRepo = FeedbackRepositoryImpl.inMemory();
      sttStateRepo = STTAdaptationStateRepositoryImpl.inMemory();
      intentStateRepo = IntentAdaptationStateRepositoryImpl.inMemory();
      llmStateRepo = LLMAdaptationStateRepositoryImpl.inMemory();
      ttsStateRepo = TTSAdaptationStateRepositoryImpl.inMemory();

      // Initialize services
      sttService = STTService(
        invocationRepository: sttInvocationRepo,
        feedbackRepository: feedbackRepo,
        adaptationStateRepository: sttStateRepo,
      );

      intentService = IntentEngineTrainable(
        invocationRepository: intentInvocationRepo,
        feedbackRepository: feedbackRepo,
        adaptationStateRepository: intentStateRepo,
      );

      llmService = LLMServiceTrainable(
        invocationRepository: llmInvocationRepo,
        feedbackRepository: feedbackRepo,
        adaptationStateRepository: llmStateRepo,
      );

      ttsService = TTSServiceTrainable(
        invocationRepository: ttsInvocationRepo,
        feedbackRepository: feedbackRepo,
        adaptationStateRepository: ttsStateRepo,
      );

      // Set minimum feedback count to 1 for fast testing
      _setMinFeedbackCounts();
    });

    /// Scenario: User reviews a turn with 4 invocations and trains the system
    test('User marks turn for feedback, provides feedback, and trains system', () async {
      // GIVEN: A turn with 4 invocations (one per component)
      final sttInv = STTInvocation(
        audioId: 'audio_123',
        output: 'set reminder in five minutes',
        confidence: 0.55, // Below default threshold
      );
      final sttInvId = await sttService.recordInvocation(sttInv);

      final intentInv = IntentInvocation(
        intent: 'schedule.reminder',
        confidence: 0.72,
        slots: {'duration': '5 minutes'},
        toolNames: ['calendar', 'reminder'],
      );
      final intentInvId = await intentService.recordInvocation(intentInv);

      final llmInv = LLMInvocation(
        systemPromptVersion: 'v1',
        response: 'I\'ve scheduled a reminder for 5 minutes from now.',
        inputTokens: 45,
        outputTokens: 18,
        conversationHistoryLength: 3,
      );
      final llmInvId = await llmService.recordInvocation(llmInv);

      final ttsInv = TTSInvocation(
        inputText: 'I\'ve scheduled a reminder for 5 minutes from now.',
        voice: 'en-US-Neural2-A',
        language: 'en-US',
        speechRate: 1.0,
        pitch: 0.0,
      );
      final ttsInvId = await ttsService.recordInvocation(ttsInv);

      // Create turn linking all 4 invocations
      final turn = Turn(
        conversationId: 'conv_001',
        sttInvocationId: sttInvId,
        intentInvocationId: intentInvId,
        llmInvocationId: llmInvId,
        ttsInvocationId: ttsInvId,
        markedForFeedback: true,
      );
      await turnRepo.save(turn);

      // WHEN: User provides feedback on each invocation
      // STT: Confirmed low-confidence utterance → should lower threshold
      final sttFeedback = Feedback(
        invocationId: sttInvId,
        turnId: turn.uuid,
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(sttFeedback);

      // Intent: Confirmed correct intent
      final intentFeedback = Feedback(
        invocationId: intentInvId,
        turnId: turn.uuid,
        componentType: 'intent',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(intentFeedback);

      // LLM: Confirmed response is correct
      final llmFeedback = Feedback(
        invocationId: llmInvId,
        turnId: turn.uuid,
        componentType: 'llm',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(llmFeedback);

      // TTS: Satisfied with voice and speed
      final ttsFeedback = Feedback(
        invocationId: ttsInvId,
        turnId: turn.uuid,
        componentType: 'tts',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(ttsFeedback);

      // WHEN: User clicks "Train" button → trainFromFeedback called for each service
      await sttService.trainFromFeedback(turn.uuid);
      await intentService.trainFromFeedback(turn.uuid);
      await llmService.trainFromFeedback(turn.uuid);
      await ttsService.trainFromFeedback(turn.uuid);

      // THEN: Adaptation state is updated for each service
      final sttState = await sttService.getAdaptationState();
      expect(sttState['confidenceThreshold'], lessThan(0.65));
      expect(sttState['version'], 1);
      expect(sttState['feedbackCountApplied'], 1);

      final intentState = await intentService.getAdaptationState();
      expect(intentState['version'], 1);
      expect(intentState['feedbackCountApplied'], 1);

      final llmState = await llmService.getAdaptationState();
      expect(llmState['version'], 1);
      expect(llmState['feedbackCountApplied'], 1);

      final ttsState = await ttsService.getAdaptationState();
      expect(ttsState['version'], 1);
      expect(ttsState['feedbackCountApplied'], 1);
    });

    /// Scenario: User corrects an invocation instead of confirming
    test('User corrects STT and system learns from correction', () async {
      final sttInv = STTInvocation(
        audioId: 'audio_456',
        output: 'set a reminder', // Wrong
        confidence: 0.85,
      );
      final sttInvId = await sttService.recordInvocation(sttInv);

      final turn = Turn(
        conversationId: 'conv_002',
        sttInvocationId: sttInvId,
        markedForFeedback: true,
      );
      await turnRepo.save(turn);

      // User provides correction
      final feedback = Feedback(
        invocationId: sttInvId,
        turnId: turn.uuid,
        componentType: 'stt',
        action: FeedbackAction.correct,
        correctedData: {'output': 'set a reminder for tomorrow'},
      );
      await feedbackRepo.save(feedback);

      // Train system
      await sttService.trainFromFeedback(turn.uuid);

      final state = await sttService.getAdaptationState();
      // 'Correct' action doesn't affect threshold, but is recorded
      expect(state['feedbackCountApplied'], 0); // Only confirm/deny count
    });

    /// Scenario: User denies a high-confidence invocation
    test('User denies high-confidence intent and threshold increases', () async {
      final intentInv = IntentInvocation(
        intent: 'schedule.reminder',
        confidence: 0.92, // High confidence
        slots: {'duration': '5 minutes'},
        toolNames: ['calendar'],
      );
      final invId = await intentService.recordInvocation(intentInv);

      final turn = Turn(
        conversationId: 'conv_003',
        intentInvocationId: invId,
        markedForFeedback: true,
      );
      await turnRepo.save(turn);

      // User denies this high-confidence intent
      final feedback = Feedback(
        invocationId: invId,
        turnId: turn.uuid,
        componentType: 'intent',
        action: FeedbackAction.deny,
      );
      await feedbackRepo.save(feedback);

      final initialState = await intentService.getAdaptationState();
      final initialThreshold = initialState['confidenceThreshold'] as double;

      // Train system
      await intentService.trainFromFeedback(turn.uuid);

      final newState = await intentService.getAdaptationState();
      final newThreshold = newState['confidenceThreshold'] as double;

      // Threshold should have increased
      expect(newThreshold, greaterThan(initialThreshold));
    });

    /// Scenario: User ignores feedback (shouldn't affect training)
    test('Ignored feedback does not affect adaptation state', () async {
      final sttInv = STTInvocation(
        audioId: 'audio_789',
        output: 'test',
        confidence: 0.45,
      );
      final invId = await sttService.recordInvocation(sttInv);

      final turn = Turn(
        conversationId: 'conv_004',
        sttInvocationId: invId,
        markedForFeedback: true,
      );
      await turnRepo.save(turn);

      // User ignores this feedback
      final feedback = Feedback(
        invocationId: invId,
        turnId: turn.uuid,
        componentType: 'stt',
        action: FeedbackAction.ignore,
      );
      await feedbackRepo.save(feedback);

      final initialState = await sttService.getAdaptationState();
      final initialThreshold = initialState['confidenceThreshold'] as double;

      // Train system
      await sttService.trainFromFeedback(turn.uuid);

      final newState = await sttService.getAdaptationState();
      final newThreshold = newState['confidenceThreshold'] as double;

      // Threshold should NOT change (no valid feedback)
      expect(newThreshold, equals(initialThreshold));
      expect(newState['feedbackCountApplied'], 0);
    });

    /// Scenario: Multi-user personalization
    test('User-scoped state personalizes from global baseline', () async {
      const userId1 = 'user_123';
      const userId2 = 'user_456';

      // Create invocations for both users
      final inv1 = STTInvocation(
        audioId: 'audio_u1',
        output: 'text one',
        confidence: 0.55,
      );
      final invId1 = await sttService.recordInvocation(inv1);

      final inv2 = STTInvocation(
        audioId: 'audio_u2',
        output: 'text two',
        confidence: 0.55,
      );
      final invId2 = await sttService.recordInvocation(inv2);

      final turn1 = Turn(
        conversationId: 'conv_u1',
        sttInvocationId: invId1,
        markedForFeedback: true,
      );
      await turnRepo.save(turn1);

      final turn2 = Turn(
        conversationId: 'conv_u2',
        sttInvocationId: invId2,
        markedForFeedback: true,
      );
      await turnRepo.save(turn2);

      // User 1 provides feedback
      final feedback1 = Feedback(
        invocationId: invId1,
        turnId: turn1.uuid,
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(feedback1);

      // Train for user 1
      await sttService.trainFromFeedback(turn1.uuid, userId: userId1);

      // User 2 provides feedback
      final feedback2 = Feedback(
        invocationId: invId2,
        turnId: turn2.uuid,
        componentType: 'stt',
        action: FeedbackAction.deny,
      );
      await feedbackRepo.save(feedback2);

      // Train for user 2
      await sttService.trainFromFeedback(turn2.uuid, userId: userId2);

      // User 1 state should be different from user 2 state
      final state1 = await sttService.getAdaptationState(userId: userId1);
      final state2 = await sttService.getAdaptationState(userId: userId2);

      // User 1 lowered threshold (confirm on low-conf)
      // User 2 raised threshold (deny on high-conf)
      expect(state1['confidenceThreshold'], lessThan(0.65));
      expect(state2['confidenceThreshold'], greaterThan(0.65));
    });
  });

  /// Helper: Set minimum feedback count to 1 for all state repos
  void _setMinFeedbackCounts() {
    // This would need to be done through direct state manipulation
    // For now, tests are designed with minFeedbackCount = 1 in mind
  }
}
