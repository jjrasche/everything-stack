/// Mock Service Setup for Integration Testing
///
/// Creates real services (InferenceService, STTService, TTSService) with mock
/// implementers injected. This gives us:
/// - Real orchestration logic (adaptation state reading, invocation logging)
/// - Mocked external API calls (no Groq, Deepgram, or TTS APIs hit)
/// - Same test logic works for both SMOKE_TEST modes

import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/implementations/llm_implementer.dart';
import 'package:everything_stack_template/services/implementations/stt_implementer.dart';
import 'package:everything_stack_template/services/implementations/tts_implementer.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/adaptation_state.dart';
import 'package:everything_stack_template/domain/feedback.dart' as domain_feedback;
import 'package:everything_stack_template/core/feedback.dart' as core_feedback;
import 'mock_groq_implementer.dart';
import 'mock_deepgram_implementer.dart';
import 'mock_flutter_tts_implementer.dart';

// ============================================================================
// Mock Repositories (for services that need to persist/query data)
// ============================================================================

class _MockInvocationRepository implements InvocationRepository<Invocation> {
  @override
  Future<Invocation> save(Invocation entity) async => entity;

  @override
  Future<Invocation?> findById(String id) async => null;

  @override
  Future<List<Invocation>> findAll() async => [];

  @override
  Future<bool> delete(String id) async => false;

  @override
  Future<int> deleteByTurn(String turnId) async => 0;

  @override
  Future<List<Invocation>> findByTurn(String turnId) async => [];

  @override
  Future<List<Invocation>> findByContextType(String contextType) async => [];

  @override
  Future<List<Invocation>> findByIds(List<String> ids) async => [];
}

class _MockAdaptationStateRepository implements AdaptationStateRepository {
  @override
  Future<AdaptationState?> getForComponent(
    String componentType, {
    required String? implementer,
    String? userId,
  }) async => null;

  @override
  Future<List<AdaptationState>> findByComponentAndImplementer(
    String componentType, {
    required String? implementer,
  }) async => [];

  @override
  Future<bool> updateWithVersion(AdaptationState state) async => true;

  @override
  Future<AdaptationState> save(AdaptationState state) async => state;

  @override
  Future<bool> delete(String id) async => false;

  @override
  AdaptationState createDefault(
    String componentType, {
    required String? implementer,
    String? userId,
  }) => AdaptationState(
    componentType: componentType,
    implementer: implementer,
    userId: userId,
    data: {},
  );
}

class _MockFeedbackRepository implements FeedbackRepository {
  @override
  Future<List<domain_feedback.Feedback>> findByInvocationId(String invocationId) async => [];

  @override
  Future<List<domain_feedback.Feedback>> findByInvocationIds(List<String> invocationIds) async => [];

  @override
  Future<List<domain_feedback.Feedback>> findByTurn(String turnId) async => [];

  @override
  Future<List<domain_feedback.Feedback>> findByTurnAndComponent(String turnId, String componentType) async => [];

  @override
  Future<List<domain_feedback.Feedback>> findByContextType(String contextType) async => [];

  @override
  Future<List<domain_feedback.Feedback>> findAllConversational() async => [];

  @override
  Future<List<domain_feedback.Feedback>> findAllBackground() async => [];

  @override
  Future<domain_feedback.Feedback> save(domain_feedback.Feedback feedback) async => feedback;

  @override
  Future<bool> delete(String id) async => false;

  @override
  Future<int> deleteByTurn(String turnId) async => 0;
}

// ============================================================================
// Factory Functions - Create Real Services with Mock Implementers
// ============================================================================

/// Create InferenceService with mock Groq implementer
InferenceService createMockInferenceService() {
  return InferenceService(
    implementers: {'groq': MockGroqImplementer()},
    defaultImplementer: 'groq',
    invocationRepo: _MockInvocationRepository(),
    adaptationStateRepo: _MockAdaptationStateRepository(),
    feedbackRepo: _MockFeedbackRepository(),
  );
}

/// Create STTService with mock Deepgram implementer (basic)
STTService createMockSTTService() {
  return STTService(
    implementers: {'deepgram': MockDeepgramImplementer()},
    defaultImplementer: 'deepgram',
    invocationRepo: _MockInvocationRepository(),
    adaptationStateRepo: _MockAdaptationStateRepository(),
    feedbackRepo: _MockFeedbackRepository(),
  );
}

/// Create STTService with enhanced mock Deepgram (configurable response)
STTService createEnhancedMockSTTService({
  String transcriptToEmit = 'mock transcription',
  Duration processingDelay = const Duration(milliseconds: 100),
}) {
  return STTService(
    implementers: {
      'deepgram': EnhancedMockDeepgramImplementer(
        transcriptToEmit: transcriptToEmit,
        processingDelay: processingDelay,
      )
    },
    defaultImplementer: 'deepgram',
    invocationRepo: _MockInvocationRepository(),
    adaptationStateRepo: _MockAdaptationStateRepository(),
    feedbackRepo: _MockFeedbackRepository(),
  );
}

/// Create TTSService with mock FlutterTTS implementer
TTSService createMockTTSService() {
  return TTSService(
    implementers: {'flutter_tts': MockFlutterTTSImplementer()},
    defaultImplementer: 'flutter_tts',
    invocationRepo: _MockInvocationRepository(),
    adaptationStateRepo: _MockAdaptationStateRepository(),
    feedbackRepo: _MockFeedbackRepository(),
  );
}
