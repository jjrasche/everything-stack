import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../core/invocation.dart';
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
    required String eventId,
    required String utterance,
    required List<double> embedding,
    required List<String> availableNamespaces,
  }) async {
    if (availableNamespaces.isEmpty) {
      throw ArgumentError('No namespaces available');
    }

    if (availableNamespaces.length == 1) {
      final selected = availableNamespaces.first;

      final invocation = Invocation(
        eventId: eventId,
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
    var state = await adaptationStateRepo.getForComponent('namespace_selector',
        implementer: null);
    if (state == null) {
      // No adaptation state, return first namespace
      return availableNamespaces.first;
    }
    state.loadData();

    // Score each namespace (for now, equal weight)
    // In future, this will use learned weights from feedback
    final selected = availableNamespaces.first;

    final invocation = Invocation(
      eventId: eventId,
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
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'namespace_selector',
    );

    if (feedbackList.isEmpty) return;

    var state = await adaptationStateRepo.getForComponent('namespace_selector',
        implementer: null, userId: userId);
    if (state == null) return;
    state.loadData();

    for (final feedback in feedbackList) {
      if (!feedback.hasCorrection) continue;

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

        Map<String, dynamic> data = state.data;
        if (selectedNamespace != null &&
            selectedNamespace != correctNamespace) {
          data['wrongSelections'] = (data['wrongSelections'] as int? ?? 0) + 1;
        }

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
    var state = await adaptationStateRepo.getForComponent('namespace_selector',
        implementer: null, userId: userId);
    if (state == null) return {};
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
