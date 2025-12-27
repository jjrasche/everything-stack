/// # Test Configuration
///
/// Mock services for integration testing.
/// These are registered when INTEGRATION_TEST=true.

library;

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

/// Mock LLM Service for testing
class MockLLMServiceForTests implements LLMService {
  @override
  Future<void> initialize() async {
    debugPrint('🤖 [TEST] MockLLMService initialized');
  }

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    yield 'Test response from mock LLM';
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    debugPrint('🤖 [TEST] MockLLMService.chatWithTools called');
    return LLMResponse(
      id: 'test-llm-${DateTime.now().millisecondsSinceEpoch}',
      content: 'This is a test response from the mock LLM service.',
      toolCalls: [],
      tokensUsed: 42,
    );
  }

  @override
  void dispose() {
    debugPrint('🤖 [TEST] MockLLMService disposed');
  }

  @override
  bool get isReady => true;

  @override
  Future<String> recordInvocation(dynamic invocation) async => 'test-inv-id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => const SizedBox();
}

/// Mock TTS Service for testing
class MockTTSServiceForTests implements TTSService {
  final List<String> synthesizedTexts = [];

  @override
  Future<void> initialize() async {
    debugPrint('🔊 [TEST] MockTTSService initialized');
  }

  @override
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  }) async* {
    debugPrint('🔊 [TEST] MockTTSService.synthesize: "$text"');
    synthesizedTexts.add(text);
    // Yield dummy audio bytes (MP3 header)
    yield Uint8List.fromList([0xFF, 0xFB, 0x10, 0x00]);
  }

  @override
  void dispose() {
    debugPrint('🔊 [TEST] MockTTSService disposed');
  }

  @override
  bool get isReady => true;

  @override
  Future<String> recordInvocation(dynamic invocation) async => 'test-inv-id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => const SizedBox();
}

/// Mock Embedding Service for testing
class MockEmbeddingServiceForTests implements EmbeddingService {
  @override
  Future<void> initialize() async {
    debugPrint('📊 [TEST] MockEmbeddingService initialized');
  }

  @override
  Future<List<double>> generate(String text) async {
    debugPrint('📊 [TEST] MockEmbeddingService.generate called');
    // Return dummy 384-dim embedding
    return List.filled(384, 0.1);
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    debugPrint('📊 [TEST] MockEmbeddingService.generateBatch called');
    // Return dummy embeddings for each text
    return List.generate(texts.length, (_) => List.filled(384, 0.1));
  }
}
