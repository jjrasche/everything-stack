import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/turn.dart';

void main() {
  group('Turn Entity', () {
    test('creates turn with conversation context', () {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      expect(turn.conversationId, 'conv_123');
      expect(turn.turnIndex, 1);
      expect(turn.markedForFeedback, false);
      expect(turn.sttInvocationId, null);
      expect(turn.intentInvocationId, null);
      expect(turn.llmInvocationId, null);
      expect(turn.ttsInvocationId, null);
    });

    test('marks turn for feedback', () {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      turn.markedForFeedback = true;
      turn.markedAt = DateTime.now();

      expect(turn.markedForFeedback, true);
      expect(turn.markedAt, isNotNull);
    });

    test('stores component invocation IDs', () {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      turn.sttInvocationId = 'stt_inv_001';
      turn.intentInvocationId = 'intent_inv_001';
      turn.llmInvocationId = 'llm_inv_001';
      turn.ttsInvocationId = 'tts_inv_001';

      expect(turn.sttInvocationId, 'stt_inv_001');
      expect(turn.intentInvocationId, 'intent_inv_001');
      expect(turn.llmInvocationId, 'llm_inv_001');
      expect(turn.ttsInvocationId, 'tts_inv_001');
    });

    test('returns only existing invocation IDs', () {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      turn.sttInvocationId = 'stt_inv_001';
      turn.llmInvocationId = 'llm_inv_001';

      final existingIds = turn.getExistingInvocationIds();

      expect(existingIds.length, 2);
      expect(existingIds, contains('stt_inv_001'));
      expect(existingIds, contains('llm_inv_001'));
      expect(existingIds, isNot(contains(null)));
    });

    test('handles null invocation IDs', () {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      final existingIds = turn.getExistingInvocationIds();

      expect(existingIds.isEmpty, true);
    });
  });
}
