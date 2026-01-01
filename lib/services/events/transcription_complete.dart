/// # TranscriptionComplete Event
///
/// Published by STTService when speech-to-text conversion succeeds.
/// Triggers Coordinator orchestration.
///
/// ## Source
/// STTService.transcribe() after successful Deepgram API call
///
/// ## Listening Consumers
/// - Coordinator (triggers orchestration pipeline)
library;

import 'system_event.dart';

class TranscriptionComplete extends SystemEvent {
  /// The transcribed text from speech
  final String transcript;

  /// Duration of audio that was transcribed (ms)
  final int durationMs;

  /// Confidence score from STT service (0.0 - 1.0)
  final double confidence;

  TranscriptionComplete({
    required this.transcript,
    required this.durationMs,
    required this.confidence,
    required String correlationId,
    DateTime? createdAt,
  }) : super(correlationId: correlationId, createdAt: createdAt);

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'transcript': transcript,
    'durationMs': durationMs,
    'confidence': confidence,
  };

  factory TranscriptionComplete.fromJson(Map<String, dynamic> json) {
    return TranscriptionComplete(
      transcript: json['transcript'] as String,
      durationMs: json['durationMs'] as int? ?? 0,
      confidence: json['confidence'] as double? ?? 0.0,
      correlationId: json['correlationId'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  @override
  String toString() =>
      'TranscriptionComplete(correlationId: $correlationId, transcript: "$transcript", confidence: $confidence, durationMs: $durationMs)';
}
