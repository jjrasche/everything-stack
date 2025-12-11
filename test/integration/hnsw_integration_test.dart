/// # HNSW + EntityRepository Integration Tests
///
/// Tests that verify HNSW index integration with EntityRepository using ObjectBox:
/// - Save entity -> generates embedding -> stored with HNSW index
/// - Delete entity -> removes from index
/// - Update entity -> re-indexes
/// - Semantic search finds similar entities
///
/// These tests use MockEmbeddingService for deterministic behavior.
/// The mock generates consistent vectors based on text hash, so:
/// - Same text -> same embedding
/// - Different text -> different embedding (usually)
///
/// Note: Mock doesn't have semantic understanding.
/// We test infrastructure, not semantic quality.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';

import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/domain/note_repository.dart';
import 'package:everything_stack_template/persistence/objectbox/note_objectbox_adapter.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/objectbox.g.dart';

// ============ Tests ============

void main() {
  late Store store;
  late NoteRepository noteRepo;
  late MockEmbeddingService embeddingService;
  late Directory testDir;

  setUp(() async {
    // Create temporary directory for ObjectBox store
    testDir = await Directory.systemTemp.createTemp('objectbox_hnsw_test_');

    // Open ObjectBox store
    store = await openStore(directory: testDir.path);

    // Use mock embedding service
    embeddingService = MockEmbeddingService();

    // Create repository with ObjectBox adapter
    final noteAdapter = NoteObjectBoxAdapter(store);
    noteRepo = NoteRepository(
      adapter: noteAdapter,
      embeddingService: embeddingService,
    );
  });

  tearDown(() async {
    store.close();
    // Clean up temp directory
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('Entity save adds to index', () {
    test('saving Embeddable entity generates embedding and stores it', () async {
      final note = Note(title: 'Test Note', content: 'Some content');
      final noteUuid = note.uuid;

      await noteRepo.save(note);

      // Verify embedding was generated
      final saved = await noteRepo.findByUuid(noteUuid);
      expect(saved, isNotNull);
      expect(saved!.embedding, isNotNull);
      expect(saved.embedding!.length, EmbeddingService.dimension);
    });

    test('semantic search finds saved entity', () async {
      final note = Note(
        title: 'Meeting Notes',
        content: 'Discussed project timeline and milestones',
      );
      await noteRepo.save(note);

      // Search with same text should find it
      final results = await noteRepo.semanticSearch(
        'Meeting Notes\nDiscussed project timeline and milestones',
        limit: 5,
      );

      expect(results.length, 1);
      expect(results.first.title, 'Meeting Notes');
    });

    test('saveAll adds all entities with embeddings', () async {
      final notes = [
        Note(title: 'Note A', content: 'Content A'),
        Note(title: 'Note B', content: 'Content B'),
        Note(title: 'Note C', content: 'Content C'),
      ];

      await noteRepo.saveAll(notes);

      // Verify all have embeddings
      for (final note in notes) {
        final saved = await noteRepo.findByUuid(note.uuid);
        expect(saved!.embedding, isNotNull);
      }

      // Verify count
      final count = await noteRepo.count();
      expect(count, 3);
    });
  });

  group('Entity delete removes from index', () {
    test('deleting entity removes it', () async {
      final note = Note(title: 'To Delete', content: 'Will be removed');
      final noteUuid = note.uuid;
      final id = await noteRepo.save(note);

      expect(await noteRepo.findByUuid(noteUuid), isNotNull);

      await noteRepo.delete(id);

      expect(await noteRepo.findByUuid(noteUuid), isNull);
    });

    test('deleted entity not returned in semantic search', () async {
      final note1 = Note(title: 'Keep', content: 'Staying');
      final note2 = Note(title: 'Remove', content: 'Going away');
      final uuid1 = note1.uuid;
      final uuid2 = note2.uuid;

      await noteRepo.save(note1);
      final id2 = await noteRepo.save(note2);

      await noteRepo.delete(id2);

      // Search should only find note1
      final results = await noteRepo.semanticSearch('Keep\nStaying', limit: 10);
      expect(results.map((n) => n.uuid), contains(uuid1));
      expect(results.map((n) => n.uuid), isNot(contains(uuid2)));
    });

    test('deleteAll removes all', () async {
      final notes = [
        Note(title: 'A'),
        Note(title: 'B'),
        Note(title: 'C'),
      ];
      await noteRepo.saveAll(notes);
      final ids = notes.map((n) => n.id).toList();

      expect(await noteRepo.count(), 3);

      await noteRepo.deleteAll(ids);

      expect(await noteRepo.count(), 0);
    });
  });

  group('Entity update re-indexes', () {
    test('updating entity content re-generates embedding', () async {
      final note = Note(title: 'Original', content: 'First version');
      final noteUuid = note.uuid;
      await noteRepo.save(note);

      final originalEmbedding = List<double>.from(note.embedding!);

      // Update content
      note.title = 'Updated';
      note.content = 'Second version with different text';
      await noteRepo.save(note);

      // Embedding should have changed
      final updated = await noteRepo.findByUuid(noteUuid);
      expect(updated!.embedding, isNot(equals(originalEmbedding)));
    });

    test('search reflects updated content', () async {
      final note = Note(title: 'Apples', content: 'About apples');
      final noteUuid = note.uuid;
      await noteRepo.save(note);

      // Search for original content
      var results = await noteRepo.semanticSearch('Apples\nAbout apples');
      expect(results.length, 1);

      // Update to different content
      note.title = 'Bananas';
      note.content = 'About bananas';
      await noteRepo.save(note);

      // Search for new content should find it
      results = await noteRepo.semanticSearch('Bananas\nAbout bananas');
      expect(results.length, 1);
      expect(results.first.uuid, noteUuid);
      expect(results.first.title, 'Bananas');
    });
  });

  group('UUID uniqueness', () {
    test('each entity gets unique uuid', () async {
      final note1 = Note(title: 'Note 1');
      final note2 = Note(title: 'Note 2');

      expect(note1.uuid, isNot(equals(note2.uuid)));
    });

    test('uuid is stable across saves', () async {
      final note = Note(title: 'Original');
      final originalUuid = note.uuid;

      await noteRepo.save(note);

      // Update and save again
      note.title = 'Updated';
      await noteRepo.save(note);

      // uuid should not change
      expect(note.uuid, originalUuid);

      // Reload from database and verify
      final reloaded = await noteRepo.findByUuid(originalUuid);
      expect(reloaded, isNotNull);
      expect(reloaded!.uuid, originalUuid);
    });

    test('findByUuid works correctly', () async {
      final note = Note(title: 'Findable');
      final noteUuid = note.uuid;
      await noteRepo.save(note);

      final found = await noteRepo.findByUuid(noteUuid);
      expect(found, isNotNull);
      expect(found!.title, 'Findable');
      expect(found.uuid, noteUuid);

      // Non-existent uuid returns null
      final notFound = await noteRepo.findByUuid('non-existent-uuid');
      expect(notFound, isNull);
    });
  });

  group('Edge cases', () {
    test('empty embedding input skips indexing', () async {
      final note = Note(title: '', content: '');
      final noteUuid = note.uuid;
      await noteRepo.save(note);

      // Empty input should result in null embedding
      final saved = await noteRepo.findByUuid(noteUuid);
      expect(saved!.embedding, isNull);
    });

    test('search with no indexed entities returns empty', () async {
      final results = await noteRepo.semanticSearch('anything');
      expect(results, isEmpty);
    });

    test('concurrent saves maintain consistency', () async {
      // Save multiple entities concurrently
      final notes = List.generate(10, (i) => Note(title: 'Note $i'));
      final uuids = notes.map((n) => n.uuid).toList();

      final futures = notes.map((n) => noteRepo.save(n));
      await Future.wait(futures);

      expect(await noteRepo.count(), 10);
      for (final uuid in uuids) {
        expect(await noteRepo.findByUuid(uuid), isNotNull);
      }
    });

    test('re-saving same entity updates rather than duplicates', () async {
      final note = Note(title: 'Original');
      await noteRepo.save(note);

      // Save again (simulating update)
      note.title = 'Updated';
      await noteRepo.save(note);

      // Should still be only one entry
      expect(await noteRepo.count(), 1);
    });
  });

  group('UUID preservation and indexed lookup', () {
    test('uuid is preserved when loading from ObjectBox', () async {
      // Create entity - uuid is auto-generated
      final original = Note(title: 'Test', content: 'Content');
      final originalUuid = original.uuid;

      // Save to database
      await noteRepo.save(original);

      // Load from database using the O(1) indexed uuid lookup
      final loaded = await noteRepo.findByUuid(originalUuid);

      // Verify uuid is identical (not regenerated)
      expect(loaded, isNotNull);
      expect(loaded!.uuid, equals(originalUuid),
          reason: 'uuid should be preserved from database, not regenerated');
    });

    test('O(1) indexed findByUuid lookup works correctly', () async {
      // Create multiple entities with different uuids
      final note1 = Note(title: 'Note 1');
      final note2 = Note(title: 'Note 2');
      final note3 = Note(title: 'Note 3');

      final uuid1 = note1.uuid;
      final uuid2 = note2.uuid;
      final uuid3 = note3.uuid;

      // Save all
      await noteRepo.saveAll([note1, note2, note3]);

      // Lookup each by uuid
      final found1 = await noteRepo.findByUuid(uuid1);
      final found2 = await noteRepo.findByUuid(uuid2);
      final found3 = await noteRepo.findByUuid(uuid3);

      // All should be found with correct uuid (O(1) indexed lookup)
      expect(found1?.uuid, uuid1);
      expect(found2?.uuid, uuid2);
      expect(found3?.uuid, uuid3);
    });

    test('findByUuid returns null for non-existent uuid', () async {
      final result = await noteRepo.findByUuid('non-existent-uuid-12345');
      expect(result, isNull);
    });
  });
}
