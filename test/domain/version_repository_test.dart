import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:everything_stack_template/core/entity_version.dart';
import 'package:everything_stack_template/core/version_repository.dart';
import 'package:everything_stack_template/core/base_entity.dart';

void main() {
  late Isar isar;
  late VersionRepository repo;

  setUp(() async {
    // Create in-memory Isar instance
    isar = await Isar.open(
      [EntityVersionSchema],
      directory: '',
      name: 'test_${DateTime.now().millisecondsSinceEpoch}',
    );
    repo = VersionRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
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
  });
}
