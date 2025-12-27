/// # ContextInjector
///
/// ## What it does
/// Trainable component that injects relevant context for a namespace.
/// Example: For 'task' namespace, inject list of incomplete tasks.
/// Example: For 'timer' namespace, inject list of active timers.
///
/// ## Input
/// - namespace: Which namespace
/// - correlationId: For linking
///
/// ## Output
/// - injectedContext: Map of context items
///
/// ## Training
/// When user feedback indicates missing context:
/// - Increase context relevance scores
/// - Track which context items are actually used
/// - Deprioritize irrelevant context

import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../domain/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/adaptation_state_repository.dart';
import '../../core/adaptation_state.dart';
import '../../core/feedback_repository.dart';
import 'dart:convert';

class ContextInjector implements Trainable {
  final InvocationRepository<Invocation> invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  // TODO: Inject actual repositories for tasks, timers, etc.
  // For now, these are placeholders

  ContextInjector({
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  });

  /// Inject context for namespace
  ///
  /// For now, returns empty context.
  /// Will be expanded to inject actual task/timer/subscription data.
  Future<Map<String, dynamic>> injectContext({
    required String correlationId,
    required String namespace,
  }) async {
    // Context injection placeholder
    final injected = <String, dynamic>{};

    // Example: if namespace is 'task', inject tasks
    // if (namespace == 'task') {
    //   injected['tasks'] = await taskRepo.findIncomplete();
    // }
    //
    // Example: if namespace is 'timer', inject timers
    // if (namespace == 'timer') {
    //   injected['timers'] = await timerRepo.findActive();
    // }

    // Record invocation
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'context_injector',
      success: true,
      confidence: 1.0,
      input: {
        'namespace': namespace,
      },
      output: {
        'injectedContext': injected,
      },
    );
    await recordInvocation(invocation);
    return injected;
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
    // Get all feedback for context_injector on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'context_injector',
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

      // Parse corrected data as JSON {missingContext?: ['field1', 'field2']}
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (corrected['missingContext'] is List) {
        final missing = (corrected['missingContext'] as List).cast<String>();

        // Update state data (track missing context fields)
        Map<String, dynamic> data = state.data;
        data['missingContextCount'] =
            (data['missingContextCount'] as int? ?? 0) + missing.length;

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
    // TODO: Implement UI for reviewing injected context
    // Should show what context was available and let user indicate what's missing
    return Placeholder();
  }
}
