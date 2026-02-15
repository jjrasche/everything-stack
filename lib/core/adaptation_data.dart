/// Base class for component adaptation data payloads.
/// Each trainable component defines its own subclass in its service file.

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
