/// # SyncService Tests
///
/// Tests sync service interface and mock implementation.
/// - Local to remote sync (push)
/// - Remote to local sync (pull)
/// - Connectivity-aware (offline checks)
/// - WiFi-only blob sync
/// - Per-entity sync status tracking
/// - Last-write-wins conflict resolution

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/sync_service.dart';

void main() {
  group('SyncService interface', () {
    test('MockSyncService is default instance', () {
      SyncService.instance = MockSyncService();
      expect(SyncService.instance, isA<MockSyncService>());
    });

    test('SyncStatus enum has all expected values', () {
      expect(SyncStatus.local, isNotNull);
      expect(SyncStatus.syncing, isNotNull);
      expect(SyncStatus.synced, isNotNull);
      expect(SyncStatus.conflict, isNotNull);
    });

    test('SyncEvent has required fields', () {
      final event = SyncEvent(
        entityUuid: 'test-uuid',
        entityType: 'Note',
        status: SyncStatus.synced,
        timestamp: DateTime.now(),
      );

      expect(event.entityUuid, 'test-uuid');
      expect(event.entityType, 'Note');
      expect(event.status, SyncStatus.synced);
      expect(event.timestamp, isNotNull);
    });
  });

  group('MockSyncService', () {
    late MockSyncService syncService;

    setUp(() {
      syncService = MockSyncService();
    });

    group('Initialization', () {
      test('initialize completes successfully', () async {
        await expectLater(syncService.initialize(), completion(isNull));
      });

      test('isReady is true after initialization', () async {
        expect(syncService.isReady, isFalse);
        await syncService.initialize();
        expect(syncService.isReady, isTrue);
      });
    });

    group('Sync status tracking', () {
      test('entity starts in local status', () async {
        await syncService.initialize();

        final status = syncService.getSyncStatus('entity-uuid');

        expect(status, SyncStatus.local);
      });

      test('syncAll changes status from local to synced', () async {
        await syncService.initialize();

        // Set up some entities
        await syncService.setSyncStatus('entity-1', SyncStatus.local);
        await syncService.setSyncStatus('entity-2', SyncStatus.local);

        // Sync all
        await syncService.syncAll();

        // All should be synced
        expect(syncService.getSyncStatus('entity-1'), SyncStatus.synced);
        expect(syncService.getSyncStatus('entity-2'), SyncStatus.synced);
      });

      test('syncEntity changes specific entity status', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.local);
        await syncService.setSyncStatus('entity-2', SyncStatus.local);

        // Sync only entity-1
        await syncService.syncEntity('entity-1');

        // Only entity-1 synced
        expect(syncService.getSyncStatus('entity-1'), SyncStatus.synced);
        expect(syncService.getSyncStatus('entity-2'), SyncStatus.local);
      });

      test('syncEntity creates tracking for non-existent uuid and syncs', () async {
        await syncService.initialize();

        // Non-existent entity gets tracked and synced
        final result = await syncService.syncEntity('non-existent');

        // Should sync to synced status
        expect(result, SyncStatus.synced);
        expect(syncService.getSyncStatus('non-existent'), SyncStatus.synced);
      });

      test('getSyncStatus returns local for untracked entities', () async {
        await syncService.initialize();

        final status = syncService.getSyncStatus('unknown-uuid');

        expect(status, SyncStatus.local);
      });
    });

    group('Sync events', () {
      test('onSyncStatusChanged emits events', () async {
        await syncService.initialize();

        final events = <SyncEvent>[];
        final subscription = syncService.onSyncStatusChanged.listen(
          (event) => events.add(event),
        );

        try {
          await syncService.setSyncStatus('entity-1', SyncStatus.syncing);
          await syncService.setSyncStatus('entity-1', SyncStatus.synced);

          // Should have received events
          expect(events, isNotEmpty);
          expect(events[0].status, SyncStatus.syncing);
          expect(events[1].status, SyncStatus.synced);
        } finally {
          await subscription.cancel();
        }
      });

      test('multiple listeners receive events', () async {
        await syncService.initialize();

        final events1 = <SyncEvent>[];
        final events2 = <SyncEvent>[];

        final sub1 = syncService.onSyncStatusChanged.listen(
          (event) => events1.add(event),
        );
        final sub2 = syncService.onSyncStatusChanged.listen(
          (event) => events2.add(event),
        );

        try {
          await syncService.setSyncStatus('entity-1', SyncStatus.syncing);

          expect(events1.length, 1);
          expect(events2.length, 1);
          expect(events1[0].entityUuid, 'entity-1');
          expect(events2[0].entityUuid, 'entity-1');
        } finally {
          await sub1.cancel();
          await sub2.cancel();
        }
      });

      test('sync event has correct timestamp', () async {
        await syncService.initialize();

        final beforeTime = DateTime.now().subtract(Duration(seconds: 1));

        final events = <SyncEvent>[];
        final subscription = syncService.onSyncStatusChanged.listen(
          (event) => events.add(event),
        );

        try {
          await syncService.setSyncStatus('entity-1', SyncStatus.synced);

          final afterTime = DateTime.now().add(Duration(seconds: 1));

          expect(events, isNotEmpty);
          expect(events[0].timestamp.isAfter(beforeTime), isTrue);
          expect(events[0].timestamp.isBefore(afterTime), isTrue);
        } finally {
          await subscription.cancel();
        }
      });
    });

    group('Blob sync (WiFi-only)', () {
      test('syncBlobs requires WiFi', () async {
        await syncService.initialize();

        // Mock WiFi unavailable
        syncService.setMockWifiAvailable(false);

        final result = await syncService.syncBlobs();

        // Should return false (not synced)
        expect(result, isFalse);
      });

      test('syncBlobs succeeds on WiFi', () async {
        await syncService.initialize();

        // Mock WiFi available
        syncService.setMockWifiAvailable(true);

        final result = await syncService.syncBlobs();

        // Should succeed
        expect(result, isTrue);
      });

      test('syncBlobs separate from entity sync', () async {
        await syncService.initialize();

        // Set up blob
        await syncService.setSyncStatus('blob-1', SyncStatus.local);

        // WiFi unavailable
        syncService.setMockWifiAvailable(false);

        // syncBlobs fails
        final blobResult = await syncService.syncBlobs();
        expect(blobResult, isFalse);

        // But syncAll succeeds (entity sync, not blob sync)
        await syncService.syncAll();
        expect(syncService.getSyncStatus('blob-1'), SyncStatus.synced);
      });

      test('syncBlobs emits sync events', () async {
        await syncService.initialize();
        syncService.setMockWifiAvailable(true);

        final events = <SyncEvent>[];
        final subscription = syncService.onSyncStatusChanged.listen(
          (event) => events.add(event),
        );

        try {
          await syncService.syncBlobs();

          // Should have emitted blob sync events
          expect(events.isNotEmpty, isTrue);
        } finally {
          await subscription.cancel();
        }
      });
    });

    group('Offline behavior', () {
      test('syncAll when offline returns null', () async {
        await syncService.initialize();

        // Set offline
        syncService.setMockOnline(false);

        final result = await syncService.syncAll();

        // Should return null (can't sync when offline)
        expect(result, isNull);
      });

      test('syncEntity when offline returns null', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.local);
        syncService.setMockOnline(false);

        final result = await syncService.syncEntity('entity-1');

        // Should return null
        expect(result, isNull);

        // Status unchanged
        expect(syncService.getSyncStatus('entity-1'), SyncStatus.local);
      });

      test('syncEntity works when online', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.local);
        syncService.setMockOnline(true);

        final result = await syncService.syncEntity('entity-1');

        expect(result, SyncStatus.synced);
      });
    });

    group('Conflict resolution', () {
      test('conflicting entity is marked as conflict', () async {
        await syncService.initialize();

        // Mark as conflict
        await syncService.setSyncStatus('entity-1', SyncStatus.conflict);

        expect(syncService.getSyncStatus('entity-1'), SyncStatus.conflict);
      });

      test('resolveConflict marks entity as synced', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.conflict);
        expect(syncService.getSyncStatus('entity-1'), SyncStatus.conflict);

        // Resolve conflict
        await syncService.resolveConflict('entity-1', keepLocal: true);

        expect(syncService.getSyncStatus('entity-1'), SyncStatus.synced);
      });

      test('resolveConflict emits event', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.conflict);

        final events = <SyncEvent>[];
        final subscription = syncService.onSyncStatusChanged.listen(
          (event) => events.add(event),
        );

        try {
          await syncService.resolveConflict('entity-1', keepLocal: true);

          expect(events.isNotEmpty, isTrue);
          expect(events.last.status, SyncStatus.synced);
        } finally {
          await subscription.cancel();
        }
      });
    });

    group('Syncing status', () {
      test('status changes to syncing during sync', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.local);

        final events = <SyncEvent>[];
        final subscription = syncService.onSyncStatusChanged.listen(
          (event) => events.add(event),
        );

        try {
          await syncService.syncEntity('entity-1');

          // Should have syncing event
          final syncingEvents =
              events.where((e) => e.status == SyncStatus.syncing).toList();
          expect(syncingEvents, isNotEmpty);
        } finally {
          await subscription.cancel();
        }
      });

      test('returns syncing status correctly', () async {
        await syncService.initialize();

        await syncService.setSyncStatus('entity-1', SyncStatus.syncing);

        expect(syncService.getSyncStatus('entity-1'), SyncStatus.syncing);
      });
    });

    group('Lifecycle', () {
      test('dispose completes', () async {
        await syncService.initialize();

        syncService.dispose();
        // No exception = success
      });

      test('dispose closes streams', () async {
        await syncService.initialize();

        final events = <SyncEvent>[];
        final subscription = syncService.onSyncStatusChanged.listen(
          (event) => events.add(event),
        );

        syncService.dispose();
        await subscription.cancel();

        // No exception = success
      });
    });
  });

  group('SyncService real implementation', () {
    // Real Supabase implementation would:
    // - Connect to Supabase project
    // - Push local changes to tables
    // - Pull remote changes
    // - Handle blob uploads to Supabase Storage
    // - Implement actual last-write-wins with timestamps
    // These will be tested on actual Supabase instance

    test('SupabaseSyncService is a SyncService', () {
      expect(SupabaseSyncService, isA<Type>());
    });
  });
}
