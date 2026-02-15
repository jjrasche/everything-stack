import 'dart:typed_data';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/audio_file.dart';

@Entity()
class AudioFileOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ AudioFile-specific fields ============

  /// Audio data as bytes (PCM16, 16kHz, mono)
  @Property(type: PropertyType.byteVector)
  List<int> audioBytes;

  /// Duration in seconds
  double durationSeconds;

  /// Format metadata
  String format;

  /// Optional: Event ID this audio belongs to
  String? eventId;

  // ============ Constructor ============

  AudioFileOB({
    required this.audioBytes,
    required this.durationSeconds,
    this.format = 'pcm16_16khz_mono',
    this.eventId,
  });

  // ============ Conversion Methods ============

  /// Convert from domain AudioFile to ObjectBox wrapper
  factory AudioFileOB.fromAudioFile(AudioFile audioFile) {
    return AudioFileOB(
      audioBytes: audioFile.audioBytes.toList(),
      durationSeconds: audioFile.durationSeconds,
      format: audioFile.format,
      eventId: audioFile.eventId,
    )
      ..id = audioFile.id
      ..uuid = audioFile.uuid
      ..createdAt = audioFile.createdAt
      ..updatedAt = audioFile.updatedAt
      ..syncId = audioFile.syncId;
  }

  /// Convert from ObjectBox wrapper back to domain AudioFile
  AudioFile toAudioFile() {
    final audioFile = AudioFile(
      audioBytes: Uint8List.fromList(audioBytes),
      durationSeconds: durationSeconds,
      format: format,
      eventId: eventId,
    );
    // Copy BaseEntity fields
    audioFile.id = id;
    audioFile.uuid = uuid;
    audioFile.createdAt = createdAt;
    audioFile.updatedAt = updatedAt;
    audioFile.syncId = syncId;
    return audioFile;
  }
}
