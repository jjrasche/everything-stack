// Export base service types for GetIt registration
export 'package:everything_stack_template/services/llm_service.dart' show LLMService, Message, LLMResponse, LLMTool;
export 'package:everything_stack_template/services/stt_service.dart' show STTService;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';

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
      content: 'This is a mock LLM response generated without calling any external API.',
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
  Future<String> recordInvocation(dynamic invocation) async => 'mock_invocation_id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => Container();
}

/// Mock STT Service - returns test transcription without processing audio
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
  Future<String> recordInvocation(dynamic invocation) async => 'mock_invocation_id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => Container();
}
