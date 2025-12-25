/// # ResponseRenderer
///
/// ## What it does
/// Trainable component that learns how to format/render LLM responses for users.
/// Learns user preferences: concise vs detailed, bullets vs paragraphs, etc.
///
/// ## Input
/// - llmResponse: Raw LLM output text
/// - namespace: Context for rendering
/// - tools: Tools that were used
///
/// ## Output
/// - renderedResponse: Formatted response for user
/// - renderingStyle: {format: 'bullets'|'paragraph', detail: 'concise'|'detailed', tone: ...}
///
/// ## Training
/// When user feedback indicates response format preference:
/// - Track which rendering styles user prefers
/// - Learn per-namespace rendering preferences
/// - Adapt response length based on context

import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../domain/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/adaptation_state_repository.dart';
import '../../domain/adaptation_state_generic.dart';
import '../../core/feedback_repository.dart';
import 'dart:convert';

class ResponseRenderer implements Trainable {
  final InvocationRepository<Invocation> invocationRepo;
  final AdaptationStateRepository<AdaptationState> adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  ResponseRenderer({
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  });

  /// Render LLM response for user
  ///
  /// For now, returns raw response.
  /// Will learn to format based on user feedback.
  Future<String> renderResponse({
    required String correlationId,
    required String llmResponse,
    required String namespace,
    required List<String> tools,
  }) async {
    // Default: return response as-is
    final rendered = llmResponse;

    // Record invocation
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'response_renderer',
      success: true,
      confidence: 1.0,
      input: {
        'llmResponse': llmResponse,
        'namespace': namespace,
        'tools': tools,
      },
      output: {
        'renderedResponse': rendered,
        'renderingStyle': {
          'format': 'paragraph',
          'detail': 'default',
          'tone': 'professional',
        },
      },
    );
    await recordInvocation(invocation);
    return rendered;
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
    // Get all feedback for response_renderer on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'response_renderer',
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

      // Parse corrected data as JSON {preference: 'too-long'|'too-short'|'too-technical', suggestedFormat?: 'bullets'}
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (corrected['preference'] is String) {
        final preference = corrected['preference'] as String;

        // Update state data (track formatting preferences)
        Map<String, dynamic> data = state.data;

        switch (preference) {
          case 'too-long':
            data['tooLongCount'] = (data['tooLongCount'] as int? ?? 0) + 1;
            data['preferredDetail'] = 'concise';
            break;
          case 'too-short':
            data['tooShortCount'] = (data['tooShortCount'] as int? ?? 0) + 1;
            data['preferredDetail'] = 'detailed';
            break;
          case 'too-technical':
            data['tooTechnicalCount'] = (data['tooTechnicalCount'] as int? ?? 0) + 1;
            data['preferredTone'] = 'simple';
            break;
          case 'perfect':
            data['perfectCount'] = (data['perfectCount'] as int? ?? 0) + 1;
            break;
        }

        if (corrected['suggestedFormat'] is String) {
          data['preferredFormat'] = corrected['suggestedFormat'];
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
    // TODO: Implement UI for rating response formatting
    // Should allow user to indicate if response was too long/short/technical
    // and suggest formatting preferences
    return Placeholder();
  }
}
