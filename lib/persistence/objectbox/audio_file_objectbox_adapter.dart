import 'package:objectbox/objectbox.dart';
import '../../domain/audio_file.dart';
import '../../core/entity_repository.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/audio_file_ob.dart';

class AudioFileObjectBoxAdapter
    extends BaseObjectBoxAdapter<AudioFile, AudioFileOB> {
  AudioFileObjectBoxAdapter(Store store) : super(store);

  @override
  AudioFileOB toOB(AudioFile entity) => AudioFileOB.fromAudioFile(entity);

  @override
  AudioFile fromOB(AudioFileOB ob) => ob.toAudioFile();

  @override
  Condition<AudioFileOB> uuidEqualsCondition(String uuid) =>
      AudioFileOB_.uuid.equals(uuid);

  @override
  Condition<AudioFileOB> syncStatusLocalCondition() =>
      AudioFileOB_.syncId.notNull();

  /// Find audio file by event ID
  Future<AudioFile?> findByEventId(String eventId) async {
    final query = box.query(AudioFileOB_.eventId.equals(eventId)).build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }
}
