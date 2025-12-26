/// # FeedbackCorrection
///
/// Base class for feedback correction payloads.
/// Each component defines its correction format in its service file.
///
/// ## What it does
/// Represents a user-provided correction for a component's invocation.
/// Stored in Feedback.correctedData when action == FeedbackAction.correct.
///
/// ## Pattern
/// - Storage: JSON string (correctedData in Feedback entity)
/// - Code: Typed subclasses (compile-time safety)
/// - Example: STTFeedbackCorrection with correctedTranscription
///
/// ## Usage
/// When user corrects a component's output, store the correction as:
/// ```dart
/// final feedback = Feedback(
///   invocationId: 'inv_123',
///   componentType: 'stt',
///   action: FeedbackAction.correct,
///   correctedData: STTFeedbackCorrection(
///     correctedTranscription: 'hello world'
///   ).toJson(),
/// );
/// ```

abstract class FeedbackCorrection {
  /// Serialize this correction to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}
