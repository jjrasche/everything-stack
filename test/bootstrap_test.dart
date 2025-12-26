/// Tests for bootstrap initialization.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/bootstrap.dart' as bootstrap;
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:everything_stack_template/services/file_service.dart';
import 'package:everything_stack_template/services/sync_service.dart';
import 'package:everything_stack_template/services/connectivity_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

void main() {
  group('Bootstrap', () {
    tearDown(() async {
      // Reset to defaults after each test
      BlobStore.instance = MockBlobStore();
      FileService.instance = MockFileService(blobStore: MockBlobStore());
      SyncService.instance = MockSyncService();
      ConnectivityService.instance = MockConnectivityService();
      EmbeddingService.instance = MockEmbeddingService();
    });

    test('initializeEverythingStack with mocks initializes all services',
        () async {
      await bootstrap.initializeEverythingStack(
        config: const bootstrap.EverythingStackConfig(useMocks: true),
      );

      // All services should be mock implementations
      expect(BlobStore.instance, isA<MockBlobStore>());
      expect(FileService.instance, isA<MockFileService>());
      expect(SyncService.instance, isA<MockSyncService>());
      expect(ConnectivityService.instance, isA<MockConnectivityService>());
      expect(EmbeddingService.instance, isA<MockEmbeddingService>());
    });

    test('EverythingStackConfig.hasSyncConfig checks both url and key', () {
      const noConfig = bootstrap.EverythingStackConfig();
      expect(noConfig.hasSyncConfig, isFalse);

      const urlOnly =
          bootstrap.EverythingStackConfig(supabaseUrl: 'https://x.supabase.co');
      expect(urlOnly.hasSyncConfig, isFalse);

      const keyOnly = bootstrap.EverythingStackConfig(supabaseAnonKey: 'key');
      expect(keyOnly.hasSyncConfig, isFalse);

      const both = bootstrap.EverythingStackConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'key',
      );
      expect(both.hasSyncConfig, isTrue);
    });

    test('EverythingStackConfig.hasEmbeddingConfig checks api keys', () {
      const noConfig = bootstrap.EverythingStackConfig();
      expect(noConfig.hasEmbeddingConfig, isFalse);

      const jina = bootstrap.EverythingStackConfig(jinaApiKey: 'jina-key');
      expect(jina.hasEmbeddingConfig, isTrue);

      const gemini = bootstrap.EverythingStackConfig(geminiApiKey: 'gemini-key');
      expect(gemini.hasEmbeddingConfig, isTrue);
    });

    test('disposeEverythingStack cleans up services', () async {
      await bootstrap.initializeEverythingStack(
        config: const bootstrap.EverythingStackConfig(useMocks: true),
      );

      // Should not throw
      await bootstrap.disposeEverythingStack();
    });
  });
}
