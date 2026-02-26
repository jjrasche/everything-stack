import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'bootstrap_module.dart';
import '../bootstrap.dart';
import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../domain/audio_file.dart';
import '../services/audio_recording_service.dart';
import '../services/audio_storage.dart';
import '../services/embedding_service.dart';

class AudioModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    try {
      await AudioRecordingService.instance.initialize();
      debugPrint('✅ Audio: recording service');
    } catch (e) {
      debugPrint('⚠️ Audio recording init failed: $e');
    }

    try {
      final audioFileAdapter = getIt<PersistenceAdapter<AudioFile>>();
      final audioFileRepo = EntityRepository<AudioFile>(
        adapter: audioFileAdapter,
        embeddingService: EmbeddingService.instance,
      );
      getIt.registerSingleton<EntityRepository<AudioFile>>(audioFileRepo);

      final audioStorage = AudioStorage(audioFileRepo);
      getIt.registerSingleton<AudioStorage>(audioStorage);
      debugPrint('✅ Audio: storage');
    } catch (e) {
      debugPrint('⚠️ Audio storage init failed: $e');
    }
  }

  @override
  Future<void> dispose(GetIt getIt) async {
    AudioRecordingService.instance.dispose();
  }
}
