/// # ToolSelector
///
/// ## What it does
/// Trainable component that selects which tools to use for a namespace.
/// Once namespace is determined, this picks specific tools within that namespace.
///
/// ## Input
/// - namespace: Which namespace (from NamespaceSelector)
/// - utterance: User's request
/// - embedding: Semantic embedding
/// - availableTools: Tools available in this namespace
///
/// ## Output
/// - selectedTools: List<String> of tool names to use
///
/// ## Training
/// When user feedback indicates wrong tools:
/// - Decrease confidence for unused tools
/// - Increase confidence for used tools
/// - Update tool selection scores based on utterance keywords

import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../domain/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/adaptation_state_repository.dart';
import '../../domain/adaptation_state_generic.dart';
import '../../core/feedback_repository.dart';
import 'dart:convert';

class ToolSelector implements Trainable {
  final InvocationRepository<Invocation> invocationRepo;
  final AdaptationStateRepository<AdaptationState> adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  ToolSelector({
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  });

  /// Select tools for namespace and utterance
  ///
  /// For now, returns all tools in namespace.
  /// Will learn from feedback to filter irrelevant tools.
  Future<List<String>> selectTools({
    required String correlationId,
    required String namespace,
    required String utterance,
    required List<double> embedding,
    required List<String> availableTools,
  }) async {
    if (availableTools.isEmpty) {
      throw ArgumentError('No tools available in namespace');
    }

    // For now, select all tools (will be filtered based on feedback)
    final selected = availableTools;

    // Record invocation
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'tool_selector',
      success: true,
      confidence: 0.5, // Low confidence since we're selecting all
      input: {
        'namespace': namespace,
        'utterance': utterance,
        'embedding': embedding,
        'availableTools': availableTools,
      },
      output: {
        'selectedTools': selected,
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
    // Get all feedback for tool_selector on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'tool_selector',
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

      // Parse corrected data as JSON {tools: ['tool1', 'tool2']}
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (corrected['tools'] is List) {
        final correctTools = (corrected['tools'] as List).cast<String>();
        final selectedTools =
            (invocation.output?['selectedTools'] as List?)?.cast<String>() ?? [];

        // Update state data (track tool selection accuracy)
        Map<String, dynamic> data = state.data;

        // Count correct/incorrect selections
        final correctSet = correctTools.toSet();
        final selectedSet = selectedTools.toSet();

        final truePositives = selectedSet.intersection(correctSet).length;
        final falsePositives = selectedSet.difference(correctSet).length;

        data['correctTools'] = (data['correctTools'] as int? ?? 0) + truePositives;
        data['wrongTools'] = (data['wrongTools'] as int? ?? 0) + falsePositives;

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
    // TODO: Implement UI for reviewing tool selection
    // Should show selected tools and allow user to correct
    return Placeholder();
  }
}
