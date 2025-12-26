/// # STTService
///
/// ## What it does
/// Provides speech-to-text (STT) conversion.
/// Implements Trainable to learn from user feedback.
///
/// ## Trainable Contract
/// - recordInvocation(STTInvocation): Save STT result for later feedback
/// - trainFromFeedback(turnId): Learn from user corrections
/// - buildFeedbackUI(invocationId): Let user provide feedback
/// - getAdaptationState(): Return current tunable parameters
///
/// ## Learning Algorithm (Rule-Based)
/// When user confirms a low-confidence utterance:
///   → Lower threshold by 5% (accept more borderline results)
/// When user denies a high-confidence utterance:
///   → Raise threshold by 5% (reject more borderline results)
/// Only updates if feedbackCount >= minFeedbackCount (default 10)
///
/// ## Usage
/// ```dart
/// // Record an STT result
/// final invocationId = await sttService.recordInvocation(
///   STTInvocation(audioId: 'audio_001', output: 'set reminder', confidence: 0.92)
/// );
///
/// // Later, user provides feedback and hits "Train"
/// await sttService.trainFromFeedback(turnId: 'turn_5', userId: 'user_123');
///
/// // Check what it learned
/// final state = await sttService.getAdaptationState(userId: 'user_123');
/// print('Threshold: ${state['confidenceThreshold']}');
/// ```

import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/trainable.dart';
import 'package:everything_stack_template/domain/invocation.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';

class STTService implements Trainable {
  final InvocationRepository<Invocation> _invocationRepository;
  final FeedbackRepository _feedbackRepository;
  final AdaptationStateRepository<STTAdaptationState>
      _adaptationStateRepository;

  // Current adaptation state (cached for performance)
  STTAdaptationState? _currentState;

  STTService({
    required InvocationRepository<Invocation> invocationRepository,
    required FeedbackRepository feedbackRepository,
    required AdaptationStateRepository<STTAdaptationState>
        adaptationStateRepository,
  })  : _invocationRepository = invocationRepository,
        _feedbackRepository = feedbackRepository,
        _adaptationStateRepository = adaptationStateRepository;

  // ============ Trainable Implementation ============

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! Invocation) {
      throw ArgumentError(
          'Expected Invocation, got ${invocation.runtimeType}');
    }

    final saved = await _invocationRepository.save(invocation);
    return saved.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // Get current state
    var state = await _adaptationStateRepository.getCurrent(userId: userId);

    // If this is the first feedback for this user, create personalized state
    if (userId != null && state.scope == 'global') {
      state = STTAdaptationState(
        scope: 'user',
        userId: userId,
      );
      state.confidenceThreshold =
          (await _adaptationStateRepository.getGlobal())?.confidenceThreshold ??
              0.65;
    }

    // Get all feedback for this turn's STT invocations
    final feedbacks =
        await _feedbackRepository.findByTurnAndComponent(turnId, 'stt');

    if (feedbacks.isEmpty) {
      return; // No feedback to learn from
    }

    // Analyze feedback to determine threshold adjustment
    double? adjustedThreshold = state.confidenceThreshold;
    int adjustmentCount = 0;

    for (final feedback in feedbacks) {
      // Skip feedback that shouldn't affect learning
      if (feedback.action == FeedbackAction.ignore) {
        continue;
      }

      // Get the invocation that was fed back on
      final invocation =
          await _invocationRepository.findById(feedback.invocationId);
      if (invocation == null) {
        continue;
      }

      // Rule 1: User confirmed low-confidence utterance
      // → Lower threshold to accept more similar results
      if (feedback.action == FeedbackAction.confirm &&
          invocation.confidence < state.confidenceThreshold) {
        adjustedThreshold = adjustedThreshold! * 0.95; // 5% decrease
        adjustmentCount++;
      }

      // Rule 2: User denied high-confidence utterance
      // → Raise threshold to reject more similar results
      if (feedback.action == FeedbackAction.deny &&
          invocation.confidence >= state.confidenceThreshold) {
        adjustedThreshold = adjustedThreshold! * 1.05; // 5% increase
        adjustmentCount++;
      }

      // Note: 'correct' action doesn't directly affect threshold
      // (User provided the correct text, but threshold learning is about accept/reject)
    }

    // Only update state if we have enough signal
    if (adjustmentCount < state.minFeedbackCount) {
      return; // Not enough feedback yet
    }

    // Clamp threshold to valid range
    state.confidenceThreshold = adjustedThreshold!.clamp(0.1, 0.95);
    state.version++;
    state.lastUpdatedAt = DateTime.now();
    state.lastUpdateReason = 'trainFromFeedback';
    state.feedbackCountApplied = adjustmentCount;

    // Save updated state with optimistic locking
    final updated = await _adaptationStateRepository.updateWithVersion(state);
    if (updated) {
      _currentState = state; // Update cache
    }
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    // Check cache first
    if (_currentState != null && _currentState!.userId == userId) {
      return _currentState!.toJson();
    }

    // Fetch from repository
    final state = await _adaptationStateRepository.getCurrent(userId: userId);
    _currentState = state; // Update cache
    return state.toJson();
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement STT feedback UI
    // Should display:
    // - Play audio button (from audioId)
    // - Display transcription (output)
    // - Show confidence score
    // - Allow user to:
    //   * Confirm (correct)
    //   * Correct (edit text)
    //   * Deny (wrong)
    //   * Ignore (skip learning)

    return Center(
      child: Text('STT Feedback UI for $invocationId (TODO)'),
    );
  }

  // ============ STT-Specific Methods ============

  /// Get a specific STT invocation for display/debugging
  Future<Invocation?> getInvocation(String invocationId) async {
    return await _invocationRepository.findById(invocationId);
  }

  /// Get all STT invocations for a context type
  Future<List<Invocation>> getInvocationsByContextType(
      String contextType) async {
    return await _invocationRepository.findByContextType(contextType);
  }

  /// Clear cache (mainly for testing)
  void clearCache() {
    _currentState = null;
  }
}
