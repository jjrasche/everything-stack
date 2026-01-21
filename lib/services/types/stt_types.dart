/// # STT Service Type Definitions
///
/// Typed payloads for STT (speech-to-text) service adaptation, invocations, and feedback.

import 'dart:convert';
import 'package:everything_stack_template/core/adaptation_data.dart';
import 'word.dart';

/// Learned STT preferences (per implementer, per user).
class STTAdaptationData extends AdaptationData {
  /// Minimum confidence threshold to accept transcription.
  /// Below this, request human correction or retry.
  final double confidenceThreshold;

  /// Minimum number of feedback samples before adjusting confidence threshold.
  /// Prevents premature adaptation from noise.
  final int minFeedbackCount;

  // ============ Deepgram Flux Turn Detection Parameters ============

  /// End-of-turn threshold (0.5-0.9).
  /// Higher = more conservative (waits longer before declaring turn end).
  /// Lower = more aggressive (faster responses but may cut off mid-sentence).
  /// Trainable via GP based on user feedback.
  final double eotThreshold;

  /// Eager end-of-turn threshold (0.3-0.9, optional).
  /// If set, Deepgram sends EagerEndOfTurn events when confidence exceeds this.
  /// Used for fast interruption without waiting for full turn end.
  final double? eagerEotThreshold;

  /// End-of-turn timeout in milliseconds (optional).
  /// If set, forces turn end after this duration even if no silence detected.
  final int? eotTimeoutMs;

  // ============ Feature Flags (NOT trainable yet - needs Thompson Sampling) ============

  /// Enable partial transcripts during streaming (live typing effect).
  /// If false, only final transcript shown after EndOfTurn.
  final bool enablePartialTranscripts;

  /// Enable eager processing (respond to EagerEndOfTurn events).
  /// If false, only EndOfTurn events trigger processing.
  final bool enableEagerProcessing;

  STTAdaptationData({
    required this.confidenceThreshold,
    required this.minFeedbackCount,
    required this.eotThreshold,
    this.eagerEotThreshold,
    this.eotTimeoutMs,
    required this.enablePartialTranscripts,
    required this.enableEagerProcessing,
  });

  /// Default adaptation state (untrained).
  factory STTAdaptationData.defaults() => STTAdaptationData(
    confidenceThreshold: 0.65,
    minFeedbackCount: 10,
    eotThreshold: 0.7,                  // Balanced default
    eagerEotThreshold: null,            // Disabled by default
    eotTimeoutMs: null,                 // No timeout by default
    enablePartialTranscripts: true,     // Show live typing
    enableEagerProcessing: false,       // Conservative default
  );

  /// Deserialize from JSON.
  factory STTAdaptationData.fromJson(Map<String, dynamic> json) => STTAdaptationData(
    confidenceThreshold: json['confidenceThreshold'] as double? ?? 0.65,
    minFeedbackCount: json['minFeedbackCount'] as int? ?? 10,
    eotThreshold: json['eotThreshold'] as double? ?? 0.7,
    eagerEotThreshold: json['eagerEotThreshold'] as double?,
    eotTimeoutMs: json['eotTimeoutMs'] as int?,
    enablePartialTranscripts: json['enablePartialTranscripts'] as bool? ?? true,
    enableEagerProcessing: json['enableEagerProcessing'] as bool? ?? false,
  );

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
    'confidenceThreshold': confidenceThreshold,
    'minFeedbackCount': minFeedbackCount,
    'eotThreshold': eotThreshold,
    if (eagerEotThreshold != null) 'eagerEotThreshold': eagerEotThreshold,
    if (eotTimeoutMs != null) 'eotTimeoutMs': eotTimeoutMs,
    'enablePartialTranscripts': enablePartialTranscripts,
    'enableEagerProcessing': enableEagerProcessing,
  });

  /// Create a copy with updated parameters (for GP optimization).
  /// GP will test variations of eotThreshold to find optimal value.
  STTAdaptationData copyWith({
    double? confidenceThreshold,
    int? minFeedbackCount,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) {
    return STTAdaptationData(
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      minFeedbackCount: minFeedbackCount ?? this.minFeedbackCount,
      eotThreshold: eotThreshold ?? this.eotThreshold,
      eagerEotThreshold: eagerEotThreshold ?? this.eagerEotThreshold,
      eotTimeoutMs: eotTimeoutMs ?? this.eotTimeoutMs,
      enablePartialTranscripts: enablePartialTranscripts ?? this.enablePartialTranscripts,
      enableEagerProcessing: enableEagerProcessing ?? this.enableEagerProcessing,
    );
  }
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
