/// Base class for invocation input/output payloads.
/// Each component defines its payload subclasses in its service file.

abstract class InvocationPayload {
  /// Serialize this payload to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}
