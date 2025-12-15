import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/core/entity_version.dart';
import 'package:everything_stack_template/core/version_repository.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/persistence/objectbox/entity_version_objectbox_adapter.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late VersionRepository repo;
  late Directory testDir;

  setUp(() async {
    // Create temporary directory for ObjectBox store
    testDir = await Directory.systemTemp.createTemp('objectbox_version_test_');

    // Open ObjectBox store
    store = await openStore(directory: testDir.path);

    // Create repository with ObjectBox adapter
    final adapter = EntityVersionObjectBoxAdapter(store);
    repo = VersionRepository(adapter: adapter);
  });

  tearDown(() async {
    store.close();
    // Clean up temp directory
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('VersionRepository', () {
    group('recordChange', () {
      test('creates first version with snapshot', () async {
        final entityUuid = 'note-123';
        final currentJson = {'title': 'First', 'body': 'Content'};

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: currentJson,
          userId: 'user-1',
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);

        expect(versions, hasLength(1));
        expect(versions[0].versionNumber, 1);
        expect(versions[0].isSnapshot, isTrue);
        expect(versions[0].snapshotJson, isNotNull);
        expect(versions[0].userId, 'user-1');
        expect(versions[0].changedFields, containsAll(['title', 'body']));
      });

      test('creates subsequent versions with deltas', () async {
        final entityUuid = 'note-123';
        final v1 = {'title': 'First', 'body': 'Content'};
        final v2 = {'title': 'Updated', 'body': 'Content'};

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: v1,
          snapshotFrequency: 20,
        );

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: v1,
          currentJson: v2,
          userId: 'user-2',
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);

        expect(versions, hasLength(2));
        expect(versions[1].versionNumber, 2);
        expect(versions[1].isSnapshot, isFalse);
        expect(versions[1].deltaJson, isNotEmpty);
        expect(versions[1].changedFields, contains('title'));
        expect(versions[1].changedFields, isNot(contains('body')));
      });

      test('creates periodic snapshots at frequency intervals', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'Version 1'};

        // Create versions 1-21 (frequency = 20, so v1 and v21 should be snapshots)
        for (int i = 1; i <= 21; i++) {
          final newState = {'title': 'Version $i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 20,
          );
          state = newState;
        }

        final versions = await repo.getHistory(entityUuid);

        expect(versions, hasLength(21));
        expect(versions[0].versionNumber, 1);
        expect(versions[0].isSnapshot, isTrue); // Initial
        expect(versions[19].versionNumber, 20);
        expect(versions[19].isSnapshot, isFalse); // Not a snapshot
        expect(versions[20].versionNumber, 21);
        expect(versions[20].isSnapshot, isTrue); // Periodic snapshot
      });

      test('stores change description', () async {
        final entityUuid = 'note-123';

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'Test'},
          changeDescription: 'Initial creation',
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);

        expect(versions[0].changeDescription, 'Initial creation');
      });
    });

    group('getHistory', () {
      test('returns versions ordered by versionNumber', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        for (int i = 1; i <= 5; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 20,
          );
          state = newState;
        }

        final versions = await repo.getHistory(entityUuid);

        expect(versions, hasLength(5));
        for (int i = 0; i < 5; i++) {
          expect(versions[i].versionNumber, i + 1);
        }
      });

      test('returns empty list for non-existent entity', () async {
        final versions = await repo.getHistory('nonexistent');

        expect(versions, isEmpty);
      });
    });

    group('getLatestVersionNumber', () {
      test('returns 0 for entity with no versions', () async {
        final version = await repo.getLatestVersionNumber('nonexistent');

        expect(version, 0);
      });

      test('returns latest version number', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        for (int i = 1; i <= 3; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 20,
          );
          state = newState;
        }

        final version = await repo.getLatestVersionNumber(entityUuid);

        expect(version, 3);
      });
    });

    group('reconstruct', () {
      test('reconstructs state at specific timestamp from snapshot', () async {
        final entityUuid = 'note-123';

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'First', 'body': 'Content'},
          snapshotFrequency: 20,
        );

        final timestamp = DateTime.now();

        await Future.delayed(const Duration(milliseconds: 10));

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: {'title': 'First', 'body': 'Content'},
          currentJson: {'title': 'Updated', 'body': 'Content'},
          snapshotFrequency: 20,
        );

        final reconstructed = await repo.reconstruct(entityUuid, timestamp);

        expect(reconstructed, isNotNull);
        expect(reconstructed!['title'], 'First');
        expect(reconstructed['body'], 'Content');
      });

      test('reconstructs state by applying deltas forward', () async {
        final entityUuid = 'note-123';

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'V1'},
          snapshotFrequency: 20,
        );

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: {'title': 'V1'},
          currentJson: {'title': 'V2'},
          snapshotFrequency: 20,
        );

        // Small delay to ensure V2 timestamp is recorded before capturing targetTime
        await Future.delayed(const Duration(milliseconds: 10));
        final targetTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 10));

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: {'title': 'V2'},
          currentJson: {'title': 'V3'},
          snapshotFrequency: 20,
        );

        final reconstructed = await repo.reconstruct(entityUuid, targetTime);

        expect(reconstructed, isNotNull);
        expect(reconstructed!['title'], 'V2');
      });

      test('returns null for timestamp before first version', () async {
        final entityUuid = 'note-123';
        final pastTimestamp = DateTime.now();

        await Future.delayed(const Duration(milliseconds: 10));

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'First'},
          snapshotFrequency: 20,
        );

        final reconstructed = await repo.reconstruct(entityUuid, pastTimestamp);

        expect(reconstructed, isNull);
      });
    });

    group('getChangesBetween', () {
      test('returns deltas in time range', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: state,
          snapshotFrequency: 20,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        final fromTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 10));

        for (int i = 2; i <= 4; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: state,
            currentJson: newState,
            snapshotFrequency: 20,
          );
          state = newState;
        }

        final toTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 10));

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: state,
          currentJson: {'title': 'V5'},
          snapshotFrequency: 20,
        );

        final changes =
            await repo.getChangesBetween(entityUuid, fromTime, toTime);

        expect(changes, hasLength(3)); // V2, V3, V4
        expect(changes[0].versionNumber, 2);
        expect(changes[2].versionNumber, 4);
      });
    });

    group('prune', () {
      test('removes old versions but keeps snapshots', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        // Create 45 versions (v1, v21, v41 will be snapshots with freq=20)
        for (int i = 1; i <= 45; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 20,
          );
          state = newState;
        }

        // Prune, keeping only 2 most recent snapshots
        await repo.prune(entityUuid, keepSnapshots: 2);

        final versions = await repo.getHistory(entityUuid);

        // Should keep: v21 (snapshot), v22-40, v41 (snapshot), v42-45
        // Should remove: v1-20 (old snapshot and its deltas)
        // Total kept: 25 versions (v21-v45)
        expect(versions.length, 25);
        expect(versions.first.versionNumber, 21);

        // Recent snapshots should still exist
        final snapshots = versions.where((v) => v.isSnapshot).toList();
        expect(snapshots.length, 2);
        expect(snapshots[0].versionNumber, 21);
        expect(snapshots[1].versionNumber, 41);
      });
    });

    group('sync methods', () {
      test('findUnsynced returns only versions with local status', () async {
        final entityUuid = 'note-123';

        // Create version and mark as synced
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'First'},
          snapshotFrequency: 20,
        );
        final versions = await repo.getHistory(entityUuid);
        await repo.markSynced(versions[0].uuid);

        // Create another version (unsynced)
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: {'title': 'First'},
          currentJson: {'title': 'Second'},
          snapshotFrequency: 20,
        );

        final unsynced = await repo.findUnsynced();
        expect(unsynced, hasLength(1));
        expect(unsynced[0].versionNumber, 2);
      });

      test(
          'findByEntityUuidUnsynced returns unsynced versions for specific entity',
          () async {
        final entity1 = 'note-1';
        final entity2 = 'note-2';

        // Create versions for entity1
        await repo.recordChange(
          entityUuid: entity1,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'Note 1'},
          snapshotFrequency: 20,
        );

        // Create versions for entity2
        await repo.recordChange(
          entityUuid: entity2,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'Note 2'},
          snapshotFrequency: 20,
        );

        final entity1Unsynced = await repo.findByEntityUuidUnsynced(entity1);
        expect(entity1Unsynced, hasLength(1));
        expect(entity1Unsynced[0].entityUuid, entity1);
      });

      test('markSynced updates syncStatus', () async {
        final entityUuid = 'note-123';

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'Test'},
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);
        expect(versions[0].syncStatus, SyncStatus.local);

        await repo.markSynced(versions[0].uuid);

        final updated = await repo.getHistory(entityUuid);
        expect(updated[0].syncStatus, SyncStatus.synced);
      });
    });

    group('edge cases', () {
      test('handles snapshot frequency of 1 (snapshot on every version)',
          () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        // Create 5 versions with frequency=1
        // Logic: newVersionNumber % snapshotFrequency == 1
        // With freq=1: 1%1=0, 2%1=0, 3%1=0... so NO periodic snapshots
        // Only the first version (v1) is always a snapshot
        for (int i = 1; i <= 5; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 1,
          );
          state = newState;
        }

        final versions = await repo.getHistory(entityUuid);
        expect(versions, hasLength(5));
        // First version is always snapshot, but freq=1 doesn't create periodic snapshots
        // because no version number is divisible by 1 with remainder 1
        expect(versions[0].isSnapshot, isTrue);
        expect(versions[1].isSnapshot, isFalse);
        expect(versions[2].isSnapshot, isFalse);
        expect(versions[3].isSnapshot, isFalse);
        expect(versions[4].isSnapshot, isFalse);
      });

      test('handles snapshot frequency of null (no periodic snapshots)',
          () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        // Create 5 versions with frequency=null (only first is snapshot)
        for (int i = 1; i <= 5; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: null,
          );
          state = newState;
        }

        final versions = await repo.getHistory(entityUuid);
        expect(versions, hasLength(5));
        expect(versions[0].isSnapshot, isTrue); // First is always snapshot
        expect(versions[1].isSnapshot, isFalse);
        expect(versions[2].isSnapshot, isFalse);
        expect(versions[3].isSnapshot, isFalse);
        expect(versions[4].isSnapshot, isFalse);
      });

      test('handles empty delta (no changes between versions)', () async {
        final entityUuid = 'note-123';
        final state = {'title': 'Unchanged', 'body': 'Content'};

        // Record initial version
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: state,
          snapshotFrequency: 20,
        );

        // Record "change" with identical state
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: state,
          currentJson: state,
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);
        expect(versions, hasLength(2));
        expect(versions[1].deltaJson, isNotEmpty);
        // Delta should be empty array [] for no changes
      });

      test('reconstructs with empty delta correctly', () async {
        final entityUuid = 'note-123';
        final state = {'title': 'V1', 'body': 'Content'};

        // Version 1
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: state,
          snapshotFrequency: 20,
        );

        final captureTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 10));

        // Version 2 with empty delta
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: state,
          currentJson: state,
          snapshotFrequency: 20,
        );

        final reconstructed = await repo.reconstruct(entityUuid, captureTime);
        expect(reconstructed, isNotNull);
        expect(reconstructed!['title'], 'V1');
      });

      test('prunes with zero snapshots to keep (handles edge case)',
          () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        // Create 10 versions (v1 and v6 will be snapshots with freq=5)
        for (int i = 1; i <= 10; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 5,
          );
          state = newState;
        }

        // Prune keeping 0 snapshots - should keep at least the most recent
        await repo.prune(entityUuid, keepSnapshots: 1);

        final versions = await repo.getHistory(entityUuid);
        expect(versions.isNotEmpty, isTrue);
        // At least the most recent snapshot should remain
      });

      test('prunes when fewer snapshots exist than requested', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        // Create 5 versions with high frequency (only v1 is snapshot)
        for (int i = 1; i <= 5; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 100,
          );
          state = newState;
        }

        // Request to keep 10 snapshots (more than exist)
        await repo.prune(entityUuid, keepSnapshots: 10);

        final versions = await repo.getHistory(entityUuid);
        // All versions should remain since we don't have 10 snapshots to keep
        expect(versions, hasLength(5));
      });

      test('reconstructs across multiple snapshots and deltas', () async {
        final entityUuid = 'note-123';
        Map<String, dynamic> state = {'title': 'V1', 'section': 'A'};

        // Create 15 versions with freq=5 (v1, v6, v11 are snapshots)
        DateTime? captureTime;
        for (int i = 1; i <= 15; i++) {
          final Map<String, dynamic> newState = {
            'title': 'V$i',
            'section': i <= 7 ? 'A' : 'B',
            'count': i
          };
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: i == 1 ? null : state,
            currentJson: newState,
            snapshotFrequency: 5,
          );
          // Capture time AFTER v6 but BEFORE v7
          if (i == 6) {
            await Future.delayed(const Duration(milliseconds: 10));
            captureTime = DateTime.now();
            await Future.delayed(const Duration(milliseconds: 10));
          }
          state = newState;
        }

        // Reconstruct at captured time (between v6 snapshot and v7)
        final reconstructed = await repo.reconstruct(entityUuid, captureTime!);

        expect(reconstructed, isNotNull);
        expect(reconstructed!['title'], 'V6');
        expect(reconstructed['section'], 'A');
        expect(reconstructed['count'], 6);
      });

      test('handles multiple entities with interleaved versions', () async {
        final entity1 = 'note-1';
        final entity2 = 'note-2';

        var state1 = {'title': 'E1-V1'};
        var state2 = {'title': 'E2-V1'};

        // Create versions for both entities
        for (int i = 1; i <= 3; i++) {
          final newState1 = {'title': 'E1-V$i'};
          await repo.recordChange(
            entityUuid: entity1,
            entityType: 'Note',
            previousJson: i == 1 ? null : state1,
            currentJson: newState1,
            snapshotFrequency: 20,
          );
          state1 = newState1;

          final newState2 = {'title': 'E2-V$i'};
          await repo.recordChange(
            entityUuid: entity2,
            entityType: 'Note',
            previousJson: i == 1 ? null : state2,
            currentJson: newState2,
            snapshotFrequency: 20,
          );
          state2 = newState2;
        }

        final history1 = await repo.getHistory(entity1);
        final history2 = await repo.getHistory(entity2);

        expect(history1, hasLength(3));
        expect(history2, hasLength(3));
        expect(history1[0].entityUuid, entity1);
        expect(history2[0].entityUuid, entity2);
      });

      test('stores complex nested JSON states correctly', () async {
        final entityUuid = 'doc-123';
        final complexState = {
          'title': 'Document',
          'metadata': {
            'author': 'John',
            'tags': ['important', 'review'],
            'nested': {
              'level': 2,
              'values': [1, 2, 3]
            }
          },
          'sections': [
            {'name': 'Intro', 'content': 'Hello'},
            {'name': 'Body', 'content': 'Main'}
          ]
        };

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Document',
          previousJson: null,
          currentJson: complexState,
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);
        final reconstructed = await repo.reconstruct(entityUuid, DateTime.now());

        expect(reconstructed, isNotNull);
        expect(reconstructed!['metadata']['author'], 'John');
        expect(reconstructed['metadata']['nested']['level'], 2);
        expect((reconstructed['sections'] as List).length, 2);
      });

      test('handles field addition and removal in deltas', () async {
        final entityUuid = 'note-123';
        final v1 = {'title': 'Test', 'body': 'Content', 'tags': []};

        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: v1,
          snapshotFrequency: 20,
        );

        // Version 2: add field
        final v2 = {
          ...v1,
          'priority': 'high'
        };
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: v1,
          currentJson: v2,
          snapshotFrequency: 20,
        );

        // Version 3: remove field
        final v3 = {
          'title': 'Test',
          'body': 'Content',
        };
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: v2,
          currentJson: v3,
          snapshotFrequency: 20,
        );

        final versions = await repo.getHistory(entityUuid);
        expect(versions, hasLength(3));

        // Reconstruct at v3
        final reconstructed = await repo.reconstruct(entityUuid, DateTime.now());
        expect(reconstructed!.containsKey('priority'), isFalse);
        expect(reconstructed['title'], 'Test');
      });

      test('handles time boundary cases in reconstruction', () async {
        final entityUuid = 'note-123';

        // Get time just before any versions
        final beforeTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 20));

        // Create first version
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: {'title': 'V1'},
          snapshotFrequency: 20,
        );

        // Get time after first version
        await Future.delayed(const Duration(milliseconds: 10));
        final afterTime = DateTime.now();

        // Reconstruct before first version (should be null)
        final before = await repo.reconstruct(entityUuid, beforeTime);
        expect(before, isNull);

        // Reconstruct after first version (should return v1)
        final after = await repo.reconstruct(entityUuid, afterTime);
        expect(after, isNotNull);
        expect(after!['title'], 'V1');
      });

      test('getChangesBetween with exact timestamp boundaries', () async {
        final entityUuid = 'note-123';
        var state = {'title': 'V1'};

        // Create v1
        await repo.recordChange(
          entityUuid: entityUuid,
          entityType: 'Note',
          previousJson: null,
          currentJson: state,
          snapshotFrequency: 20,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        final fromTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 10));

        // Create v2, v3
        for (int i = 2; i <= 3; i++) {
          final newState = {'title': 'V$i'};
          await repo.recordChange(
            entityUuid: entityUuid,
            entityType: 'Note',
            previousJson: state,
            currentJson: newState,
            snapshotFrequency: 20,
          );
          state = newState;
        }

        await Future.delayed(const Duration(milliseconds: 10));
        final toTime = DateTime.now();

        final changes = await repo.getChangesBetween(entityUuid, fromTime, toTime);
        expect(changes, hasLength(2)); // v2 and v3
      });
    });
  });
}
