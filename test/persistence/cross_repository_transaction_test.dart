/// Test cross-repository transactions (Entity + Version)
///
/// This verifies that we can atomically save an entity and its version
/// in a single transaction, even though they use different adapters.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/core/entity_version.dart';
import 'package:everything_stack_template/persistence/objectbox/note_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/entity_version_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/note_ob.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/entity_version_ob.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late Directory testDir;
  late NoteObjectBoxAdapter noteAdapter;
  late EntityVersionObjectBoxAdapter versionAdapter;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('objectbox_cross_tx_test_');
    store = await openStore(directory: testDir.path);
    noteAdapter = NoteObjectBoxAdapter(store);
    versionAdapter = EntityVersionObjectBoxAdapter(store);
  });

  tearDown(() async {
    store.close();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('Cross-Repository Transactions', () {
    test('save entity + version atomically using adapters', () async {
      // Test data
      final note = Note(title: 'Test Note', content: 'Test Content');
      final noteUuid = note.uuid;

      // Execute in transaction using wrapper entities
      await store.runInTransactionAsync<void, Map<String, dynamic>>(
        TxMode.write,
        (Store txStore, Map<String, dynamic> params) {
          // Access wrapper boxes in transaction
          final noteBox = txStore.box<NoteOB>();
          final versionBox = txStore.box<EntityVersionOB>();

          // Save note using wrapper
          final note = params['note'] as Note;
          note.touch();
          final noteOB = NoteOB.fromNote(note);
          noteBox.put(noteOB);

          // Save version using wrapper
          final version = EntityVersion(
            entityType: 'Note',
            entityUuid: note.uuid,
            timestamp: DateTime.now(),
            versionNumber: 1,
            deltaJson: '{"title":"Test Note","content":"Test Content"}',
            changedFields: ['title', 'content'],
            isSnapshot: true,
          );
          final versionOB = EntityVersionOB.fromEntityVersion(version);
          versionBox.put(versionOB);
        },
        {'note': note},
      );

      // Verify both were saved
      final savedNote = await noteAdapter.findByUuid(noteUuid);
      final versions = await versionAdapter.findByEntityUuid(noteUuid);

      expect(savedNote, isNotNull);
      expect(savedNote!.title, 'Test Note');
      expect(versions.length, 1);
      expect(versions[0].versionNumber, 1);
    });

    test('rollback works for entity + version', () async {
      final note = Note(title: 'Rollback Test', content: 'Content');
      final noteUuid = note.uuid;

      try {
        await store.runInTransactionAsync<void, Map<String, dynamic>>(
          TxMode.write,
          (Store txStore, Map<String, dynamic> params) {
            final noteBox = txStore.box<NoteOB>();
            final versionBox = txStore.box<EntityVersionOB>();

            // Save note using wrapper
            final note = params['note'] as Note;
            note.touch();
            final noteOB = NoteOB.fromNote(note);
            noteBox.put(noteOB);

            // Save version using wrapper
            final version = EntityVersion(
              entityType: 'Note',
              entityUuid: note.uuid,
              timestamp: DateTime.now(),
              versionNumber: 1,
              deltaJson: '{}',
              changedFields: [],
              isSnapshot: true,
            );
            final versionOB = EntityVersionOB.fromEntityVersion(version);
            versionBox.put(versionOB);

            // Simulate failure after both operations
            throw Exception('Simulated failure after both saves');
          },
          {'note': note},
        );
        fail('Should have thrown exception');
      } catch (e) {
        expect(e.toString(), contains('Simulated failure'));
      }

      // Verify NEITHER was saved (atomic rollback)
      final savedNote = await noteAdapter.findByUuid(noteUuid);
      final versions = await versionAdapter.findByEntityUuid(noteUuid);

      expect(savedNote, isNull, reason: 'Note should have rolled back');
      expect(versions, isEmpty, reason: 'Version should have rolled back');
    });

    test('partial failure rolls back everything', () async {
      final note = Note(title: 'Partial Failure', content: 'Content');
      final noteUuid = note.uuid;

      try {
        await store.runInTransactionAsync<void, Map<String, dynamic>>(
          TxMode.write,
          (Store txStore, Map<String, dynamic> params) {
            final noteBox = txStore.box<NoteOB>();

            // Save note using wrapper
            final note = params['note'] as Note;
            note.touch();
            final noteOB = NoteOB.fromNote(note);
            noteBox.put(noteOB);

            // Verify note wrapper is saved (within transaction)
            final check = noteBox.get(noteOB.id);
            if (check == null) {
              throw Exception('Note save failed');
            }

            // Fail before saving version
            throw Exception('Failure before version save');
          },
          {'note': note},
        );
        fail('Should have thrown exception');
      } catch (e) {
        expect(e.toString(), contains('Failure before version save'));
      }

      // Verify note was rolled back even though put() succeeded
      final savedNote = await noteAdapter.findByUuid(noteUuid);
      expect(savedNote, isNull, reason: 'Transaction should rollback all operations');
    });

    test('multiple entities + versions in single transaction', () async {
      final note1 = Note(title: 'Note 1', content: 'Content 1');
      final note2 = Note(title: 'Note 2', content: 'Content 2');

      await store.runInTransactionAsync<void, List<Note>>(
        TxMode.write,
        (Store txStore, List<Note> notes) {
          final noteBox = txStore.box<NoteOB>();
          final versionBox = txStore.box<EntityVersionOB>();

          for (final note in notes) {
            // Save note using wrapper
            note.touch();
            final noteOB = NoteOB.fromNote(note);
            noteBox.put(noteOB);

            // Save version using wrapper
            final version = EntityVersion(
              entityType: 'Note',
              entityUuid: note.uuid,
              timestamp: DateTime.now(),
              versionNumber: 1,
              deltaJson: '{}',
              changedFields: ['title', 'content'],
              isSnapshot: true,
            );
            final versionOB = EntityVersionOB.fromEntityVersion(version);
            versionBox.put(versionOB);
          }
        },
        [note1, note2],
      );

      // Verify all saved
      final savedNote1 = await noteAdapter.findByUuid(note1.uuid);
      final savedNote2 = await noteAdapter.findByUuid(note2.uuid);
      final versions1 = await versionAdapter.findByEntityUuid(note1.uuid);
      final versions2 = await versionAdapter.findByEntityUuid(note2.uuid);

      expect(savedNote1, isNotNull);
      expect(savedNote2, isNotNull);
      expect(versions1.length, 1);
      expect(versions2.length, 1);
    });
  });
}
