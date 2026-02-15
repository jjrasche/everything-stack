/// Recorded audio stored as bytes in database (no filesystem dependencies).

import 'dart:convert';
import 'dart:typed_data';
import '../core/base_entity.dart';

class AudioFile extends BaseEntity {
  /// Audio data as PCM bytes (16kHz, mono, 16-bit)
  final Uint8List audioBytes;

  /// Duration in seconds
  final double durationSeconds;

  /// Format metadata (e.g., "pcm16_16khz_mono")
  final String format;

  /// Optional: Event ID this audio belongs to
  final String? eventId;

  AudioFile({
    required this.audioBytes,
    required this.durationSeconds,
    this.format = 'pcm16_16khz_mono',
    this.eventId,
  });

  @override
  AudioFile copyWith({
    Uint8List? audioBytes,
    double? durationSeconds,
    String? format,
    String? eventId,
  }) {
    final copy = AudioFile(
      audioBytes: audioBytes ?? this.audioBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      format: format ?? this.format,
      eventId: eventId ?? this.eventId,
    );
    // Copy BaseEntity fields manually
    copy.id = id;
    copy.uuid = uuid;
    copy.createdAt = createdAt;
    copy.updatedAt = updatedAt;
    copy.syncId = syncId;
    return copy;
  }

  @override
  String toEmbeddingInput() {
    // Audio files don't have semantic embeddings (would need transcription)
    return 'AudioFile($uuid, ${durationSeconds}s)';
  }

  /// Size in bytes
  int get sizeBytes => audioBytes.length;

  /// Serialize to JSON for IndexedDB persistence.
  ///
  /// Note: audioBytes are base64 encoded for JSON compatibility.
  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'audioBytes': base64Encode(audioBytes),
        'durationSeconds': durationSeconds,
        'format': format,
        'eventId': eventId,
      };

  /// Deserialize from JSON for IndexedDB persistence.
  factory AudioFile.fromJson(Map<String, dynamic> json) {
    final audioFile = AudioFile(
      audioBytes: base64Decode(json['audioBytes'] as String),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      format: json['format'] as String? ?? 'pcm16_16khz_mono',
      eventId: json['eventId'] as String?,
    );
    audioFile.id = json['id'] as int? ?? 0;
    audioFile.uuid = json['uuid'] as String? ?? '';
    audioFile.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    audioFile.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    audioFile.syncId = json['syncId'] as String?;
    return audioFile;
  }
}
