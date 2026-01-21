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

  /// Platforms this implementer supports.
  /// Valid values: 'android', 'ios', 'macos', 'windows', 'linux', 'web'
  /// Return empty set for stub implementations (unsupported platforms).
  ///
  /// Examples:
  /// - Pure Dart HTTP implementer: all 6 platforms
  /// - flutter_tts plugin: ['android', 'ios', 'macos', 'windows', 'web']
  /// - Platform-specific native code: subset of platforms
  Set<String> get supportedPlatforms;
}
