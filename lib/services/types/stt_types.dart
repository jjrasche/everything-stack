/// # STT Service Type Definitions
///
/// Typed payloads for STT (speech-to-text) service adaptation, invocations, and feedback.

import 'word.dart';

/// Learned STT preferences (per implementer, per user).
class STTAdaptationData {
  /// Minimum confidence threshold to accept transcription.
  /// Below this, request human correction or retry.
  final double confidenceThreshold;

  /// Minimum number of feedback samples before adjusting confidence threshold.
  /// Prevents premature adaptation from noise.
  final int minFeedbackCount;

  STTAdaptationData({
    required this.confidenceThreshold,
    required this.minFeedbackCount,
  });

  /// Default adaptation state (untrained).
  factory STTAdaptationData.defaults() => STTAdaptationData(
    confidenceThreshold: 0.65,
    minFeedbackCount: 10,
  );

  /// Deserialize from JSON.
  factory STTAdaptationData.fromJson(Map<String, dynamic> json) => STTAdaptationData(
    confidenceThreshold: json['confidenceThreshold'] as double? ?? 0.65,
    minFeedbackCount: json['minFeedbackCount'] as int? ?? 10,
  );

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'confidenceThreshold': confidenceThreshold,
    'minFeedbackCount': minFeedbackCount,
  };
}

/// STT invocation input (audio metadata).
class STTInvocationInput {
  /// Audio file/data ID.
  final String audioId;

  /// Duration of audio in seconds.
  final double durationSeconds;

  STTInvocationInput({
    required this.audioId,
    required this.durationSeconds,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'audioId': audioId,
    'durationSeconds': durationSeconds,
  };

  /// Deserialize from JSON.
  factory STTInvocationInput.fromJson(Map<String, dynamic> json) => STTInvocationInput(
    audioId: json['audioId'] as String,
    durationSeconds: json['durationSeconds'] as double,
  );
}

/// STT invocation output (transcription result from implementer).
class STTInvocationOutput {
  /// The transcribed text.
  final String transcription;

  /// Confidence score (0.0-1.0) from implementer.
  /// Different implementers have different confidence scales.
  final double confidence;

  /// Per-word details: text, confidence, start time, end time.
  final List<Word> words;

  /// Latency in milliseconds (from implementer).
  /// Time taken to process audio and return transcription.
  final double latencyMs;

  STTInvocationOutput({
    required this.transcription,
    required this.confidence,
    required this.words,
    required this.latencyMs,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'transcription': transcription,
    'confidence': confidence,
    'words': words.map((w) => w.toJson()).toList(),
    'latencyMs': latencyMs,
  };

  /// Deserialize from JSON.
  factory STTInvocationOutput.fromJson(Map<String, dynamic> json) => STTInvocationOutput(
    transcription: json['transcription'] as String,
    confidence: json['confidence'] as double,
    words: (json['words'] as List).map((w) => Word.fromJson(w as Map<String, dynamic>)).toList(),
    latencyMs: json['latencyMs'] as double,
  );
}

/// STT feedback (user confirmation or correction).
class STTFeedback {
  /// User confirmed transcription is correct.
  final bool transcriptionCorrect;

  /// If user corrected it, the correct transcription.
  final String? correctedTranscription;

  /// Word error rate (if user provided reference transcription).
  /// Computed as (insertions + deletions + substitutions) / reference_length.
  final double? wordErrorRate;

  STTFeedback({
    required this.transcriptionCorrect,
    this.correctedTranscription,
    this.wordErrorRate,
  });

  /// Serialize to JSON (stored in Feedback.correctedData).
  Map<String, dynamic> toJson() => {
    'transcriptionCorrect': transcriptionCorrect,
    if (correctedTranscription != null) 'correctedTranscription': correctedTranscription,
    if (wordErrorRate != null) 'wordErrorRate': wordErrorRate,
  };

  /// Deserialize from JSON.
  factory STTFeedback.fromJson(Map<String, dynamic> json) => STTFeedback(
    transcriptionCorrect: json['transcriptionCorrect'] as bool? ?? false,
    correctedTranscription: json['correctedTranscription'] as String?,
    wordErrorRate: json['wordErrorRate'] as double?,
  );
}
