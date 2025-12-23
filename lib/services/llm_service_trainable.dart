/// # LLMService (Trainable)
///
/// Extends LLMService with Trainable interface for feedback-driven learning.
/// Learns from user corrections to LLM responses.

import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/trainable.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';

class LLMServiceTrainable implements Trainable {
  final LLMInvocationRepository _invocationRepository;
  final FeedbackRepository _feedbackRepository;
  final AdaptationStateRepository<LLMAdaptationState>
      _adaptationStateRepository;

  LLMAdaptationState? _currentState;

  LLMServiceTrainable({
    required LLMInvocationRepository invocationRepository,
    required FeedbackRepository feedbackRepository,
    required AdaptationStateRepository<LLMAdaptationState>
        adaptationStateRepository,
  })  : _invocationRepository = invocationRepository,
        _feedbackRepository = feedbackRepository,
        _adaptationStateRepository = adaptationStateRepository;

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! LLMInvocation) {
      throw ArgumentError('Expected LLMInvocation, got ${invocation.runtimeType}');
    }

    await _invocationRepository.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    var state = await _adaptationStateRepository.getCurrent(userId: userId);

    if (userId != null && state.scope == 'global') {
      state = LLMAdaptationState(scope: 'user', userId: userId);
    }

    final feedbacks =
        await _feedbackRepository.findByTurnAndComponent(turnId, 'llm');

    if (feedbacks.isEmpty) return;

    // Learning logic:
    // - Corrected response → adjust temperature or prompt variant
    // - Token count trending high → reduce maxTokens
    // Currently simple: just track feedback counts

    int confirmCount = 0;
    int correctCount = 0;
    int denyCount = 0;

    for (final feedback in feedbacks) {
      if (feedback.action == FeedbackAction.ignore) continue;

      if (feedback.action == FeedbackAction.confirm) {
        confirmCount++;
      } else if (feedback.action == FeedbackAction.correct) {
        correctCount++;
      } else if (feedback.action == FeedbackAction.deny) {
        denyCount++;
      }
    }

    final totalFeedback = confirmCount + correctCount + denyCount;
    if (totalFeedback < state.minFeedbackCount) return;

    // If user is correcting responses frequently, may need different prompt variant
    if (correctCount > totalFeedback * 0.3) {
      // > 30% corrections: might benefit from different prompt
      state.systemPromptVariant = 'verbose'; // TODO: Actual variant selection
    }

    state.version++;
    state.lastUpdatedAt = DateTime.now();
    state.lastUpdateReason = 'trainFromFeedback';
    state.feedbackCountApplied = totalFeedback;

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
    return Center(child: Text('LLM Feedback UI for $invocationId (TODO)'));
  }
}
