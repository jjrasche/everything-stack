import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/invocations.dart';

void main() {
  group('STTInvocation', () {
    test('creates invocation with audio context', () {
      final inv = STTInvocation(
        audioId: 'audio_001',
        output: 'set a reminder',
        confidence: 0.92,
      );

      expect(inv.componentType, 'stt');
      expect(inv.contextType, 'conversation');
      expect(inv.audioId, 'audio_001');
      expect(inv.output, 'set a reminder');
      expect(inv.confidence, 0.92);
      expect(inv.retryCount, 0);
    });

    test('tracks retry count', () {
      final inv = STTInvocation(
        audioId: 'audio_001',
        output: 'result',
        confidence: 0.9,
      );

      inv.retryCount = 2;
      inv.lastError = 'network timeout';

      expect(inv.retryCount, 2);
      expect(inv.lastError, 'network timeout');
    });

    test('creates retry invocation', () {
      final retry = STTInvocation(
        audioId: 'audio_001',
        output: '',
        confidence: 0.0,
      )..contextType = 'retry';

      expect(retry.contextType, 'retry');
    });
  });

  group('IntentInvocation', () {
    test('creates invocation with slot data', () {
      final inv = IntentInvocation(
        transcription: 'set a reminder for 3pm',
        toolName: 'reminder',
        slotsJson: '{"title":"meeting","time":"3pm"}',
        confidence: 0.85,
      );

      expect(inv.componentType, 'intent');
      expect(inv.toolName, 'reminder');
      expect(inv.confidence, 0.85);
      expect(inv.retryCount, 0);
    });

    test('handles missing tool (conversational)', () {
      final inv = IntentInvocation(
        transcription: 'what time is it',
        toolName: '',
        slotsJson: '{}',
        confidence: 0.0,
      );

      expect(inv.toolName, isEmpty);
    });
  });

  group('LLMInvocation', () {
    test('creates invocation with prompt reference', () {
      final inv = LLMInvocation(
        systemPromptVersion: 'v1.2.3',
        conversationHistoryLength: 3,
        response: 'I can help you set that reminder.',
        tokenCount: 42,
      );

      expect(inv.componentType, 'llm');
      expect(inv.systemPromptVersion, 'v1.2.3');
      expect(inv.conversationHistoryLength, 3);
      expect(inv.tokenCount, 42);
      expect(inv.stopReason, '');
    });

    test('tracks stop reason', () {
      final inv = LLMInvocation(
        systemPromptVersion: 'v1.2.3',
        conversationHistoryLength: 0,
        response: 'response',
        tokenCount: 10,
      )..stopReason = 'stop';

      expect(inv.stopReason, 'stop');
    });
  });

  group('TTSInvocation', () {
    test('creates invocation with audio output', () {
      final inv = TTSInvocation(
        text: 'I can help you set that reminder.',
        audioId: 'audio_resp_001',
      );

      expect(inv.componentType, 'tts');
      expect(inv.text, 'I can help you set that reminder.');
      expect(inv.audioId, 'audio_resp_001');
      expect(inv.contextType, 'conversation');
    });

    test('handles retries', () {
      final inv = TTSInvocation(
        text: 'response',
        audioId: '',
      )..retryCount = 1;

      expect(inv.retryCount, 1);
    });
  });
}
