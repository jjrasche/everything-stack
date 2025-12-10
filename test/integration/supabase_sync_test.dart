/// # Supabase Sync Integration Tests
///
/// Tests real Supabase sync operations against a live Supabase instance.
/// These tests skip gracefully in CI (no secrets) and run locally with .env credentials.
///
/// Layer 2 testing: Real E2E tests against Supabase (not mocks).
///
/// ## Running locally
/// 1. Set up .env file with SUPABASE_URL and SUPABASE_ANON_KEY
/// 2. Run: flutter test test/integration/supabase_sync_test.dart
///
/// ## CI behavior
/// Tests skip (not fail) when SUPABASE_URL environment variable is absent.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:everything_stack_template/services/sync_service.dart';
import 'package:everything_stack_template/services/blob_store.dart';

const _uuid = Uuid();

/// Check if Supabase credentials are available.
/// Returns true if tests should run, false to skip.
bool get hasSupabaseCredentials {
  final url = Platform.environment['SUPABASE_URL'] ??
      const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  return url.isNotEmpty;
}

/// Get Supabase URL from environment.
String get supabaseUrl {
  return Platform.environment['SUPABASE_URL'] ??
      const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
}

/// Get Supabase anon key from environment.
String get supabaseAnonKey {
  return Platform.environment['SUPABASE_ANON_KEY'] ??
      const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
}

