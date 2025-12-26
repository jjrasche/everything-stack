/// # AdaptationData
///
/// Base class for component adaptation data payloads.
/// Each trainable component defines its own subclass in its service file.
///
/// ## What it does
/// Represents the learned parameters for a trainable component.
/// Serializes to JSON for storage, deserializes back to typed class in code.
///
/// ## Pattern
/// - Storage: JSON string (dataJson field in AdaptationState)
/// - Code: Typed subclasses (compile-time safety)
/// - Example: STTAdaptationData with confidenceThreshold, minFeedbackCount
///
/// ## Implementation Checklist
/// Each AdaptationData subclass MUST implement:
/// - [ ] toJson() - serializes to JSON string
/// - [ ] fromJson() factory - deserializes from JSON string
/// - [ ] copyWith() - creates copy with field updates
/// - [ ] Default values in constructor

abstract class AdaptationData {
  /// Serialize this data to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Dart doesn't support abstract factory constructors.
  // Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}

/// Empty default for components that don't need adaptation yet.
/// Used as fallback when no learned parameters exist.
class EmptyAdaptationData extends AdaptationData {
  EmptyAdaptationData();

  @override
  String toJson() => '{}';

  factory EmptyAdaptationData.fromJson(String json) => EmptyAdaptationData();
}
