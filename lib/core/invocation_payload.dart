/// # InvocationPayload
///
/// Base class for invocation input/output payloads.
/// Each component defines its payload subclasses in its service file.
///
/// ## What it does
/// Represents component-specific input or output from an invocation.
/// Serializes to JSON for storage in Invocation.inputJson/outputJson fields.
///
/// ## Pattern
/// - Storage: JSON string (inputJson, outputJson in Invocation entity)
/// - Code: Typed subclasses (compile-time safety)
/// - Example: STTInvocationInput with audioId, STTInvocationOutput with transcription
///
/// ## Usage
/// Components define:
/// - Input payloads: what went into the component
/// - Output payloads: what came out of the component
///
/// Example:
/// ```dart
/// class STTInvocationInput extends InvocationPayload {
///   final String audioId;
///   STTInvocationInput(this.audioId);
///
///   @override
///   String toJson() => jsonEncode({'audioId': audioId});
/// }
/// ```

abstract class InvocationPayload {
  /// Serialize this payload to a JSON string for persistence.
  /// Must be idempotent: fromJson(toJson()) ≈ original object
  String toJson();

  // Note: Each subclass MUST implement:
  //   factory ClassName.fromJson(String json) { ... }
}
