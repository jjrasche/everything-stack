/// # FeedbackRepository
///
/// ## What it does
/// Manages feedback records across all components.
/// Feedback links invocations to user corrections/confirmations.
///
/// ## Query Operations
/// - findByInvocationId(): Get feedback for specific invocation
/// - findByTurn(): Get all feedback for a turn
/// - findByTurnAndComponent(): Get feedback for turn + component
/// - findByContextType(): Get feedback for background/retry/test
/// - save(): Persist feedback

import '../domain/feedback.dart';

abstract class FeedbackRepository {
  /// Find feedback for specific invocation
  ///
  /// Parameters:
  /// - [invocationId] Which invocation
  ///
  /// Returns: List of feedback (may be empty)
  Future<List<Feedback>> findByInvocationId(String invocationId);

  /// Find feedback for multiple invocations
  ///
  /// Used when processing feedback for entire turn.
  ///
  /// Parameters:
  /// - [invocationIds] List of invocation IDs
  ///
  /// Returns: All feedback for those invocations
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds);

  /// Find all feedback for a turn
  ///
  /// Parameters:
  /// - [turnId] Which turn
  ///
  /// Returns: Feedback from all components for that turn
  Future<List<Feedback>> findByTurn(String turnId);

  /// Find feedback for specific component in a turn
  ///
  /// Used by trainFromFeedback() to get component-specific feedback.
  ///
  /// Parameters:
  /// - [turnId] Which turn
  /// - [componentType] 'stt', 'intent', 'llm', 'tts'
  ///
  /// Returns: Feedback for that component in that turn
  Future<List<Feedback>> findByTurnAndComponent(
    String turnId,
    String componentType,
  );

  /// Find feedback of specific context type
  ///
  /// Used to query background/retry/test feedback.
  /// These have turnId == null.
  ///
  /// Parameters:
  /// - [contextType] 'background', 'retry', 'test'
  ///
  /// Returns: Feedback for invocations in that context
  Future<List<Feedback>> findByContextType(String contextType);

  /// Find all conversational feedback
  ///
  /// Returns: All feedback with turnId != null
  Future<List<Feedback>> findAllConversational();

  /// Find all background/retry/test feedback
  ///
  /// Returns: All feedback with turnId == null
  Future<List<Feedback>> findAllBackground();

  /// Save feedback
  ///
  /// Parameters:
  /// - [feedback] Feedback to save
  ///
  /// Returns: Saved feedback
  Future<Feedback> save(Feedback feedback);

  /// Delete feedback
  ///
  /// Parameters:
  /// - [id] Feedback ID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Delete all feedback for a turn
  ///
  /// Parameters:
  /// - [turnId] Which turn
  ///
  /// Returns: Number of feedback records deleted
  Future<int> deleteByTurn(String turnId);
}
