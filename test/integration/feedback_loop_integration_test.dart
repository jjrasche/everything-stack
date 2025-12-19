import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';
import 'package:everything_stack_template/repositories/turn_repository_impl.dart';
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';
import 'package:everything_stack_template/repositories/adaptation_state_repository_impl.dart';

void main() {
  group('Feedback Loop Integration', () {
    late TurnRepositoryImpl turnRepo;
    late STTInvocationRepositoryImpl sttRepo;
    late IntentInvocationRepositoryImpl intentRepo;
    late LLMInvocationRepositoryImpl llmRepo;
    late TTSInvocationRepositoryImpl ttsRepo;
    late FeedbackRepositoryImpl feedbackRepo;
    late STTAdaptationStateRepositoryImpl sttStateRepo;

    setUp(() {
      turnRepo = TurnRepositoryImpl.inMemory();
      sttRepo = STTInvocationRepositoryImpl.inMemory();
      intentRepo = IntentInvocationRepositoryImpl.inMemory();
      llmRepo = LLMInvocationRepositoryImpl.inMemory();
      ttsRepo = TTSInvocationRepositoryImpl.inMemory();
      feedbackRepo = FeedbackRepositoryImpl.inMemory();
      sttStateRepo = STTAdaptationStateRepositoryImpl.inMemory();
    });

    test('Complete feedback loop: invocation → feedback → learning', () async {
      // ============ PHASE 1: Component Execution ============
      // User says: "Set a reminder"
      // STT produces invocation
      final sttInvocation = STTInvocation(
        audioId: 'audio_001',
        output: 'set a reminder',
        confidence: 0.92,
      );
      await sttRepo.save(sttInvocation);

      // Intent classifies
      final intentInvocation = IntentInvocation(
        transcription: 'set a reminder',
        toolName: 'reminder',
        slotsJson: '{"title":"task"}',
        confidence: 0.88,
      );
      await intentRepo.save(intentInvocation);

      // LLM generates response
      final llmInvocation = LLMInvocation(
        systemPromptVersion: 'v1.0.0',
        conversationHistoryLength: 0,
        response: 'I can help you set that reminder.',
        tokenCount: 32,
      );
      await llmRepo.save(llmInvocation);

      // TTS synthesizes
      final ttsInvocation = TTSInvocation(
        text: 'I can help you set that reminder.',
        audioId: 'audio_resp_001',
      );
      await ttsRepo.save(ttsInvocation);

      // ============ PHASE 2: Turn Grouping ============
      // Group all invocations into a turn
      final turn = Turn(
        conversationId: 'conv_001',
        turnIndex: 1,
      );
      turn.sttInvocationId = sttInvocation.uuid;
      turn.intentInvocationId = intentInvocation.uuid;
      turn.llmInvocationId = llmInvocation.uuid;
      turn.ttsInvocationId = ttsInvocation.uuid;

      await turnRepo.save(turn);

      // Verify turn is complete
      expect(turn.isComplete, true);
      expect(turn.getExistingInvocationIds().length, 4);

      // ============ PHASE 3: User Feedback ============
      // User marks turn for feedback
      turn.markedForFeedback = true;
      turn.markedAt = DateTime.now();
      await turnRepo.save(turn);

      // User provides feedback on each component
      // STT: "That transcription was correct"
      final sttFeedback = Feedback(
        invocationId: sttInvocation.uuid,
        turnId: turn.uuid,
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(sttFeedback);

      // Intent: "That's not the tool I wanted"
      final intentFeedback = Feedback(
        invocationId: intentInvocation.uuid,
        turnId: turn.uuid,
        componentType: 'intent',
        action: FeedbackAction.deny,
      );
      await feedbackRepo.save(intentFeedback);

      // LLM: "Response was good"
      final llmFeedback = Feedback(
        invocationId: llmInvocation.uuid,
        turnId: turn.uuid,
        componentType: 'llm',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(llmFeedback);

      // TTS: "Speech was clear"
      final ttsFeedback = Feedback(
        invocationId: ttsInvocation.uuid,
        turnId: turn.uuid,
        componentType: 'tts',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(ttsFeedback);

      // ============ PHASE 4: Verification ============
      // Verify all feedback was recorded
      final allFeedback = await feedbackRepo.findByTurn(turn.uuid);
      expect(allFeedback.length, 4);

      // Get component-specific feedback
      final sttFeedbackForTurn =
          await feedbackRepo.findByTurnAndComponent(turn.uuid, 'stt');
      expect(sttFeedbackForTurn.length, 1);
      expect(sttFeedbackForTurn[0].action, FeedbackAction.confirm);

      // ============ PHASE 5: Learning ============
      // STT learns from feedback
      // Rule: If confidence was high (0.92) and user confirmed, keep threshold
      var sttState = await sttStateRepo.getCurrent();
      expect(sttState.version, 0);
      expect(sttState.confidenceThreshold, 0.65);

      // Component decides to keep threshold (high confidence was correct)
      // No state change needed

      // But if we had low confidence with confirm, we'd lower the threshold:
      // Let's simulate another turn with low confidence that was correct
      final turn2 = Turn(
        conversationId: 'conv_001',
        turnIndex: 2,
      );

      final lowConfidenceSTT = STTInvocation(
        audioId: 'audio_002',
        output: 'set a timer',
        confidence: 0.55, // Below threshold!
      );
      await sttRepo.save(lowConfidenceSTT);

      turn2.sttInvocationId = lowConfidenceSTT.uuid;
      await turnRepo.save(turn2);

      // User confirms this low-confidence result
      final lowConfFeedback = Feedback(
        invocationId: lowConfidenceSTT.uuid,
        turnId: turn2.uuid,
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(lowConfFeedback);

      // Component learns: "Low confidence can be correct"
      // Lower threshold from 0.65 to 0.60
      sttState = await sttStateRepo.getCurrent();
      sttState.confidenceThreshold = 0.60;
      sttState.version = 1;
      sttState.lastUpdateReason = 'trainFromFeedback';
      sttState.feedbackCountApplied = 1;

      await sttStateRepo.save(sttState);

      // Verify learning took effect
      final updatedState = await sttStateRepo.getCurrent();
      expect(updatedState.confidenceThreshold, 0.60);
      expect(updatedState.version, 1);
      expect(updatedState.lastUpdateReason, 'trainFromFeedback');
    });

    test('Multi-user personalization: global → user state', () async {
      // Create global baseline
      final globalState = STTAdaptationState(scope: 'global');
      globalState.confidenceThreshold = 0.65;
      await sttStateRepo.save(globalState);

      // User A gets global state
      var stateA = await sttStateRepo.getCurrent(userId: 'user_a');
      expect(stateA.scope, 'global');
      expect(stateA.confidenceThreshold, 0.65);

      // User A provides feedback, creates personalized state
      final userAState = STTAdaptationState(
        scope: 'user',
        userId: 'user_a',
      );
      userAState.confidenceThreshold = 0.55; // User A speaks clearly
      userAState.version = 0;
      await sttStateRepo.save(userAState);

      // User A now gets personalized state
      stateA = await sttStateRepo.getCurrent(userId: 'user_a');
      expect(stateA.scope, 'user');
      expect(stateA.confidenceThreshold, 0.55);

      // User B still gets global state
      var stateB = await sttStateRepo.getCurrent(userId: 'user_b');
      expect(stateB.scope, 'global');
      expect(stateB.confidenceThreshold, 0.65);
    });

    test('Optimistic locking prevents concurrent updates', () async {
      // Create initial state
      var state = STTAdaptationState(scope: 'global');
      state.version = 0;
      await sttStateRepo.save(state);

      // Simulate concurrent update
      state.confidenceThreshold = 0.70;
      state.version = 1;
      var updated = await sttStateRepo.updateWithVersion(state);
      expect(updated, true);

      // Try to update with stale version
      final staleState = STTAdaptationState(scope: 'global');
      staleState.uuid = state.uuid;
      staleState.confidenceThreshold = 0.75;
      staleState.version = 0; // Stale version!

      updated = await sttStateRepo.updateWithVersion(staleState);
      expect(updated, false); // Conflict detected

      // State should not have changed
      final current = await sttStateRepo.getCurrent();
      expect(current.confidenceThreshold, 0.70);
    });
  });
}
