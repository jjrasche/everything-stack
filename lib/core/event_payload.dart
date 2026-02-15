/// Base class for typed event payloads.
/// Each event source defines its payload subclass, serialized to JSON for Event.payloadJson.

abstract class EventPayload {
  /// Serialize this payload to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}
