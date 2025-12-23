/// # Turn Providers
///
/// Riverpod providers for managing turns and feedback state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/ui/providers/trainable_providers.dart';

/// Fetch all turns marked for feedback
final turnsForFeedbackProvider = FutureProvider<List<Turn>>((ref) async {
  final turnRepo = ref.watch(turnRepositoryProvider);
  final turns = await turnRepo.findMarkedForFeedbackByConversation('default');
  return turns;
});

/// Fetch a specific turn by ID
final turnByIdProvider = FutureProvider.family<Turn?, String>((ref, turnId) async {
  final turnRepo = ref.watch(turnRepositoryProvider);
  return await turnRepo.findById(turnId);
});

/// State for currently selected turn during feedback review
final selectedTurnProvider = StateProvider<Turn?>((ref) => null);

/// State for feedback being collected during review
final feedbackFormProvider = StateProvider<Map<String, FeedbackAction>>((ref) => {});

/// State for corrected data being edited
final correctedDataProvider = StateProvider<Map<String, dynamic>>((ref) => {});

/// Fetch feedback for a specific turn and component
final turnFeedbackProvider = FutureProvider.family<List<Feedback>, String>((ref, turnId) async {
  final feedbackRepo = ref.watch(feedbackRepositoryProvider);
  final allFeedback = await feedbackRepo.findByTurn(turnId);
  return allFeedback;
});

/// Fetch a specific invocation (polymorphic - type determined by string)
final invocationByIdProvider = FutureProvider.family<dynamic, (String, String)>((ref, args) async {
  final (invocationId, componentType) = args;

  switch (componentType) {
    case 'stt':
      final repo = ref.watch(sttInvocationRepositoryProvider);
      return await repo.findById(invocationId);
    case 'llm':
      final repo = ref.watch(llmInvocationRepositoryProvider);
      return await repo.findById(invocationId);
    case 'tts':
      final repo = ref.watch(ttsInvocationRepositoryProvider);
      return await repo.findById(invocationId);
    default:
      return null;
  }
});
