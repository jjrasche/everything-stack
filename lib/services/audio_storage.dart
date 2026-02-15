import 'dart:typed_data';
import '../domain/audio_file.dart';
import '../core/entity_repository.dart';

class AudioStorage {
  final EntityRepository<AudioFile> _repository;

  AudioStorage(this._repository);

  /// Save audio bytes to database and return audioId (UUID).
  Future<String> saveAudio({
    required Uint8List audioBytes,
    required double durationSeconds,
    String format = 'pcm16_16khz_mono',
    String? eventId,
  }) async {
    final audioFile = AudioFile(
      audioBytes: audioBytes,
      durationSeconds: durationSeconds,
      format: format,
      eventId: eventId,
    );

    // The entity's uuid is set during save by BaseEntity
    await _repository.save(audioFile);
    return audioFile.uuid;
  }

  /// Load audio bytes from database by audioId (UUID).
  Future<Uint8List> loadAudio(String audioId) async {
    final audioFile = await _repository.findByUuid(audioId);
    if (audioFile == null) {
      throw AudioNotFoundException(audioId);
    }
    return audioFile.audioBytes;
  }

  /// Get audio file metadata (duration, format) without loading bytes.
  Future<AudioFileMetadata?> getMetadata(String audioId) async {
    final audioFile = await _repository.findByUuid(audioId);
    if (audioFile == null) {
      return null;
    }
    return AudioFileMetadata(
      audioId: audioFile.uuid,
      durationSeconds: audioFile.durationSeconds,
      format: audioFile.format,
      sizeBytes: audioFile.sizeBytes,
      createdAt: audioFile.createdAt,
      eventId: audioFile.eventId,
    );
  }

  /// Delete audio file by UUID.
  Future<bool> deleteAudio(String audioId) async {
    return await _repository.deleteByUuid(audioId);
  }
}

/// Metadata about an audio file (without loading full bytes).
class AudioFileMetadata {
  final String audioId;
  final double durationSeconds;
  final String format;
  final int sizeBytes;
  final DateTime createdAt;
  final String? eventId;

  AudioFileMetadata({
    required this.audioId,
    required this.durationSeconds,
    required this.format,
    required this.sizeBytes,
    required this.createdAt,
    this.eventId,
  });
}

/// Exception thrown when audio file is not found.
class AudioNotFoundException implements Exception {
  final String audioId;
  AudioNotFoundException(this.audioId);

  @override
  String toString() => 'AudioNotFoundException: Audio file not found: $audioId';
}
