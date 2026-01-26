/// # STT Implementer Interface
///
/// Dumb API wrapper for speech-to-text providers (Deepgram, Google Cloud, etc.).
/// No state management, no training logic. Just calls API and returns results.
/// Service holds metadata about call (latencyMs) in properties.

import 'dart:typed_data';

import '../../core/implementer.dart';
import '../types/stt_types.dart';

abstract class STTImplementer implements Implementer {
  /// Recognize speech from saved audio (batch mode).
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

  /// Start live recognition by streaming audio chunks as they arrive.
  ///
  /// This is for real-time streaming mode where audio is sent to the API
  /// as it's being recorded, not after recording completes.
  ///
  /// Parameters:
  /// - [audioStream] Stream of audio chunks from microphone
  /// - [eventId] Event correlation ID for publishing events
  /// - [eotThreshold] End-of-turn threshold (0.5-0.9)
  /// - [eagerEotThreshold] Eager end-of-turn threshold (optional)
  /// - [eotTimeoutMs] End-of-turn timeout (optional)
  /// - [enablePartialTranscripts] Enable partial transcript events
  /// - [enableEagerProcessing] Enable eager processing
  ///
  /// Returns: STT invocation output when EndOfTurn detected
  ///
  /// Throws: UnsupportedError if implementer doesn't support live streaming
  Future<STTInvocationOutput> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) {
    throw UnsupportedError('${implementerName} does not support live streaming');
  }
}
