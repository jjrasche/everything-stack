/// # Word
///
/// Typed representation of a single word in STT output.
/// Includes transcription and timing/confidence data.

/// A single word result from speech-to-text recognition.
class Word {
  /// The recognized word text.
  final String text;

  /// Confidence score for this specific word (0.0-1.0).
  final double confidence;

  /// Start time of word in audio (seconds).
  final double startTime;

  /// End time of word in audio (seconds).
  final double endTime;

  Word({
    required this.text,
    required this.confidence,
    required this.startTime,
    required this.endTime,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'text': text,
    'confidence': confidence,
    'startTime': startTime,
    'endTime': endTime,
  };

  /// Deserialize from JSON.
  factory Word.fromJson(Map<String, dynamic> json) => Word(
    text: json['text'] as String,
    confidence: json['confidence'] as double,
    startTime: json['startTime'] as double,
    endTime: json['endTime'] as double,
  );

  @override
  String toString() => 'Word(text: $text, confidence: $confidence, start: ${startTime}s, end: ${endTime}s)';
}
