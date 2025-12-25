/// # Turn Providers
///
/// Riverpod providers for managing turns and feedback state.
/// Repositories are accessed via ServiceLocator, not Riverpod providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/core/turn_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';
import 'package:everything_stack_template/domain/tts_invocation_repository.dart';
import 'package:everything_stack_template/bootstrap.dart';

/// Fetch all turns marked for feedback
final turnsForFeedbackProvider = FutureProvider<List<Turn>>((ref) async {
  final turnRepo = getIt<TurnRepository>();
  final turns = await turnRepo.findMarkedForFeedbackByConversation('default');
  return turns;
});

/// Fetch a specific turn by ID
final turnByIdProvider =
    FutureProvider.family<Turn?, String>((ref, turnId) async {
  final turnRepo = getIt<TurnRepository>();
  return await turnRepo.findById(turnId);
});

/// State for currently selected turn during feedback review
final selectedTurnProvider = StateProvider<Turn?>((ref) => null);

/// State for feedback being collected during review
final feedbackFormProvider =
    StateProvider<Map<String, FeedbackAction>>((ref) => {});

/// State for corrected data being edited
final correctedDataProvider = StateProvider<Map<String, dynamic>>((ref) => {});

/// Fetch feedback for a specific turn and component
final turnFeedbackProvider =
    FutureProvider.family<List<Feedback>, String>((ref, turnId) async {
  final feedbackRepo = getIt<FeedbackRepository>();
  final allFeedback = await feedbackRepo.findByTurn(turnId);
  return allFeedback;
});

/// Fetch a specific invocation (polymorphic - type determined by string)
final invocationByIdProvider =
    FutureProvider.family<dynamic, (String, String)>((ref, args) async {
  final (invocationId, componentType) = args;

  switch (componentType) {
    case 'llm':
      final repo = getIt<LLMInvocationRepository>();
      return await repo.findByUuid(invocationId);
    case 'tts':
      final repo = getIt<TTSInvocationRepository>();
      return await repo.findByUuid(invocationId);
    default:
      return null;
  }
});
