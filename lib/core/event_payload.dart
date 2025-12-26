/// # EventPayload
///
/// Base class for event payloads.
/// Each event source defines its payload subclass.
///
/// ## What it does
/// Represents the data carried by an event.
/// Serializes to JSON for storage in Event.payloadJson field.
///
/// ## Pattern
/// - Storage: JSON string (payloadJson in Event entity)
/// - Code: Typed subclasses (compile-time safety)
/// - Example: UserUtteranceEventPayload, ToolExecutionEventPayload
///
/// ## Event Sourcing
/// Events are immutable records of what happened.
/// EventPayload carries the relevant data for that event.
///
/// Example:
/// ```dart
/// class UserUtteranceEventPayload extends EventPayload {
///   final String utterance;
///   final String sourceType; // 'voice', 'text', 'api'
///
///   UserUtteranceEventPayload({
///     required this.utterance,
///     required this.sourceType,
///   });
///
///   @override
///   String toJson() => jsonEncode({
///     'utterance': utterance,
///     'sourceType': sourceType,
///   });
/// }
/// ```

abstract class EventPayload {
  /// Serialize this payload to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}
