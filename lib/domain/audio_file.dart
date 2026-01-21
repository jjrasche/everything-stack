/// # AudioFile Entity
///
/// Represents a recorded audio file stored as bytes in database.
/// Used for STT processing and playback.
///
/// Storage pattern: bytes-in-database (no filesystem dependencies)

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
}
