/// # AudioFileIndexedDBAdapter
///
/// IndexedDB adapter for AudioFile entity.
/// Provides web-compatible persistence for audio recordings.

import 'dart:indexed_db' as idb;
import '../../domain/audio_file.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class AudioFileIndexedDBAdapter extends BaseIndexedDBAdapter<AudioFile> {
  AudioFileIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.audioFiles;

  @override
  AudioFile fromJson(Map<String, dynamic> json) => AudioFile.fromJson(json);

  /// Find audio file by event ID
  Future<AudioFile?> findByEventId(String eventId) async {
    final allFiles = await findAll();
    return allFiles.cast<AudioFile?>().firstWhere(
          (f) => f?.eventId == eventId,
          orElse: () => null,
        );
  }
}
