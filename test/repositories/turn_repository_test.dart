import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/repositories/turn_repository_impl.dart';

void main() {
  late TurnRepositoryImpl repository;

  setUp(() {
    // Use in-memory implementation for testing
    repository = TurnRepositoryImpl.inMemory();
  });

  group('TurnRepository', () {
    test('saves and retrieves turn', () async {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      await repository.save(turn);
      final retrieved = await repository.findById(turn.uuid);

      expect(retrieved, isNotNull);
      expect(retrieved!.conversationId, 'conv_123');
      expect(retrieved.turnIndex, 1);
    });

    test('finds all turns in conversation', () async {
      final turn1 = Turn(conversationId: 'conv_123', turnIndex: 0);
      final turn2 = Turn(conversationId: 'conv_123', turnIndex: 1);
      final turn3 = Turn(conversationId: 'conv_456', turnIndex: 0);

      await repository.save(turn1);
      await repository.save(turn2);
      await repository.save(turn3);

      final turns = await repository.findByConversation('conv_123');

      expect(turns.length, 2);
      expect(turns[0].turnIndex, 0);
      expect(turns[1].turnIndex, 1);
    });

    test('stores component invocation IDs', () async {
      final turn = Turn(
        conversationId: 'conv_123',
        turnIndex: 1,
      );

      turn.sttInvocationId = 'stt_001';
      turn.intentInvocationId = 'intent_001';
      turn.llmInvocationId = 'llm_001';
      turn.ttsInvocationId = 'tts_001';

      await repository.save(turn);
      final retrieved = await repository.findById(turn.uuid);

      expect(retrieved!.sttInvocationId, 'stt_001');
      expect(retrieved.intentInvocationId, 'intent_001');
      expect(retrieved.llmInvocationId, 'llm_001');
      expect(retrieved.ttsInvocationId, 'tts_001');
    });

    test('finds marked turns for feedback', () async {
      final turn1 = Turn(conversationId: 'conv_123', turnIndex: 0);
      final turn2 = Turn(conversationId: 'conv_123', turnIndex: 1);
      final turn3 = Turn(conversationId: 'conv_123', turnIndex: 2);

      turn2.markedForFeedback = true;
      turn2.markedAt = DateTime.now();

      await repository.save(turn1);
      await repository.save(turn2);
      await repository.save(turn3);

      final marked = await repository.findMarkedForFeedbackByConversation('conv_123');

      expect(marked.length, 1);
      expect(marked[0].turnIndex, 1);
    });

    test('deletes turn', () async {
      final turn = Turn(conversationId: 'conv_123', turnIndex: 1);

      await repository.save(turn);
      final deleted = await repository.delete(turn.uuid);
      final retrieved = await repository.findById(turn.uuid);

      expect(deleted, true);
      expect(retrieved, null);
    });
  });
}
