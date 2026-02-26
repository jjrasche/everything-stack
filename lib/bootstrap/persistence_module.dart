import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'bootstrap_module.dart';
import '../bootstrap.dart';
import '../services/blob_store.dart';
import '../services/sync_service.dart';
import '../services/connectivity_service.dart';
import 'persistence_web.dart'
    if (dart.library.io) 'persistence_native.dart';
import 'blob_store_factory_web.dart'
    if (dart.library.io) 'blob_store_factory_io.dart';

class PersistenceModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    await initializePersistence(getIt);

    final blobStore = createPlatformBlobStore();
    await blobStore.initialize();
    BlobStore.instance = blobStore;

    final connectivityService = ConnectivityPlusService();
    await connectivityService.initialize();
    ConnectivityService.instance = connectivityService;

    if (config.hasSyncConfig) {
      final syncService = SupabaseSyncService(
        supabaseUrl: config.supabaseUrl!,
        supabaseAnonKey: config.supabaseAnonKey!,
      );
      await syncService.initialize();
      SyncService.instance = syncService;
    }

    debugPrint('✅ Persistence, BlobStore, Connectivity initialized');
  }

  @override
  Future<void> dispose(GetIt getIt) async {
    disposePersistence(getIt);
    BlobStore.instance.dispose();
    ConnectivityService.instance.dispose();
    SyncService.instance.dispose();
  }
}
