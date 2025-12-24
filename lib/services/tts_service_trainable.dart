/// # TTSService (Trainable)
///
/// Extends TTSService with Trainable interface for feedback-driven learning.
/// Learns from user feedback on voice settings and speech rate.

import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/trainable.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/tts_invocation_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';

class TTSServiceTrainable implements Trainable {
  final TTSInvocationRepository _invocationRepository;
  final FeedbackRepository _feedbackRepository;
  final AdaptationStateRepository<TTSAdaptationState>
      _adaptationStateRepository;

  TTSAdaptationState? _currentState;

  TTSServiceTrainable({
    required TTSInvocationRepository invocationRepository,
    required FeedbackRepository feedbackRepository,
    required AdaptationStateRepository<TTSAdaptationState>
        adaptationStateRepository,
  })  : _invocationRepository = invocationRepository,
        _feedbackRepository = feedbackRepository,
        _adaptationStateRepository = adaptationStateRepository;

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! TTSInvocation) {
      throw ArgumentError(
          'Expected TTSInvocation, got ${invocation.runtimeType}');
    }

    await _invocationRepository.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    var state = await _adaptationStateRepository.getCurrent(userId: userId);

    if (userId != null && state.scope == 'global') {
      state = TTSAdaptationState(scope: 'user', userId: userId);
    }

    final feedbacks =
        await _feedbackRepository.findByTurnAndComponent(turnId, 'tts');

    if (feedbacks.isEmpty) return;

    // Learning logic:
    // TTS has less direct feedback (audio quality is subjective)
    // Mainly track user engagement:
    // - Confirmed = user was satisfied with voice/speed
    // - Corrected/Denied = user might want different voice or speed

    int confirmCount = 0;
    int otherCount = 0;

    for (final feedback in feedbacks) {
      if (feedback.action == FeedbackAction.ignore) continue;

      if (feedback.action == FeedbackAction.confirm) {
        confirmCount++;
      } else {
        otherCount++;
      }
    }

    final totalFeedback = confirmCount + otherCount;
    if (totalFeedback < state.minFeedbackCount) return;

    // If mostly denials/corrections, may need different voice
    if (otherCount > confirmCount) {
      // Slightly adjust speech rate (very conservative)
      if (state.speechRate > 1.0) {
        state.speechRate *= 0.98; // Slow down slightly
      } else {
        state.speechRate *= 1.02; // Speed up slightly
      }
      state.speechRate = state.speechRate.clamp(0.5, 2.0);
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
    return Center(child: Text('TTS Feedback UI for $invocationId (TODO)'));
  }
}
