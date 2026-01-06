// Export base service types for GetIt registration
export 'package:everything_stack_template/services/llm_service.dart' show LLMService, Message, LLMResponse, LLMTool;
export 'package:everything_stack_template/services/stt_service.dart' show STTService;

import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/feedback.dart' as core_feedback;

/// Mock repositories for testing
class _MockInvocationRepo implements InvocationRepository<Invocation> {
  @override
  Future<void> save(Invocation entity) async {}

  @override
  Future<Invocation?> findById(String id) async => null;

  @override
  Future<List<Invocation>> findAll({int offset = 0, int limit = 100}) async => [];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<int> count() async => 0;

  @override
  Future<List<Invocation>> findByQuery(String query) async => [];

  @override
  Future<void> update(Invocation entity) async {}

  @override
  Future<void> deleteWhere(bool Function(Invocation) predicate) async {}

  @override
  Future<void> saveBatch(List<Invocation> entities) async {}
}

class _MockAdaptationStateRepo implements AdaptationStateRepository {
  @override
  Future<void> save(dynamic entity) async {}

  @override
  Future<dynamic> findById(String id) async => null;

  @override
  Future<List<dynamic>> findAll({int offset = 0, int limit = 100}) async => [];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<int> count() async => 0;

  @override
  Future<List<dynamic>> findByQuery(String query) async => [];

  @override
  Future<dynamic> getForComponent(String componentType, {required String? implementer, String? userId}) async => null;

  @override
  Future<void> update(dynamic entity) async {}

  @override
  Future<void> deleteWhere(bool Function(dynamic) predicate) async {}

  @override
  Future<void> saveBatch(List<dynamic> entities) async {}
}

class _MockFeedbackRepo implements FeedbackRepository {
  @override
  Future<void> save(dynamic entity) async {}

  @override
  Future<dynamic> findById(String id) async => null;

  @override
  Future<List<dynamic>> findAll({int offset = 0, int limit = 100}) async => [];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<int> count() async => 0;

  @override
  Future<List<dynamic>> findByQuery(String query) async => [];

  @override
  Future<void> update(dynamic entity) async {}

  @override
  Future<void> deleteWhere(bool Function(dynamic) predicate) async {}

  @override
  Future<void> saveBatch(List<dynamic> entities) async {}
}

/// Mock LLM Service - returns test response without hitting API
class MockLLMService extends LLMService {
  MockLLMService()
      : super(
          implementers: {},
          defaultImplementer: 'mock',
          invocationRepo: _MockInvocationRepo(),
          adaptationStateRepo: _MockAdaptationStateRepo(),
          feedbackRepo: _MockFeedbackRepo(),
        );

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
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) => Container();

  @override
  Future<void> trainFromFeedback(Invocation invocation, core_feedback.Feedback feedback) async {}
}

/// Mock STT Service - returns test transcription without hitting API
class MockSTTService extends STTService {
  MockSTTService()
      : super(
          implementers: {},
          defaultImplementer: 'mock',
          invocationRepo: _MockInvocationRepo(),
          adaptationStateRepo: _MockAdaptationStateRepo(),
          feedbackRepo: _MockFeedbackRepo(),
        );

  @override
  Future<String> recognize({
    required String eventId,
    required String audioId,
    required double durationSeconds,
    String? implementerName,
    String? userId,
  }) async {
    print('🎤 MockSTTService: Returning mock transcription (no API call)');
    return 'mock transcription from audio';
  }

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) => Container();

  @override
  Future<void> trainFromFeedback(Invocation invocation, core_feedback.Feedback feedback) async {}
}

/// Enhanced Mock STT Service - Configurable transcription response
///
/// **For E2E testing:** Allows configuration of transcript text for testing different scenarios.
/// Streaming support will be added when DeepgramImplementer WebSocket logic is implemented.
class EnhancedMockSTTService extends STTService {
  final String transcriptToEmit;
  final Duration processingDelay;

  EnhancedMockSTTService({
    this.transcriptToEmit = 'mock transcription',
    this.processingDelay = const Duration(milliseconds: 100),
  })  : super(
          implementers: {},
          defaultImplementer: 'mock',
          invocationRepo: _MockInvocationRepo(),
          adaptationStateRepo: _MockAdaptationStateRepo(),
          feedbackRepo: _MockFeedbackRepo(),
        );

  @override
  Future<String> recognize({
    required String eventId,
    required String audioId,
    required double durationSeconds,
    String? implementerName,
    String? userId,
  }) async {
    print('🎤 EnhancedMockSTTService: Processing audio (configurable transcript)');
    print('   📝 Duration: ${durationSeconds}s');

    // Simulate processing delay
    await Future.delayed(processingDelay);

    print('   📤 Emitting transcript: "$transcriptToEmit"');
    return transcriptToEmit;
  }

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) => Container();

  @override
  Future<void> trainFromFeedback(Invocation invocation, core_feedback.Feedback feedback) async {}
}
