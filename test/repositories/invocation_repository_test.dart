import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';

void main() {
  group('STTInvocationRepository', () {
    late STTInvocationRepositoryImpl repository;

    setUp(() {
      repository = STTInvocationRepositoryImpl.inMemory();
    });

    test('saves and retrieves STT invocation', () async {
      final inv = STTInvocation(
        audioId: 'audio_001',
        output: 'set a reminder',
        confidence: 0.92,
      );

      await repository.save(inv);
      final retrieved = await repository.findById(inv.uuid);

      expect(retrieved, isNotNull);
      expect(retrieved!.output, 'set a reminder');
      expect(retrieved.confidence, 0.92);
    });

    test('filters by context type', () async {
      final conv = STTInvocation(
        audioId: 'audio_001',
        output: 'text',
        confidence: 0.9,
      )..contextType = 'conversation';

      final retry = STTInvocation(
        audioId: 'audio_002',
        output: 'retry',
        confidence: 0.8,
      )..contextType = 'retry';

      await repository.save(conv);
      await repository.save(retry);

      final conversational = await repository.findByContextType('conversation');
      final retries = await repository.findByContextType('retry');

      expect(conversational.length, 1);
      expect(retries.length, 1);
    });

    test('finds multiple invocations by IDs', () async {
      final inv1 = STTInvocation(
        audioId: 'audio_001',
        output: 'text1',
        confidence: 0.9,
      );
      final inv2 = STTInvocation(
        audioId: 'audio_002',
        output: 'text2',
        confidence: 0.8,
      );

      await repository.save(inv1);
      await repository.save(inv2);

      final found = await repository.findByIds([inv1.uuid, inv2.uuid]);

      expect(found.length, 2);
      expect(found.any((i) => i.output == 'text1'), true);
      expect(found.any((i) => i.output == 'text2'), true);
    });

    test('deletes invocation', () async {
      final inv = STTInvocation(
        audioId: 'audio_001',
        output: 'text',
        confidence: 0.9,
      );

      await repository.save(inv);
      final deleted = await repository.delete(inv.uuid);
      final retrieved = await repository.findById(inv.uuid);

      expect(deleted, true);
      expect(retrieved, null);
    });
  });

  group('IntentInvocationRepository', () {
    late IntentInvocationRepositoryImpl repository;

    setUp(() {
      repository = IntentInvocationRepositoryImpl.inMemory();
    });

    test('saves and retrieves Intent invocation', () async {
      final inv = IntentInvocation(
        transcription: 'set a reminder for 3pm',
        toolName: 'reminder',
        slotsJson: '{"title":"meeting"}',
        confidence: 0.85,
      );

      await repository.save(inv);
      final retrieved = await repository.findById(inv.uuid);

      expect(retrieved, isNotNull);
      expect(retrieved!.toolName, 'reminder');
    });
  });

  group('LLMInvocationRepository', () {
    late LLMInvocationRepositoryImpl repository;

    setUp(() {
      repository = LLMInvocationRepositoryImpl.inMemory();
    });

    test('saves and retrieves LLM invocation', () async {
      final inv = LLMInvocation(
        systemPromptVersion: 'v1.2.3',
        conversationHistoryLength: 3,
        response: 'I can help you set that reminder.',
        tokenCount: 42,
      );

      await repository.save(inv);
      final retrieved = await repository.findById(inv.uuid);

      expect(retrieved, isNotNull);
      expect(retrieved!.systemPromptVersion, 'v1.2.3');
      expect(retrieved.tokenCount, 42);
    });
  });

  group('TTSInvocationRepository', () {
    late TTSInvocationRepositoryImpl repository;

    setUp(() {
      repository = TTSInvocationRepositoryImpl.inMemory();
    });

    test('saves and retrieves TTS invocation', () async {
      final inv = TTSInvocation(
        text: 'I can help you set that reminder.',
        audioId: 'audio_resp_001',
      );

      await repository.save(inv);
      final retrieved = await repository.findById(inv.uuid);

      expect(retrieved, isNotNull);
      expect(retrieved!.audioId, 'audio_resp_001');
    });
  });
}
