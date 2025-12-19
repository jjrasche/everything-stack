import 'package:flutter/material.dart';

/// # Trainable Interface
///
/// ## What it does
/// Contract for components that learn from user feedback.
/// Each component (STT, Intent, LLM, TTS) implements this interface.
/// Enables feedback loops: invocation → user feedback → state update
///
/// ## Methods
/// - recordInvocation(): Save component execution for later feedback
/// - trainFromFeedback(): Learn from user feedback on a turn
/// - getAdaptationState(): Return current tunable parameters
/// - buildFeedbackUI(): Build UI for user to provide feedback
///
/// ## Implementation Notes
/// - recordInvocation() is called immediately after component runs
/// - trainFromFeedback() is called after user provides feedback
/// - getAdaptationState() is called to display current settings
/// - buildFeedbackUI() is called in FeedbackReviewScreen
///
/// ## Type Safety
/// Each component implements Trainable with its own types:
///
/// ```dart
/// class STTService implements Trainable {
///   Future<void> recordInvocation(STTInvocation inv) async { ... }
///   Future<STTAdaptationState> getAdaptationState() { ... }
///   Widget buildFeedbackUI(String invocationId) { ... }
/// }
/// ```

abstract class Trainable {
  /// Record an invocation for this component
  ///
  /// Called immediately after component completes (success or failure).
  /// Invocation is stored for later feedback review.
  ///
  /// Parameters:
  /// - [invocation] The component's execution result
  ///
  /// Returns: UUID of the recorded invocation (used in Feedback later)
  ///
  /// Example:
  /// ```dart
  /// final sttInvocation = STTInvocation(...);
  /// final invocationId = await sttService.recordInvocation(sttInvocation);
  /// ```
  Future<String> recordInvocation(dynamic invocation);

  /// Learn from user feedback on a turn
  ///
  /// Called after user provides feedback in FeedbackReviewScreen.
  /// Component processes feedback and updates AdaptationState.
  ///
  /// Parameters:
  /// - [turnId] Which turn contains the feedback
  /// - [userId] Optional: user-specific learning (personalizes component)
  ///
  /// Example:
  /// ```dart
  /// await sttService.trainFromFeedback(
  ///   turnId: 'turn_5',
  ///   userId: 'user_123',  // For user-scoped adaptation
  /// );
  /// ```
  Future<void> trainFromFeedback(
    String turnId, {
    String? userId,
  });

  /// Get current adaptation state for display/debugging
  ///
  /// Returns the component's current tunable parameters.
  /// Used to show user "here's what we learned" or for debugging.
  ///
  /// Parameters:
  /// - [userId] Optional: get user-scoped state instead of global
  ///
  /// Returns: Map of {paramName: paramValue}
  ///
  /// Example:
  /// ```dart
  /// final state = await sttService.getAdaptationState(userId: 'user_123');
  /// print('STT threshold: ${state['confidenceThreshold']}');
  /// ```
  Future<Map<String, dynamic>> getAdaptationState({String? userId});

  /// Build UI for user to review and provide feedback
  ///
  /// Component builds its own feedback UI (full control).
  /// Called in FeedbackReviewScreen for each invocation in a turn.
  ///
  /// Parameters:
  /// - [invocationId] Which invocation to review
  ///
  /// Returns: Widget that allows user to provide feedback (confirm/deny/correct/ignore)
  ///
  /// The widget is responsible for:
  /// - Displaying the invocation (audio for STT, slots for Intent, etc.)
  /// - Allowing user to provide feedback (confirm, deny, correct, ignore)
  /// - Calling appropriate feedback repository to save feedback
  ///
  /// Example (STT):
  /// ```dart
  /// @override
  /// Widget buildFeedbackUI(String invocationId) {
  ///   return AudioPlayerWithTranscription(
  ///     audioId: invocation.audioId,
  ///     transcription: invocation.output,
  ///     onConfirm: () => createFeedback('confirm'),
  ///     onCorrect: (newText) => createFeedback('correct', newText),
  ///   );
  /// }
  /// ```
  Widget buildFeedbackUI(String invocationId);
}
