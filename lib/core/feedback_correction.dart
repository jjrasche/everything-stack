/// Base class for feedback correction payloads.
/// Each component defines its correction format in its service file.

abstract class FeedbackCorrection {
  /// Serialize this correction to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}
