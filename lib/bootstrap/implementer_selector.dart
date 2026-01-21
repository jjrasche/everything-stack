/// # Implementer Selector
///
/// Bootstrap helper for selecting platform-compatible implementers.
/// Used during service initialization to auto-select implementers that work
/// on the current platform.
///
/// ## Usage
/// ```dart
/// final ttsImplementers = {
///   'flutter_tts': FlutterTtsImplementer(),
///   'remote_tts': RemoteTTSImplementer(),
/// };
/// final defaultTTS = selectCompatibleImplementer(ttsImplementers, 'TTS');
/// ```

library;

import '../core/implementer.dart';
import '../core/platform_detector.dart';

/// Select first implementer that supports current platform.
///
/// Parameters:
/// - [implementers] Map of available implementers
/// - [serviceName] Name of service (for error messages, e.g., 'TTS', 'STT', 'LLM')
///
/// Returns: Key of first compatible implementer
/// Throws: StateError if no compatible implementer found
String selectCompatibleImplementer(
  Map<String, Implementer> implementers,
  String serviceName,
) {
  final compatible = implementers.entries
      .where((e) => e.value.supportedPlatforms.contains(currentPlatform))
      .toList();

  if (compatible.isEmpty) {
    throw StateError(
      'No $serviceName implementer supports platform "$currentPlatform". '
      'Available implementers: ${implementers.keys.join(", ")}',
    );
  }

  return compatible.first.key;
}
