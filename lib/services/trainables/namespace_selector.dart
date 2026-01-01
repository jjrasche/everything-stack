/// # NamespaceSelector
///
/// ## What it does
/// Trainable component that selects which namespace a user request belongs to.
/// Learns which namespaces are more relevant to different utterances.
///
/// ## Input
/// - utterance: User's spoken/typed request
/// - embedding: Semantic embedding of utterance
/// - availableNamespaces: List of namespace names to choose from
///
/// ## Output
/// - selectedNamespace: Which namespace the request belongs to
///
/// ## Training
/// When user feedback indicates wrong namespace:
/// - Decrease confidence for wrong namespace
/// - Increase confidence for correct namespace
/// - Update semantic similarity scores

import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../domain/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/adaptation_state_repository.dart';
import '../../core/adaptation_state.dart';
import '../../core/feedback_repository.dart';
import 'dart:convert';

class NamespaceSelector implements Trainable {
  final InvocationRepository<Invocation> invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  NamespaceSelector({
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  });

  /// Select namespace for utterance
  ///
  /// For now, returns first namespace if only one, otherwise picks randomly.
  /// Will learn from feedback in future iterations.
  Future<String> selectNamespace({
    required String correlationId,
    required String utterance,
    required List<double> embedding,
    required List<String> availableNamespaces,
  }) async {
    // Validate input
    if (availableNamespaces.isEmpty) {
      throw ArgumentError('No namespaces available');
    }

    if (availableNamespaces.length == 1) {
      final selected = availableNamespaces.first;

      // Record invocation
      final invocation = Invocation(
        correlationId: correlationId,
        componentType: 'namespace_selector',
        success: true,
        confidence: 1.0,
        input: {
          'utterance': utterance,
          'embedding': embedding,
          'availableNamespaces': availableNamespaces,
        },
        output: {
          'selectedNamespace': selected,
        },
      );
      await recordInvocation(invocation);
      return selected;
    }

    // Multiple namespaces - use adaptation state to score
    final state = await adaptationStateRepo.getCurrent();
    state.loadData();

    // Score each namespace (for now, equal weight)
    // In future, this will use learned weights from feedback
    final selected = availableNamespaces.first;

    // Record invocation
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'namespace_selector',
      success: true,
      confidence: 0.5, // Low confidence since we're guessing
      input: {
        'utterance': utterance,
        'embedding': embedding,
        'availableNamespaces': availableNamespaces,
      },
      output: {
        'selectedNamespace': selected,
      },
    );
    await recordInvocation(invocation);
    return selected;
  }

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! Invocation) {
      throw ArgumentError('Expected Invocation');
    }
    await invocationRepo.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // Get all feedback for namespace_selector on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'namespace_selector',
    );

    if (feedbackList.isEmpty) return;

    // Get current adaptation state
    final state = await adaptationStateRepo.getCurrent(userId: userId);
    state.loadData();

    // Process each feedback
    for (final feedback in feedbackList) {
      if (!feedback.hasCorrection) continue;

      // Load the invocation
      final invocation = await invocationRepo.findById(feedback.invocationId);
      if (invocation == null) continue;

      // Parse corrected data as JSON {namespace: 'correct_namespace'}
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (corrected['namespace'] is String) {
        final correctNamespace = corrected['namespace'] as String;
        final selectedNamespace =
            invocation.output?['selectedNamespace'] as String?;

        // Update state data (increment feedback count for correct namespace)
        Map<String, dynamic> data = state.data;
        if (selectedNamespace != null &&
            selectedNamespace != correctNamespace) {
          // Track wrong selections
          data['wrongSelections'] = (data['wrongSelections'] as int? ?? 0) + 1;
        }

        // Track correct selections
        data['correctSelections'] =
            (data['correctSelections'] as int? ?? 0) + 1;

        state.data = data;
        state.version++;
        state.lastUpdatedAt = DateTime.now();
        state.lastUpdateReason = 'trainFromFeedback';
        state.feedbackCountApplied++;

        await adaptationStateRepo.save(state);
      }
    }
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    final state = await adaptationStateRepo.getCurrent(userId: userId);
    state.loadData();
    return state.data;
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement UI for reviewing namespace selection
    // Should show the utterance and selected namespace, allow user to correct
    return Placeholder();
  }
}
