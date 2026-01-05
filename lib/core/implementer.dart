/// # Implementer Interface
///
/// Dumb API wrapper contract.
/// Implementers accept parameters, return results.
/// NO state management, NO training logic.
///
/// Examples: GroqImplementer, ClaudeImplementer, DeepgramImplementer
abstract class Implementer {
  /// Unique identifier for this implementer.
  /// Examples: 'groq', 'claude', 'deepgram', 'flutter_tts'
  String get implementerName;
}
