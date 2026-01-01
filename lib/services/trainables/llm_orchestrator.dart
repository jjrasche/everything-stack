/// # LLMOrchestrator
///
/// ## What it does
/// Trainable component that orchestrates the LLM agentic loop.
/// Learns which tool calling patterns and response strategies work best.
///
/// ## Input
/// - utterance: User's request
/// - namespace: Selected namespace
/// - tools: Available tools
/// - context: Injected context
///
/// ## Output
/// - finalResponse: LLM's final response to user
/// - toolCalls: List of tool calls made during loop
/// - iterations: Number of agentic loop iterations
///
/// ## Training
/// When user feedback indicates issues:
/// - Track which tool combinations worked
/// - Learn when to use tools vs. direct response
/// - Optimize loop iteration count

import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../domain/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/adaptation_state_repository.dart';
import '../../core/adaptation_state.dart';
import '../../core/feedback_repository.dart';
import 'dart:convert';

class LLMOrchestrator implements Trainable {
  final InvocationRepository<Invocation> invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  LLMOrchestrator({
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  });

  /// Record LLM orchestration invocation
  ///
  /// Called after the agentic loop completes.
  Future<void> recordOrchestration({
    required String correlationId,
    required String utterance,
    required String namespace,
    required List<String> tools,
    required Map<String, dynamic> context,
    required String finalResponse,
    required List<String> toolCalls,
    required int iterations,
    required bool success,
  }) async {
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'llm_orchestrator',
      success: success,
      confidence: success ? 1.0 : 0.0,
      input: {
        'utterance': utterance,
        'namespace': namespace,
        'tools': tools,
        'context': context,
      },
      output: {
        'finalResponse': finalResponse,
        'toolCalls': toolCalls,
        'iterations': iterations,
      },
    );
    await recordInvocation(invocation);
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
    // Get all feedback for llm_orchestrator on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'llm_orchestrator',
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

      // Parse corrected data as JSON
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (corrected['quality'] is String) {
        final quality = corrected['quality'] as String;

        // Update state data (track orchestration quality)
        Map<String, dynamic> data = state.data;

        switch (quality) {
          case 'good':
            data['successfulLoops'] = (data['successfulLoops'] as int? ?? 0) + 1;
            break;
          case 'poor':
            data['poorLoops'] = (data['poorLoops'] as int? ?? 0) + 1;
            break;
          case 'toolIssue':
            data['toolErrors'] = (data['toolErrors'] as int? ?? 0) + 1;
            break;
        }

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
    // TODO: Implement UI for rating LLM orchestration quality
    // Should allow user to rate overall response and tool usage
    return Placeholder();
  }
}
