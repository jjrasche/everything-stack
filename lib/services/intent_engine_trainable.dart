/// # IntentEngine (Trainable)
///
/// Extends IntentEngine with Trainable interface for feedback-driven learning.
/// Learns from user corrections to intent classification.

import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/trainable.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';

class IntentEngineTrainable implements Trainable {
  final InvocationRepository<IntentInvocation> _invocationRepository;
  final FeedbackRepository _feedbackRepository;
  final AdaptationStateRepository<IntentAdaptationState>
      _adaptationStateRepository;

  IntentAdaptationState? _currentState;

  IntentEngineTrainable({
    required InvocationRepository<IntentInvocation> invocationRepository,
    required FeedbackRepository feedbackRepository,
    required AdaptationStateRepository<IntentAdaptationState>
        adaptationStateRepository,
  })  : _invocationRepository = invocationRepository,
        _feedbackRepository = feedbackRepository,
        _adaptationStateRepository = adaptationStateRepository;

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! IntentInvocation) {
      throw ArgumentError(
          'Expected IntentInvocation, got ${invocation.runtimeType}');
    }

    final saved = await _invocationRepository.save(invocation);
    return saved.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    var state = await _adaptationStateRepository.getCurrent(userId: userId);

    if (userId != null && state.scope == 'global') {
      state = IntentAdaptationState(scope: 'user', userId: userId);
      state.confidenceThreshold =
          (await _adaptationStateRepository.getGlobal())?.confidenceThreshold ??
              0.65;
    }

    final feedbacks =
        await _feedbackRepository.findByTurnAndComponent(turnId, 'intent');

    if (feedbacks.isEmpty) return;

    // Learning logic:
    // - Denied high-confidence intent → raise overall threshold
    // - Confirmed low-confidence intent → lower overall threshold
    // - Confirmed/denied → update tool-specific thresholds

    double? adjustedThreshold = state.confidenceThreshold;
    int adjustmentCount = 0;

    for (final feedback in feedbacks) {
      if (feedback.action == FeedbackAction.ignore) continue;

      final invocation = await _invocationRepository.findById(feedback.invocationId);
      if (invocation == null) continue;

      // Adjust overall confidence threshold
      if (feedback.action == FeedbackAction.confirm &&
          invocation.confidence < state.confidenceThreshold) {
        adjustedThreshold = adjustedThreshold! * 0.95;
        adjustmentCount++;
      }

      if (feedback.action == FeedbackAction.deny &&
          invocation.confidence >= state.confidenceThreshold) {
        adjustedThreshold = adjustedThreshold! * 1.05;
        adjustmentCount++;
      }

      // Adjust tool-specific confidence
      if (invocation.toolName.isNotEmpty) {
        final toolThreshold =
            state.toolConfidenceThresholds[invocation.toolName] ?? 0.65;

        if (feedback.action == FeedbackAction.deny) {
          state.toolConfidenceThresholds[invocation.toolName] =
              (toolThreshold * 1.05).clamp(0.1, 0.95);
        } else if (feedback.action == FeedbackAction.confirm &&
            invocation.confidence < toolThreshold) {
          state.toolConfidenceThresholds[invocation.toolName] =
              (toolThreshold * 0.95).clamp(0.1, 0.95);
        }
      }
    }

    if (adjustmentCount < state.minFeedbackCount) return;

    state.confidenceThreshold = adjustedThreshold!.clamp(0.1, 0.95);
    state.version++;
    state.lastUpdatedAt = DateTime.now();
    state.lastUpdateReason = 'trainFromFeedback';
    state.feedbackCountApplied = adjustmentCount;

    final updated = await _adaptationStateRepository.updateWithVersion(state);
    if (updated) _currentState = state;
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    if (_currentState != null && _currentState!.userId == userId) {
      return _currentState!.toJson();
    }

    final state = await _adaptationStateRepository.getCurrent(userId: userId);
    _currentState = state;
    return state.toJson();
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    return Center(child: Text('Intent Feedback UI for $invocationId (TODO)'));
  }
}
