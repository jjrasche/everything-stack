import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';

void main() {
  late FeedbackRepositoryImpl repository;

  setUp(() {
    repository = FeedbackRepositoryImpl.inMemory();
  });

  group('FeedbackRepository', () {
    test('saves and retrieves feedback', () async {
      final feedback = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );

      await repository.save(feedback);
      final retrieved = await repository.findByInvocationId('stt_inv_001');

      expect(retrieved.length, 1);
      expect(retrieved[0].action, FeedbackAction.confirm);
    });

    test('finds feedback by turn', () async {
      final fb1 = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
        turnId: 'turn_5',
      );

      final fb2 = Feedback(
        invocationId: 'intent_inv_001',
        componentType: 'intent',
        action: FeedbackAction.correct,
        correctedData: '{"slots": {}}',
        turnId: 'turn_5',
      );

      final fb3 = Feedback(
        invocationId: 'llm_inv_001',
        componentType: 'llm',
        action: FeedbackAction.ignore,
        turnId: 'turn_6',
      );

      await repository.save(fb1);
      await repository.save(fb2);
      await repository.save(fb3);

      final turn5Feedback = await repository.findByTurn('turn_5');

      expect(turn5Feedback.length, 2);
      expect(turn5Feedback.any((f) => f.componentType == 'stt'), true);
      expect(turn5Feedback.any((f) => f.componentType == 'intent'), true);
    });

    test('finds feedback by turn and component', () async {
      final sttFb1 = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
        turnId: 'turn_5',
      );

      final sttFb2 = Feedback(
        invocationId: 'stt_inv_002',
        componentType: 'stt',
        action: FeedbackAction.deny,
        turnId: 'turn_5',
      );

      final intentFb = Feedback(
        invocationId: 'intent_inv_001',
        componentType: 'intent',
        action: FeedbackAction.correct,
        turnId: 'turn_5',
      );

      await repository.save(sttFb1);
      await repository.save(sttFb2);
      await repository.save(intentFb);

      final sttFeedback =
          await repository.findByTurnAndComponent('turn_5', 'stt');

      expect(sttFeedback.length, 2);
      expect(sttFeedback.every((f) => f.componentType == 'stt'), true);
    });

    test('finds background feedback (turnId == null)', () async {
      final conversational = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
        turnId: 'turn_5',
      );

      final background = Feedback(
        invocationId: 'stt_inv_retry_001',
        componentType: 'stt',
        action: FeedbackAction.deny,
        turnId: null,
      );

      await repository.save(conversational);
      await repository.save(background);

      final backgroundFeedback = await repository.findAllBackground();

      expect(backgroundFeedback.length, 1);
      expect(backgroundFeedback[0].turnId, null);
    });

    test('deletes feedback', () async {
      final feedback = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );

      await repository.save(feedback);
      final deleted = await repository.delete(feedback.uuid);
      final retrieved = await repository.findByInvocationId('stt_inv_001');

      expect(deleted, true);
      expect(retrieved.isEmpty, true);
    });
  });
}
