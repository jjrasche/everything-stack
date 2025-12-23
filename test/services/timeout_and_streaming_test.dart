import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/timeout_config.dart';
import 'package:everything_stack_template/services/retry_helper.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/bootstrap/timeout_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('TimeoutConfig', () {
    test('has reasonable timeout values', () {
      expect(TimeoutConfig.httpDefault.inSeconds, 30);
      expect(TimeoutConfig.embeddingGeneration.inSeconds, 45);
      expect(TimeoutConfig.llmStreamingIdle.inSeconds, 10);
      expect(TimeoutConfig.sttConnection.inSeconds, 10);
      expect(TimeoutConfig.ttsGeneration.inSeconds, 20);
    });
  });

  group('TimeoutHttpClient', () {
    test('wraps HTTP client and enforces timeout', () async {
      // Create a mock client that never responds
      final slowClient = MockClient((request) async {
        await Future.delayed(Duration(hours: 1)); // Never completes
        return http.Response('', 200);
      });

      final timeoutClient = TimeoutHttpClient(
        slowClient,
        timeout: Duration(milliseconds: 100),
      );

      // Should timeout
      expect(
        timeoutClient.get(Uri.parse('http://example.com')),
        throwsA(isA<TimeoutHttpException>()),
      );
    });

    test('passes through successful responses', () async {
      final successClient = MockClient((request) async {
        return http.Response('success', 200);
      });

      final timeoutClient = TimeoutHttpClient(successClient);

      final response = await timeoutClient.get(Uri.parse('http://example.com'));
      expect(response.statusCode, 200);
      expect(response.body, 'success');
    });
  });

  group('Retry Helper', () {
    test('retries on failure with exponential backoff', () async {
      int attempts = 0;

      final result = await retryWithBackoff(
        operation: () async {
          attempts++;
          if (attempts < 3) {
            throw Exception('Fail');
          }
          return 'success';
        },
        maxAttempts: 3,
        initialDelay: Duration(milliseconds: 10),
      );

      expect(result, 'success');
      expect(attempts, 3);
    });

    test('gives up after max attempts', () async {
      int attempts = 0;

      expect(
        retryWithBackoff(
          operation: () async {
            attempts++;
            throw Exception('Always fail');
          },
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 10),
        ),
        throwsA(isA<Exception>()),
      );

      await Future.delayed(Duration(milliseconds: 100));
      expect(attempts, 3);
    });

    test('RetryConfig provides sensible defaults', () {
      expect(RetryConfig.quick.maxAttempts, 3);
      expect(RetryConfig.standard.maxAttempts, 3);
      expect(RetryConfig.slow.maxAttempts, 5);
      expect(RetryConfig.critical.maxAttempts, 10);
    });
  });

  group('STTService', () {
    test('NullSTTService is default instance', () {
      expect(STTService.instance, isA<NullSTTService>());
    });

    test('NullSTTService fails gracefully', () {
      final instance = NullSTTService();

      expect(instance.isReady, isFalse);

      final subscription = instance.transcribe(
        audio: Stream.value(Uint8List(0)),
        onTranscript: (_) {},
        onError: expectAsync1((error) {
          expect(error, isA<STTException>());
        }),
      );

      expect(subscription, isNotNull);
    });

    test('DeepgramSTTService initializes', () async {
      // Phase 0: STTService is abstract
      // STT implementations (Deepgram) are deferred to Phase 1
      // This test is deferred
    }, skip: 'STT implementations deferred to Phase 1');
  });

  group('TTSService', () {
    test('NullTTSService is default instance', () {
      expect(TTSService.instance, isA<NullTTSService>());
    });

    test('NullTTSService fails gracefully', () async {
      final instance = NullTTSService();

      expect(instance.isReady, isFalse);

      expect(
        instance.synthesize('test').toList(),
        throwsA(isA<TTSException>()),
      );
    });

    test('GoogleTTSService initializes', () async {
      // Phase 0: TTS uses NullTTSService only
      // TTS implementations (Google) are deferred to Phase 1
      // This test is deferred
    }, skip: 'TTS implementations deferred to Phase 1');
  });

  group('LLMService', () {
    test('NullLLMService is default instance', () {
      expect(LLMService.instance, isA<NullLLMService>());
    });

    test('NullLLMService fails gracefully', () async {
      final instance = NullLLMService();

      expect(instance.isReady, isFalse);

      expect(
        instance.chat(
          history: [],
          userMessage: 'test',
        ).toList(),
        throwsA(isA<LLMException>()),
      );
    });

    test('Message helper constructors work', () {
      final userMsg = Message.user('Hello');
      expect(userMsg.role, 'user');
      expect(userMsg.content, 'Hello');

      final assistantMsg = Message.assistant('Hi there');
      expect(assistantMsg.role, 'assistant');
      expect(assistantMsg.content, 'Hi there');

      final systemMsg = Message.system('You are helpful');
      expect(systemMsg.role, 'system');
      expect(systemMsg.content, 'You are helpful');
    });

    test('Message JSON serialization works', () {
      final msg = Message.user('test');
      final json = msg.toJson();

      expect(json['role'], 'user');
      expect(json['content'], 'test');

      final restored = Message.fromJson(json);
      expect(restored.role, 'user');
      expect(restored.content, 'test');
    });
  });
}
