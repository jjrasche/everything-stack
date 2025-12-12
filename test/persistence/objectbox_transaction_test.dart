/// Test to verify ObjectBox runInTransactionAsync behavior
///
/// This test verifies:
/// 1. runInTransactionAsync can execute multiple operations atomically
/// 2. The callback can use synchronous Box operations
/// 3. Rollback works on exception
/// 4. Our adapter pattern is compatible

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/core/entity_version.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('objectbox_tx_test_');
    store = await openStore(directory: testDir.path);
  });

  tearDown(() async {
    store.close();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('ObjectBox Transaction Support', () {
    test('runInTransactionAsync executes atomically', () async {
      // Test data
      final noteData = ['note-uuid', 'Test Note', 'Content'];
      final versionData = ['note-uuid', 'Note', 1];

      // Execute in transaction
      await store.runInTransactionAsync<void, List<dynamic>>(
        TxMode.write,
        (Store txStore, List<dynamic> params) {
          final noteBox = txStore.box<Note>();
          final versionBox = txStore.box<EntityVersion>();

          // Save note
          final note = Note(
            title: params[0][1] as String,
            content: params[0][2] as String,
          );
          note.uuid = params[0][0] as String;
          noteBox.put(note);

          // Save version
          final version = EntityVersion(
            entityType: params[1][1] as String,
            entityUuid: params[1][0] as String,
            timestamp: DateTime.now(),
            versionNumber: params[1][2] as int,
            deltaJson: '{}',
            changedFields: [],
            isSnapshot: true,
          );
          versionBox.put(version);
        },
        [noteData, versionData],
      );

      // Verify both were saved
      final noteBox = store.box<Note>();
      final versionBox = store.box<EntityVersion>();

      final savedNote = await noteBox
          .query(Note_.uuid.equals('note-uuid'))
          .build()
          .findFirst();
      final savedVersion = await versionBox
          .query(EntityVersion_.entityUuid.equals('note-uuid'))
          .build()
          .findFirst();

      expect(savedNote, isNotNull);
      expect(savedNote!.title, 'Test Note');
      expect(savedVersion, isNotNull);
      expect(savedVersion!.versionNumber, 1);
    });

    test('runInTransactionAsync rolls back on exception', () async {
      final noteData = ['note-uuid-2', 'Test Note', 'Content'];

      try {
        await store.runInTransactionAsync<void, List<dynamic>>(
          TxMode.write,
          (Store txStore, List<dynamic> params) {
            final noteBox = txStore.box<Note>();
            final versionBox = txStore.box<EntityVersion>();

            // Save note
            final note = Note(
              title: params[0][1] as String,
              content: params[0][2] as String,
            );
            note.uuid = params[0][0] as String;
            noteBox.put(note);

            // Throw exception before saving version
            throw Exception('Simulated failure');
          },
          [noteData],
        );
        fail('Should have thrown exception');
      } catch (e) {
        expect(e.toString(), contains('Simulated failure'));
      }

      // Verify note was NOT saved (rollback worked)
      final noteBox = store.box<Note>();
      final savedNote = await noteBox
          .query(Note_.uuid.equals('note-uuid-2'))
          .build()
          .findFirst();

      expect(savedNote, isNull, reason: 'Transaction should have rolled back');
    });

    test('runInTransactionAsync with synchronous adapter pattern', () async {
      // Simulate adapter-style operations inside transaction
      final result = await store.runInTransactionAsync<String, List<String>>(
        TxMode.write,
        (Store txStore, List<String> params) {
          final noteBox = txStore.box<Note>();

          // Adapter-style save operation
          final note1 = Note(title: params[0], content: 'Content 1');
          note1.touch();
          noteBox.put(note1);

          final note2 = Note(title: params[1], content: 'Content 2');
          note2.touch();
          noteBox.put(note2);

          // Return result
          return 'Saved ${params.length} notes';
        },
        ['Note 1', 'Note 2'],
      );

      expect(result, 'Saved 2 notes');

      // Verify both saved
      final noteBox = store.box<Note>();
      final all = noteBox.getAll();
      expect(all.length, 2);
    });

    test('verify Box operations are synchronous', () async {
      // This test verifies our adapters use sync operations that work in transactions
      final noteBox = store.box<Note>();

      // Create note outside transaction
      final note = Note(title: 'Test', content: 'Content');

      // Verify these are synchronous calls (no await needed)
      noteBox.put(note);  // Synchronous
      final retrieved = noteBox.get(note.id);  // Synchronous
      final all = noteBox.getAll();  // Synchronous

      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Test');
      expect(all.length, greaterThan(0));
    });
  });
}
