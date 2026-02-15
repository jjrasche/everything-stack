import 'dart:convert';
import 'package:everything_stack_template/core/adaptation_data.dart';

/// Learned TTS preferences (per implementer, per user).
class TTSAdaptationData extends AdaptationData {
  /// Preferred voice ID (implementer-specific: e.g., 'en-US-Neural2-C').
  final String voiceId;

  /// Speech rate multiplier (0.5 = half speed, 2.0 = double speed).
  final double speechRate;

  /// Voice pitch adjustment (0.5 = lower, 2.0 = higher).
  final double pitch;

  TTSAdaptationData({
    required this.voiceId,
    required this.speechRate,
    required this.pitch,
  });

  /// Default adaptation state (untrained).
  factory TTSAdaptationData.defaults() => TTSAdaptationData(
        voiceId: 'default',
        speechRate: 1.0,
        pitch: 1.0,
      );

  /// Deserialize from JSON.
  factory TTSAdaptationData.fromJson(Map<String, dynamic> json) =>
      TTSAdaptationData(
        voiceId: json['voiceId'] as String? ?? 'default',
        speechRate: json['speechRate'] as double? ?? 1.0,
        pitch: json['pitch'] as double? ?? 1.0,
      );

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
        'voiceId': voiceId,
        'speechRate': speechRate,
        'pitch': pitch,
      });
}

/// TTS invocation input (text to synthesize).
class TTSInvocationInput {
  /// Text to synthesize into speech.
  final String text;

  /// User's preferred voice (if overriding adaptation state).
  final String? voicePreference;

  TTSInvocationInput({
    required this.text,
    this.voicePreference,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
        'text': text,
        if (voicePreference != null) 'voicePreference': voicePreference,
      };

  /// Deserialize from JSON.
  factory TTSInvocationInput.fromJson(Map<String, dynamic> json) =>
      TTSInvocationInput(
        text: json['text'] as String,
        voicePreference: json['voicePreference'] as String?,
      );
}

/// TTS invocation output (synthesized audio metadata).
class TTSInvocationOutput {
  /// ID of generated audio file.
  final String audioId;

  /// Duration of generated audio (seconds).
  final double durationSeconds;

  /// How long synthesis took (milliseconds).
  final double latencyMs;

  TTSInvocationOutput({
    required this.audioId,
    required this.durationSeconds,
    required this.latencyMs,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
        'audioId': audioId,
        'durationSeconds': durationSeconds,
        'latencyMs': latencyMs,
      };

  /// Deserialize from JSON.
  factory TTSInvocationOutput.fromJson(Map<String, dynamic> json) =>
      TTSInvocationOutput(
        audioId: json['audioId'] as String,
        durationSeconds: json['durationSeconds'] as double,
        latencyMs: json['latencyMs'] as double,
      );
}

/// TTS feedback (user satisfaction with audio).
class TTSFeedback {
  /// User found voice appropriate/acceptable.
  final bool voiceAppropriate;

  /// User found speech speed appropriate.
  final bool speedAppropriate;

  /// User found audio clarity good.
  final bool clarityGood;

  TTSFeedback({
    required this.voiceAppropriate,
    required this.speedAppropriate,
    required this.clarityGood,
  });

  /// Serialize to JSON (stored in Feedback.correctedData).
  Map<String, dynamic> toJson() => {
        'voiceAppropriate': voiceAppropriate,
        'speedAppropriate': speedAppropriate,
        'clarityGood': clarityGood,
      };

  /// Deserialize from JSON.
  factory TTSFeedback.fromJson(Map<String, dynamic> json) => TTSFeedback(
        voiceAppropriate: json['voiceAppropriate'] as bool? ?? false,
        speedAppropriate: json['speedAppropriate'] as bool? ?? false,
        clarityGood: json['clarityGood'] as bool? ?? false,
      );
}
