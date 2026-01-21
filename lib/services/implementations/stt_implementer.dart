/// # STT Implementer Interface
///
/// Dumb API wrapper for speech-to-text providers (Deepgram, Google Cloud, etc.).
/// No state management, no training logic. Just calls API and returns results.
/// Service holds metadata about call (latencyMs) in properties.

import '../../core/implementer.dart';
import '../types/stt_types.dart';

abstract class STTImplementer implements Implementer {
  /// Recognize speech from audio.
  ///
  /// Parameters:
  /// - [audioId] ID/path of audio file or data
  /// - [durationSeconds] Duration of audio in seconds
  /// - [eventId] Event correlation ID for publishing partial transcripts
  /// - [eotThreshold] End-of-turn threshold (Flux only, 0.5-0.9)
  /// - [eagerEotThreshold] Eager end-of-turn threshold (Flux only, optional)
  /// - [eotTimeoutMs] End-of-turn timeout (Flux only, optional)
  /// - [enablePartialTranscripts] Enable partial transcript events (Flux only)
  /// - [enableEagerProcessing] Enable eager processing (Flux only)
  ///
  /// Returns: STT invocation output (transcription + per-word details + latency)
  /// No side effects: Returns typed output directly
  Future<STTInvocationOutput> recognize({
    required String audioId,
    required double durationSeconds,
    String? eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  });
}
