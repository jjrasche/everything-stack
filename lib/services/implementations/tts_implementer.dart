/// # TTS Implementer Interface
///
/// Dumb API wrapper for text-to-speech providers (Flutter TTS, Google Cloud, etc.).
/// No state management, no training logic. Just calls API and returns results.
/// Service holds metadata about call (latencyMs) in properties.

import '../../core/implementer.dart';
import '../types/tts_types.dart';

abstract class TTSImplementer implements Implementer {
  /// Synthesize text to speech.
  ///
  /// Parameters:
  /// - [text] Text to synthesize
  /// - [voiceId] Voice to use (implementer-specific: e.g., 'en-US-Neural2-C')
  /// - [speechRate] Speech rate multiplier (0.5 = half speed, 2.0 = double speed)
  /// - [pitch] Pitch adjustment (0.5 = lower, 2.0 = higher)
  ///
  /// Returns: TTS invocation output (audioId, duration, latency)
  /// No side effects: Returns typed output directly
  Future<TTSInvocationOutput> synthesize({
    required String text,
    required String voiceId,
    required double speechRate,
    required double pitch,
  });
}
