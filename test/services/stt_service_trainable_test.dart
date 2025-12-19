import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';
import 'package:everything_stack_template/repositories/adaptation_state_repository_impl.dart';

void main() {
  group('STTService implements Trainable', () {
    late STTService sttService;
    late STTInvocationRepositoryImpl invocationRepo;
    late FeedbackRepositoryImpl feedbackRepo;
    late STTAdaptationStateRepositoryImpl stateRepo;

    setUp(() {
      invocationRepo = STTInvocationRepositoryImpl.inMemory();
      feedbackRepo = FeedbackRepositoryImpl.inMemory();
      stateRepo = STTAdaptationStateRepositoryImpl.inMemory();

      sttService = STTService(
        invocationRepository: invocationRepo,
        feedbackRepository: feedbackRepo,
        adaptationStateRepository: stateRepo,
      );
    });

    test('recordInvocation saves STT invocation', () async {
      final inv = STTInvocation(
        audioId: 'audio_001',
        output: 'set a reminder',
        confidence: 0.92,
      );

      final invocationId = await sttService.recordInvocation(inv);

      expect(invocationId, isNotNull);
      final retrieved = await invocationRepo.findById(invocationId);
      expect(retrieved!.output, 'set a reminder');
      expect(retrieved.confidence, 0.92);
    });

    test('getAdaptationState returns current state', () async {
      final state = await sttService.getAdaptationState();

      expect(state, isA<Map<String, dynamic>>());
      expect(state['confidenceThreshold'], 0.65);
      expect(state['minFeedbackCount'], 10);
    });

    test('trainFromFeedback lowers threshold when user confirms low-confidence',
        () async {
      // Setup: User has high-confidence utterance that was confirmed
      final highConfInv = STTInvocation(
        audioId: 'audio_1',
        output: 'set a reminder',
        confidence: 0.90,
      );
      await invocationRepo.save(highConfInv);

      // User has low-confidence utterance that was ALSO confirmed
      final lowConfInv = STTInvocation(
        audioId: 'audio_2',
        output: 'set a timer',
        confidence: 0.55, // Below default threshold (0.65)
      );
      await invocationRepo.save(lowConfInv);

      // Create feedback: both confirmed
      final highConfFeedback = Feedback(
        invocationId: highConfInv.uuid,
        turnId: 'turn_1',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(highConfFeedback);

      final lowConfFeedback = Feedback(
        invocationId: lowConfInv.uuid,
        turnId: 'turn_2',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(lowConfFeedback);

      // Train on turn_2 (the low-confidence turn that was correct)
      await sttService.trainFromFeedback('turn_2');

      final newState = await sttService.getAdaptationState();
      // Threshold should be lowered (0.65 * 0.95 = ~0.6175)
      expect(newState['confidenceThreshold'], lessThan(0.65));
    });

    test('trainFromFeedback raises threshold when user denies high-confidence',
        () async {
      // User has high-confidence utterance that was DENIED
      final highConfInv = STTInvocation(
        audioId: 'audio_1',
        output: 'wrong transcription',
        confidence: 0.85, // Above default threshold (0.65)
      );
      await invocationRepo.save(highConfInv);

      final deniedFeedback = Feedback(
        invocationId: highConfInv.uuid,
        turnId: 'turn_1',
        componentType: 'stt',
        action: FeedbackAction.deny,
      );
      await feedbackRepo.save(deniedFeedback);

      // Train on turn_1
      await sttService.trainFromFeedback('turn_1');

      final newState = await sttService.getAdaptationState();
      // Threshold should be raised (0.65 * 1.05 = ~0.6825)
      expect(newState['confidenceThreshold'], greaterThan(0.65));
    });

    test('trainFromFeedback ignores feedback with ignore action', () async {
      final inv = STTInvocation(
        audioId: 'audio_1',
        output: 'text',
        confidence: 0.50,
      );
      await invocationRepo.save(inv);

      final ignoredFeedback = Feedback(
        invocationId: inv.uuid,
        turnId: 'turn_1',
        componentType: 'stt',
        action: FeedbackAction.ignore,
      );
      await feedbackRepo.save(ignoredFeedback);

      await sttService.trainFromFeedback('turn_1');

      final newState = await sttService.getAdaptationState();
      // Threshold should not change
      expect(newState['confidenceThreshold'], 0.65);
    });

    test('trainFromFeedback requires minimum feedback count before updating',
        () async {
      final inv = STTInvocation(
        audioId: 'audio_1',
        output: 'text',
        confidence: 0.50,
      );
      await invocationRepo.save(inv);

      // Only 1 feedback (min is 10 by default)
      final feedback = Feedback(
        invocationId: inv.uuid,
        turnId: 'turn_1',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(feedback);

      await sttService.trainFromFeedback('turn_1');

      final newState = await sttService.getAdaptationState();
      // Threshold should not change (not enough feedback)
      expect(newState['confidenceThreshold'], 0.65);
    });

    test('trainFromFeedback with minFeedbackCount=1 updates immediately',
        () async {
      // Create custom state with minFeedbackCount=1
      var state = STTAdaptationState(scope: 'global');
      state.minFeedbackCount = 1;
      await stateRepo.save(state);

      final inv = STTInvocation(
        audioId: 'audio_1',
        output: 'text',
        confidence: 0.50, // Below threshold
      );
      await invocationRepo.save(inv);

      final feedback = Feedback(
        invocationId: inv.uuid,
        turnId: 'turn_1',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(feedback);

      await sttService.trainFromFeedback('turn_1');

      final newState = await sttService.getAdaptationState();
      // Now threshold SHOULD change
      expect(newState['confidenceThreshold'], lessThan(0.65));
    });

    test('trainFromFeedback tracks version and audit trail', () async {
      var state = STTAdaptationState(scope: 'global');
      state.minFeedbackCount = 1;
      await stateRepo.save(state);

      final inv = STTInvocation(
        audioId: 'audio_1',
        output: 'text',
        confidence: 0.55,
      );
      await invocationRepo.save(inv);

      final feedback = Feedback(
        invocationId: inv.uuid,
        turnId: 'turn_1',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );
      await feedbackRepo.save(feedback);

      await sttService.trainFromFeedback('turn_1');

      final newState = await sttService.getAdaptationState();
      expect(newState['version'], 1);
      expect(newState['lastUpdateReason'], 'trainFromFeedback');
      expect(newState['feedbackCountApplied'], 1);
    });

    test('buildFeedbackUI returns a widget', () {
      final widget = sttService.buildFeedbackUI('invocation_123');

      expect(widget, isNotNull);
      // Widget is returned (can't test much without running Flutter)
    });
  });
}
