// Export base service types for GetIt registration
export 'package:everything_stack_template/services/llm_service.dart'
    show LLMService, Message, LLMResponse, LLMTool;
export 'package:everything_stack_template/services/stt_service.dart'
    show STTService, STTException;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/services/events/transcription_complete.dart';

/// Mock LLM Service - returns test response without hitting API
class MockLLMService extends LLMService {
  @override
  Future<void> initialize() async {}

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    yield 'Mock response to: $userMessage';
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    print('🤖 MockLLMService: Returning mock response (no API call)');
    return LLMResponse(
      id: 'mock_response_${DateTime.now().millisecondsSinceEpoch}',
      content:
          'This is a mock LLM response generated without calling any external API.',
      toolCalls: [],
      tokensUsed: 42,
    );
  }

  @override
  void dispose() {}

  @override
  bool get isReady => true;

  // Implement Trainable interface
  @override
  Future<String> recordInvocation(dynamic invocation) async =>
      'mock_invocation_id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => Container();
}

/// Mock STT Service - returns test transcription without processing audio
///
/// **LEGACY:** Use [EnhancedMockSTTService] for tests that need realistic stream handling.
/// This service ignores the input stream - useful for fast unit tests but not E2E.
class MockSTTService extends STTService {
  @override
  Future<void> initialize() async {}

  @override
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    print('🎤 MockSTTService: Returning mock transcription (no API call)');
    // Return a subscription that yields mock transcript
    return stream(
      input: audio,
      onData: onTranscript,
      onUtteranceEnd: onUtteranceEnd,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    print('🎤 MockSTTService: Creating mock stream subscription');

    // Create a mock stream that yields one transcript
    final controller = StreamController<String>();

    // Schedule the mock response
    Future.delayed(Duration(milliseconds: 100), () {
      if (!controller.isClosed) {
        onData('mock transcription from audio');
        onUtteranceEnd?.call();
      }
    }).then((_) {
      if (!controller.isClosed) {
        controller.close();
      }
    });

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  void dispose() {}

  @override
  bool get isReady => true;

  // Implement Trainable interface
  @override
  Future<String> recordInvocation(dynamic invocation) async =>
      'mock_invocation_id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => Container();
}

/// Enhanced Mock STT Service - Actually processes input stream
///
/// **For E2E testing:** Configurable transcript, consumes audio bytes from input stream.
/// This proves the streaming layer works without hitting real APIs.
///
/// **IMPORTANT:** Publishes TranscriptionComplete event to EventBus to trigger orchestration.
/// This is realistic because real STT services publish events after transcription.
///
/// ## Usage
/// ```dart
/// GetIt.instance.registerSingleton<STTService>(
///   EnhancedMockSTTService(
///     transcriptToEmit: 'What is the weather today?',
///     processingDelay: Duration(milliseconds: 150),
///   )
/// );
/// ```
///
/// ## What it verifies
/// - ✅ Input stream is properly consumed (audio bytes received)
/// - ✅ Transcript is emitted (onData called)
/// - ✅ Utterance end signaled (onUtteranceEnd called)
/// - ✅ TranscriptionComplete event published to EventBus
/// - ✅ Orchestration triggered (event → Coordinator listener)
/// - ✅ Graceful cleanup (onDone called)
class EnhancedMockSTTService extends STTService {
  final String transcriptToEmit;
  final Duration processingDelay;

  EnhancedMockSTTService({
    this.transcriptToEmit = 'mock transcription',
    this.processingDelay = const Duration(milliseconds: 100),
  });

  @override
  Future<void> initialize() async {}

  @override
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    return stream(
      input: audio,
      onData: onTranscript,
      onUtteranceEnd: onUtteranceEnd,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    print('🎤 EnhancedMockSTTService: Processing audio stream');

    final controller = StreamController<String>();
    var totalBytes = 0;

    // CRITICAL: Actually consume the input stream
    // This proves the caller is providing audio data correctly
    input.listen(
      (audioBytes) {
        totalBytes += audioBytes.length;
        print('   📨 Received ${audioBytes.length} bytes (total: $totalBytes)');
      },
      onError: (error) {
        print('   ❌ Audio stream error: $error');
        onError(error);
        controller.addError(error);
      },
      onDone: () {
        print('   ✅ Stream ended: $totalBytes total bytes processed');

        // After consuming stream, emit configured transcript
        Future.delayed(processingDelay, () async {
          if (totalBytes > 0) {
            print('   📤 Emitting transcript: "$transcriptToEmit"');
            onData(transcriptToEmit);
            if (!controller.isClosed) {
              controller.add(transcriptToEmit);
            }
            print('   🔊 Signaling utterance end');
            onUtteranceEnd?.call();

            // CRITICAL: Publish TranscriptionComplete event to trigger orchestration
            // This is what real STT services do - they publish an event after transcription
            try {
              final eventBus = GetIt.instance<EventBus>();
              final correlationId =
                  'stt_${DateTime.now().millisecondsSinceEpoch}';
              final event = TranscriptionComplete(
                transcript: transcriptToEmit,
                durationMs: (totalBytes ~/ 16000 * 1000), // Rough estimate
                confidence: 0.95,
                correlationId: correlationId,
              );
              print(
                  '   📡 Publishing TranscriptionComplete event to EventBus (correlationId: $correlationId)');
              await eventBus.publish(event);
              print(
                  '   ✅ Event published - Coordinator listener should trigger');
            } catch (e) {
              print('   ⚠️ Failed to publish event: $e');
              // Don't fail - the onData callback already happened
            }
          } else {
            print('   ❌ No audio data received - emitting error');
            final error = STTException('No audio data received');
            onError(error);
            if (!controller.isClosed) {
              controller.addError(error);
            }
          }
          print('   🏁 Signaling done');
          onDone?.call();
          if (!controller.isClosed) {
            controller.close();
          }
        });
      },
    );

    // Return subscription to the controller's stream
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  void dispose() {}

  @override
  bool get isReady => true;

  // Implement Trainable interface
  @override
  Future<String> recordInvocation(dynamic invocation) async =>
      'enhanced_mock_invocation_id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => Container();
}