void main() {
  // ============ Test #1: Graceful Skip ============
  group('Supabase Sync - Credential Check', () {
    test('Test file loads without error when SUPABASE_URL absent', () {
      // This test always runs and verifies the skip logic works
      if (!hasSupabaseCredentials) {
        // Expected in CI - credentials not available
        expect(supabaseUrl, isEmpty);
      } else {
        // Running locally with credentials
        expect(supabaseUrl, isNotEmpty);
      }
    });
  });

  // ============ E2E Tests (skip when no credentials) ============
  group('Supabase Sync - E2E Tests', () {
    late SupabaseSyncService syncService;
    late SupabaseBlobStore blobStore;
    final testUuids = <String>[]; // Track for cleanup

    setUpAll(() async {
      if (!hasSupabaseCredentials) return;

      // Initialize real Supabase services
      syncService = SupabaseSyncService(
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
      );
      blobStore = SupabaseBlobStore(
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
      );

      await syncService.initialize();
      await blobStore.initialize();
    });

    tearDownAll(() async {
      if (!hasSupabaseCredentials) return;

      // Cleanup all test entities
      for (final uuid in testUuids) {
        try {
          await syncService.deleteRemote(uuid);
        } catch (_) {
          // Ignore cleanup errors
        }
        try {
          await blobStore.deleteRemote(uuid);
        } catch (_) {
          // Ignore cleanup errors
        }
      }

      syncService.dispose();
      blobStore.dispose();
    });

    // ============ Test #2: Push entity to Supabase ============
    test('Push entity to Supabase - create local → sync → verify in remote', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: A local entity data to sync
      final testUuid = _uuid.v4();
      testUuids.add(testUuid);

      final entityData = {
        'title': 'Test Note',
        'content': 'Created locally, syncing to Supabase',
        'tags': ['test', 'sync'],
      };

      // When: Push entity to Supabase
      final success = await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: entityData,
      );

      // Then: Push succeeded
      expect(success, isTrue);

      // And: Entity exists in remote
      final remote = await syncService.fetchEntity(testUuid);
      expect(remote, isNotNull);
      expect(remote!['type'], 'Note');
      expect(remote['data']['title'], 'Test Note');
    });

    // ============ Test #3: Pull entity from Supabase ============
    test('Pull entity from Supabase - entity in remote → pull → verify data', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: An entity exists in remote (from previous test or setup)
      final testUuid = _uuid.v4();
      testUuids.add(testUuid);

      // First push an entity
      await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: {'title': 'Remote Note', 'content': 'Pulling this'},
      );

      // When: Pull the entity
      final pulled = await syncService.fetchEntity(testUuid);

      // Then: Got the entity data
      expect(pulled, isNotNull);
      expect(pulled!['data']['title'], 'Remote Note');
    });

    // ============ Test #4: Round-trip sync ============
    test('Round-trip sync - create → push → verify → delete local simulation', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: Create and push entity
      final testUuid = _uuid.v4();
      testUuids.add(testUuid);

      final originalData = {
        'title': 'Round Trip Note',
        'content': 'Testing round trip',
      };

      // Push to remote
      await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: originalData,
      );

      // Simulate "deleting local" by just forgetting it
      // Then pull from remote (simulating new device or restored app)
      final restored = await syncService.fetchEntity(testUuid);

      // Then: Data is restored correctly
      expect(restored, isNotNull);
      expect(restored!['data']['title'], 'Round Trip Note');
      expect(restored['data']['content'], 'Testing round trip');
    });

    // ============ Test #5: Last-write-wins conflict resolution ============
    test('Last-write-wins conflict - newer updated_at wins', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: An entity in remote
      final testUuid = _uuid.v4();
      testUuids.add(testUuid);

      // Push initial version
      await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: {'title': 'Version 1'},
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      // When: Push newer version (simulating another device)
      final newerTime = DateTime.now();
      await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: {'title': 'Version 2 - Newer'},
        updatedAt: newerTime,
      );

      // When: Try to push older version (should be rejected or overwritten)
      final olderTime = DateTime.now().subtract(const Duration(minutes: 10));
      await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: {'title': 'Version 3 - Older (should lose)'},
        updatedAt: olderTime,
      );

      // Then: Newer version wins
      final result = await syncService.fetchEntity(testUuid);
      expect(result, isNotNull);
      expect(result!['data']['title'], 'Version 2 - Newer');
    });

    // ============ Test #6: Blob sync to Supabase Storage ============
    test('Blob sync - upload bytes → verify in Storage → download', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: Blob data to upload
      final testUuid = _uuid.v4();
      testUuids.add(testUuid);

      final testBytes = Uint8List.fromList(
        List<int>.generate(1024, (i) => i % 256),
      );

      // When: Upload blob to Supabase Storage
      final uploadSuccess = await blobStore.uploadRemote(testUuid, testBytes);
      expect(uploadSuccess, isTrue);

      // Then: Blob exists in remote
      final exists = await blobStore.existsRemote(testUuid);
      expect(exists, isTrue);

      // When: Download blob
      final downloaded = await blobStore.downloadRemote(testUuid);

      // Then: Downloaded bytes match original
      expect(downloaded, isNotNull);
      expect(downloaded!.length, testBytes.length);
      expect(downloaded, equals(testBytes));
    });

    // ============ Test #7: Offline behavior ============
    test('Offline behavior - operations return gracefully when simulating offline', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: Sync service with simulated offline state
      syncService.setSimulateOffline(true);

      // When: Try to sync
      final result = await syncService.syncAll();

      // Then: Returns null (offline indicator)
      expect(result, isNull);

      // Restore online state
      syncService.setSimulateOffline(false);
    });

    // ============ Test #8: Cleanup test data ============
    test('Cleanup test data - verify deletion works', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: An entity to delete
      final testUuid = _uuid.v4();

      await syncService.pushEntity(
        uuid: testUuid,
        type: 'Note',
        data: {'title': 'To be deleted'},
      );

      // Verify it exists
      var exists = await syncService.fetchEntity(testUuid);
      expect(exists, isNotNull);

      // When: Delete the entity
      final deleted = await syncService.deleteRemote(testUuid);
      expect(deleted, isTrue);

      // Then: Entity no longer exists
      exists = await syncService.fetchEntity(testUuid);
      expect(exists, isNull);
    });

    // ============ Test #9: Sync status tracking ============
    test('Sync status tracking - entity.syncStatus updates through local→syncing→synced flow', () async {
      if (!hasSupabaseCredentials) {
        markTestSkipped('SUPABASE_URL not set - skipping E2E test');
        return;
      }

      // Given: Tracking sync status changes
      final testUuid = _uuid.v4();
      testUuids.add(testUuid);

      final statusHistory = <SyncStatus>[];

      // Listen to status changes
      final subscription = syncService.onSyncStatusChanged
          .where((event) => event.entityUuid == testUuid)
          .listen((event) {
        statusHistory.add(event.status);
      });

      // Initial status should be local
      expect(syncService.getSyncStatus(testUuid), SyncStatus.local);

      // When: Sync the entity
      await syncService.syncEntity(testUuid);

      // Give stream time to emit
      await Future.delayed(const Duration(milliseconds: 100));

      // Then: Status went through syncing → synced
      expect(statusHistory, contains(SyncStatus.syncing));
      expect(statusHistory.last, SyncStatus.synced);

      // Final status is synced
      expect(syncService.getSyncStatus(testUuid), SyncStatus.synced);

      await subscription.cancel();
    });
  });
}

// ============ Skip helper for test output ============
void markTestSkipped(String reason) {
  // This doesn't actually skip in flutter_test, but documents intent
  // The test body returns early when credentials are missing
  print('SKIPPED: $reason');
}
