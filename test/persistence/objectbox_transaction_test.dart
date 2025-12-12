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
import 'package:everything_stack_template/persistence/objectbox/wrappers/note_ob.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/entity_version_ob.dart';
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

      // Execute in transaction using wrapper entities
      await store.runInTransactionAsync<void, List<dynamic>>(
        TxMode.write,
        (Store txStore, List<dynamic> params) {
          final noteBox = txStore.box<NoteOB>();
          final versionBox = txStore.box<EntityVersionOB>();

          // Save note wrapper
          final note = Note(
            title: params[0][1] as String,
            content: params[0][2] as String,
          );
          note.uuid = params[0][0] as String;
          final noteOB = NoteOB.fromNote(note);
          noteBox.put(noteOB);

          // Save version wrapper
          final version = EntityVersion(
            entityType: params[1][1] as String,
            entityUuid: params[1][0] as String,
            timestamp: DateTime.now(),
            versionNumber: params[1][2] as int,
            deltaJson: '{}',
            changedFields: [],
            isSnapshot: true,
          );
          final versionOB = EntityVersionOB.fromEntityVersion(version);
          versionBox.put(versionOB);
        },
        [noteData, versionData],
      );

      // Verify both were saved using wrapper entities
      final noteBox = store.box<NoteOB>();
      final versionBox = store.box<EntityVersionOB>();

      final savedNoteOB = await noteBox
          .query(NoteOB_.uuid.equals('note-uuid'))
          .build()
          .findFirst();
      final savedVersionOB = await versionBox
          .query(EntityVersionOB_.entityUuid.equals('note-uuid'))
          .build()
          .findFirst();

      expect(savedNoteOB, isNotNull);
      expect(savedNoteOB!.toNote().title, 'Test Note');
      expect(savedVersionOB, isNotNull);
      expect(savedVersionOB!.toEntityVersion().versionNumber, 1);
    });

    test('runInTransactionAsync rolls back on exception', () async {
      final noteData = ['note-uuid-2', 'Test Note', 'Content'];

      try {
        await store.runInTransactionAsync<void, List<dynamic>>(
          TxMode.write,
          (Store txStore, List<dynamic> params) {
            final noteBox = txStore.box<NoteOB>();

            // Save note wrapper
            final note = Note(
              title: params[0][1] as String,
              content: params[0][2] as String,
            );
            note.uuid = params[0][0] as String;
            final noteOB = NoteOB.fromNote(note);
            noteBox.put(noteOB);

            // Throw exception before completing transaction
            throw Exception('Simulated failure');
          },
          [noteData],
        );
        fail('Should have thrown exception');
      } catch (e) {
        expect(e.toString(), contains('Simulated failure'));
      }

      // Verify note was NOT saved (rollback worked)
      final noteBox = store.box<NoteOB>();
      final savedNoteOB = await noteBox
          .query(NoteOB_.uuid.equals('note-uuid-2'))
          .build()
          .findFirst();

      expect(savedNoteOB, isNull, reason: 'Transaction should have rolled back');
    });

    test('runInTransactionAsync with synchronous adapter pattern', () async {
      // Simulate adapter-style operations inside transaction using wrappers
      final result = await store.runInTransactionAsync<String, List<String>>(
        TxMode.write,
        (Store txStore, List<String> params) {
          final noteBox = txStore.box<NoteOB>();

          // Adapter-style save operation using wrappers
          final note1 = Note(title: params[0], content: 'Content 1');
          note1.touch();
          final noteOB1 = NoteOB.fromNote(note1);
          noteBox.put(noteOB1);

          final note2 = Note(title: params[1], content: 'Content 2');
          note2.touch();
          final noteOB2 = NoteOB.fromNote(note2);
          noteBox.put(noteOB2);

          // Return result
          return 'Saved ${params.length} notes';
        },
        ['Note 1', 'Note 2'],
      );

      expect(result, 'Saved 2 notes');

      // Verify both saved using wrappers
      final noteBox = store.box<NoteOB>();
      final all = noteBox.getAll();
      expect(all.length, 2);
    });

    test('verify Box operations are synchronous', () async {
      // This test verifies our adapters use sync operations that work in transactions
      final noteBox = store.box<NoteOB>();

      // Create note wrapper outside transaction
      final note = Note(title: 'Test', content: 'Content');
      final noteOB = NoteOB.fromNote(note);

      // Verify these are synchronous calls (no await needed)
      noteBox.put(noteOB);  // Synchronous
      final retrieved = noteBox.get(noteOB.id);  // Synchronous
      final all = noteBox.getAll();  // Synchronous

      expect(retrieved, isNotNull);
      expect(retrieved!.toNote().title, 'Test');
      expect(all.length, greaterThan(0));
    });
  });
}
