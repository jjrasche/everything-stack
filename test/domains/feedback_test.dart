import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/feedback.dart';

void main() {
  group('Feedback Entity', () {
    test('creates confirm feedback (no correction needed)', () {
      final feedback = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );

      expect(feedback.componentType, 'stt');
      expect(feedback.action, FeedbackAction.confirm);
      expect(feedback.correctedData, null);
    });

    test('creates deny feedback (wrong, no correction)', () {
      final feedback = Feedback(
        invocationId: 'intent_inv_001',
        componentType: 'intent',
        action: FeedbackAction.deny,
      );

      expect(feedback.action, FeedbackAction.deny);
      expect(feedback.correctedData, null);
    });

    test('creates correct feedback with data', () {
      final feedback = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.correct,
        correctedData: 'corrected transcription',
      );

      expect(feedback.action, FeedbackAction.correct);
      expect(feedback.correctedData, 'corrected transcription');
    });

    test('creates ignore feedback (don\'t learn from this)', () {
      final feedback = Feedback(
        invocationId: 'llm_inv_001',
        componentType: 'llm',
        action: FeedbackAction.ignore,
      );

      expect(feedback.action, FeedbackAction.ignore);
    });

    test('links feedback to turn context', () {
      final feedback = Feedback(
        invocationId: 'intent_inv_001',
        componentType: 'intent',
        action: FeedbackAction.deny,
        turnId: 'turn_5',
      );

      expect(feedback.turnId, 'turn_5');
    });

    test('records reason for feedback', () {
      final feedback = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.correct,
        correctedData: 'new text',
        reason: 'Accent made original hard to understand',
      );

      expect(feedback.reason, 'Accent made original hard to understand');
    });

    test('timestamps feedback', () {
      final feedback = Feedback(
        invocationId: 'stt_inv_001',
        componentType: 'stt',
        action: FeedbackAction.confirm,
      );

      expect(feedback.timestamp, isNotNull);
      expect(
        feedback.timestamp.difference(DateTime.now()).inSeconds.abs(),
        lessThan(1),
      );
    });

    test('handles null turnId (background/retry/test context)', () {
      final feedback = Feedback(
        invocationId: 'llm_inv_retry_001',
        componentType: 'llm',
        action: FeedbackAction.ignore,
        turnId: null,
      );

      expect(feedback.turnId, null);
    });
  });

  group('FeedbackAction enum', () {
    test('has all four actions', () {
      expect(FeedbackAction.confirm.name, 'confirm');
      expect(FeedbackAction.deny.name, 'deny');
      expect(FeedbackAction.correct.name, 'correct');
      expect(FeedbackAction.ignore.name, 'ignore');
    });

    test('can parse from string', () {
      expect(
        FeedbackAction.values.firstWhere((a) => a.name == 'confirm'),
        FeedbackAction.confirm,
      );
    });
  });
}
