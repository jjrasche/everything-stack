/// # Trainable Services Providers
///
/// Riverpod providers for accessing Trainable services (STT, Intent, LLM, TTS)
/// and their associated repositories.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/services/trainable.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/intent_engine_trainable.dart';
import 'package:everything_stack_template/services/llm_service_trainable.dart';
import 'package:everything_stack_template/services/tts_service_trainable.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/turn_repository.dart';
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';
import 'package:everything_stack_template/repositories/adaptation_state_repository_impl.dart';
import 'package:everything_stack_template/repositories/turn_repository_impl.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';

/// STT Invocation Repository (in-memory for Phase 0)
final sttInvocationRepositoryProvider = Provider<InvocationRepository<STTInvocation>>((ref) {
  return STTInvocationRepositoryImpl.inMemory();
});

/// Intent Invocation Repository
final intentInvocationRepositoryProvider = Provider<InvocationRepository<IntentInvocation>>((ref) {
  return IntentInvocationRepositoryImpl.inMemory();
});

/// LLM Invocation Repository
final llmInvocationRepositoryProvider = Provider<InvocationRepository<LLMInvocation>>((ref) {
  return LLMInvocationRepositoryImpl.inMemory();
});

/// TTS Invocation Repository
final ttsInvocationRepositoryProvider = Provider<InvocationRepository<TTSInvocation>>((ref) {
  return TTSInvocationRepositoryImpl.inMemory();
});

/// Feedback Repository (shared across all components)
final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepositoryImpl.inMemory();
});

/// Turn Repository
final turnRepositoryProvider = Provider<TurnRepository>((ref) {
  return TurnRepositoryImpl.inMemory();
});

/// STT Adaptation State Repository
final sttAdaptationStateRepositoryProvider = Provider<AdaptationStateRepository<STTAdaptationState>>((ref) {
  return STTAdaptationStateRepositoryImpl.inMemory();
});

/// Intent Adaptation State Repository
final intentAdaptationStateRepositoryProvider = Provider<AdaptationStateRepository<IntentAdaptationState>>((ref) {
  return IntentAdaptationStateRepositoryImpl.inMemory();
});

/// LLM Adaptation State Repository
final llmAdaptationStateRepositoryProvider = Provider<AdaptationStateRepository<LLMAdaptationState>>((ref) {
  return LLMAdaptationStateRepositoryImpl.inMemory();
});

/// TTS Adaptation State Repository
final ttsAdaptationStateRepositoryProvider = Provider<AdaptationStateRepository<TTSAdaptationState>>((ref) {
  return TTSAdaptationStateRepositoryImpl.inMemory();
});

/// STT Trainable Service
final sttTrainableProvider = Provider<Trainable>((ref) {
  final invocationRepo = ref.watch(sttInvocationRepositoryProvider);
  final feedbackRepo = ref.watch(feedbackRepositoryProvider);
  final stateRepo = ref.watch(sttAdaptationStateRepositoryProvider);

  return STTService(
    invocationRepository: invocationRepo,
    feedbackRepository: feedbackRepo,
    adaptationStateRepository: stateRepo,
  );
});

/// Intent Engine Trainable Service
final intentTrainableProvider = Provider<Trainable>((ref) {
  final invocationRepo = ref.watch(intentInvocationRepositoryProvider);
  final feedbackRepo = ref.watch(feedbackRepositoryProvider);
  final stateRepo = ref.watch(intentAdaptationStateRepositoryProvider);

  return IntentEngineTrainable(
    invocationRepository: invocationRepo,
    feedbackRepository: feedbackRepo,
    adaptationStateRepository: stateRepo,
  );
});

/// LLM Trainable Service
final llmTrainableProvider = Provider<Trainable>((ref) {
  final invocationRepo = ref.watch(llmInvocationRepositoryProvider);
  final feedbackRepo = ref.watch(feedbackRepositoryProvider);
  final stateRepo = ref.watch(llmAdaptationStateRepositoryProvider);

  return LLMServiceTrainable(
    invocationRepository: invocationRepo,
    feedbackRepository: feedbackRepo,
    adaptationStateRepository: stateRepo,
  );
});

/// TTS Trainable Service
final ttsTrainableProvider = Provider<Trainable>((ref) {
  final invocationRepo = ref.watch(ttsInvocationRepositoryProvider);
  final feedbackRepo = ref.watch(feedbackRepositoryProvider);
  final stateRepo = ref.watch(ttsAdaptationStateRepositoryProvider);

  return TTSServiceTrainable(
    invocationRepository: invocationRepo,
    feedbackRepository: feedbackRepo,
    adaptationStateRepository: stateRepo,
  );
});
