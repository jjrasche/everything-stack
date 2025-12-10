/// # HNSW + EntityRepository Integration Tests
///
/// Tests that verify HNSW index integration with EntityRepository:
/// - Save entity -> generates embedding -> adds to index by uuid
/// - Delete entity -> removes from index
/// - Update entity -> re-indexes
/// - Index persists across repository restarts
/// - Rebuild index from entities when missing/corrupt
///
/// These tests use MockEmbeddingService for deterministic behavior.
/// The mock generates consistent vectors based on text hash, so:
/// - Same text -> same embedding
/// - Different text -> different embedding (usually)
///
/// Note: Mock doesn't have semantic understanding.
/// We test infrastructure, not semantic quality.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/patterns/embeddable.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';

part 'hnsw_integration_test.g.dart';

// ============ Test Entities ============

/// Embeddable test entity (simulates Note)
@Collection()
class TestNote extends BaseEntity with Embeddable {
  // Override uuid with @Index for O(1) findByUuid() lookups
  // Initialize with base class value to enable Isar serialization
  @Index(unique: true)
  @override
  String uuid = '';

  @override
  @enumerated
  SyncStatus syncStatus = SyncStatus.local;

  String title;
  String content;

  TestNote({required this.title, this.content = ''}) {
    // Ensure uuid is generated if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  @override
  String toEmbeddingInput() => '$title\n$content';
}

/// Non-embeddable entity - should not be indexed
@Collection()
class TestConfig extends BaseEntity {
  // Override uuid with @Index for O(1) findByUuid() lookups
  // Initialize with base class value to enable Isar serialization
  @Index(unique: true)
  @override
  String uuid = '';

  @override
  @enumerated
  SyncStatus syncStatus = SyncStatus.local;

  String key;
  String value;

  TestConfig({required this.key, required this.value}) {
    // Ensure uuid is generated if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }
}

// ============ Test Repositories ============

class TestNoteRepository extends EntityRepository<TestNote> {
  TestNoteRepository(super.isar, {super.hnswIndex, super.embeddingService});

  @override
  IsarCollection<TestNote> get collection => isar.testNotes;
}

class TestConfigRepository extends EntityRepository<TestConfig> {
  TestConfigRepository(super.isar, {super.hnswIndex, super.embeddingService});

  @override
  IsarCollection<TestConfig> get collection => isar.testConfigs;
}

// ============ Tests ============

void main() {
  late Isar isar;
  late HnswIndex hnswIndex;
  late MockEmbeddingService embeddingService;
  late TestNoteRepository noteRepo;
  late TestConfigRepository configRepo;

  setUp(() async {
    // Initialize Isar for testing
    await Isar.initializeIsarCore(download: true);
    isar = await Isar.open(
      [TestNoteSchema, TestConfigSchema],
      directory: '',
      name: 'test_${DateTime.now().millisecondsSinceEpoch}',
    );

    // Create shared HNSW index (Option A: global index)
    // Now uses String UUIDs as keys
    hnswIndex = HnswIndex(
      dimensions: EmbeddingService.dimension,
      seed: 42, // Deterministic for tests
    );

    // Use mock embedding service
    embeddingService = MockEmbeddingService();

    // Create repositories sharing the same index
    noteRepo = TestNoteRepository(
      isar,
      hnswIndex: hnswIndex,
      embeddingService: embeddingService,
    );
    configRepo = TestConfigRepository(
      isar,
      hnswIndex: hnswIndex,
      embeddingService: embeddingService,
    );
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
  });

  group('Entity save adds to index', () {
    test('saving Embeddable entity generates embedding and adds to index by uuid', () async {
      final note = TestNote(title: 'Test Note', content: 'Some content');
      final noteUuid = note.uuid; // Capture uuid before save

      await noteRepo.save(note);

      // Verify embedding was generated
      final saved = await noteRepo.findByUuid(noteUuid);
      expect(saved, isNotNull);
      expect(saved!.embedding, isNotNull);
      expect(saved.embedding!.length, EmbeddingService.dimension);

      // Verify added to HNSW index by uuid
      expect(hnswIndex.contains(noteUuid), isTrue);
      expect(hnswIndex.size, 1);
    });

    test('semantic search finds saved entity', () async {
      final note = TestNote(
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

    test('saveAll adds all entities to index by uuid', () async {
      final notes = [
        TestNote(title: 'Note A', content: 'Content A'),
        TestNote(title: 'Note B', content: 'Content B'),
        TestNote(title: 'Note C', content: 'Content C'),
      ];
      final uuids = notes.map((n) => n.uuid).toList();

      await noteRepo.saveAll(notes);

      expect(hnswIndex.size, 3);
      for (var i = 0; i < notes.length; i++) {
        expect(notes[i].embedding, isNotNull);
        expect(hnswIndex.contains(uuids[i]), isTrue);
      }
    });
  });

  group('Entity delete removes from index', () {
    test('deleting entity removes from HNSW index by uuid', () async {
      final note = TestNote(title: 'To Delete', content: 'Will be removed');
      final noteUuid = note.uuid;
      final id = await noteRepo.save(note);

      expect(hnswIndex.contains(noteUuid), isTrue);

      await noteRepo.delete(id);

      expect(hnswIndex.contains(noteUuid), isFalse);
      expect(hnswIndex.size, 0);
    });

    test('deleted entity not returned in semantic search', () async {
      final note1 = TestNote(title: 'Keep', content: 'Staying');
      final note2 = TestNote(title: 'Remove', content: 'Going away');
      final uuid1 = note1.uuid;
      final uuid2 = note2.uuid;

      final id1 = await noteRepo.save(note1);
      final id2 = await noteRepo.save(note2);

      await noteRepo.delete(id2);

      // Search with exact content should find note1
      // (Mock embeddings are hash-based, not semantic)
      final results = await noteRepo.semanticSearch('Keep\nStaying', limit: 10);
      expect(results.map((n) => n.uuid), contains(uuid1));
      expect(results.map((n) => n.uuid), isNot(contains(uuid2)));
    });

    test('deleteAll removes all from index', () async {
      final notes = [
        TestNote(title: 'A'),
        TestNote(title: 'B'),
        TestNote(title: 'C'),
      ];
      final uuids = notes.map((n) => n.uuid).toList();
      await noteRepo.saveAll(notes);
      final ids = notes.map((n) => n.id!).toList();

      expect(hnswIndex.size, 3);

      await noteRepo.deleteAll(ids);

      expect(hnswIndex.size, 0);
      for (final uuid in uuids) {
        expect(hnswIndex.contains(uuid), isFalse);
      }
    });
  });

  group('Entity update re-indexes', () {
    test('updating entity content re-generates embedding', () async {
      final note = TestNote(title: 'Original', content: 'First version');
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

      // Index should still contain the uuid (with updated vector)
      expect(hnswIndex.contains(noteUuid), isTrue);
      expect(hnswIndex.size, 1);
    });

    test('search reflects updated content', () async {
      final note = TestNote(title: 'Apples', content: 'About apples');
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

  group('Index persistence', () {
    test('index serializes and deserializes correctly with uuid keys', () async {
      // Save some entities
      final note1 = TestNote(title: 'Note 1', content: 'Content 1');
      final note2 = TestNote(title: 'Note 2', content: 'Content 2');
      final note3 = TestNote(title: 'Note 3', content: 'Content 3');
      await noteRepo.save(note1);
      await noteRepo.save(note2);
      await noteRepo.save(note3);

      // Serialize the index
      final bytes = hnswIndex.toBytes();

      // Create new index from bytes
      final restoredIndex = HnswIndex.fromBytes(bytes);

      expect(restoredIndex.size, 3);
      expect(restoredIndex.contains(note1.uuid), isTrue);
      expect(restoredIndex.contains(note2.uuid), isTrue);
      expect(restoredIndex.contains(note3.uuid), isTrue);

      // Search should work on restored index
      final results = restoredIndex.search(
        await embeddingService.generate('Note 1\nContent 1'),
        k: 3,
      );
      expect(results.length, 3);
    });

    test('repository can restore index on init', () async {
      // Save entities and serialize index
      final note1 = TestNote(title: 'Persistent 1');
      final note2 = TestNote(title: 'Persistent 2');
      await noteRepo.save(note1);
      await noteRepo.save(note2);

      final serializedBytes = hnswIndex.toBytes();

      // Simulate restart: create new index from bytes
      final restoredIndex = HnswIndex.fromBytes(serializedBytes);

      // Create new repository with restored index
      final newRepo = TestNoteRepository(
        isar,
        hnswIndex: restoredIndex,
        embeddingService: embeddingService,
      );

      // Search with exact content should work
      // (Mock embeddings are hash-based, not semantic)
      final results1 = await newRepo.semanticSearch('Persistent 1\n', limit: 10);
      expect(results1.length, 1);
      expect(results1.first.title, 'Persistent 1');

      final results2 = await newRepo.semanticSearch('Persistent 2\n', limit: 10);
      expect(results2.length, 1);
      expect(results2.first.title, 'Persistent 2');
    });

    test('index bytes can be stored in Isar', () async {
      // This test verifies the pattern of storing index in database
      await noteRepo.save(TestNote(title: 'Test'));

      final bytes = hnswIndex.toBytes();

      // Store bytes (would typically go in a settings/metadata collection)
      // For this test, just verify bytes are valid
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(0));

      // Verify can restore
      final restored = HnswIndex.fromBytes(bytes);
      expect(restored.size, 1);
    });
  });

  group('Rebuild index from entities', () {
    test('rebuildIndex recreates index from all Embeddable entities', () async {
      // Save entities with embeddings
      final note1 = TestNote(title: 'Note 1', content: 'Content 1');
      final note2 = TestNote(title: 'Note 2', content: 'Content 2');
      final note3 = TestNote(title: 'Note 3', content: 'Content 3');
      await noteRepo.save(note1);
      await noteRepo.save(note2);
      await noteRepo.save(note3);

      expect(hnswIndex.size, 3);

      // Simulate corrupt/missing index by creating empty one
      final freshIndex = HnswIndex(
        dimensions: EmbeddingService.dimension,
        seed: 42,
      );
      final repoWithEmptyIndex = TestNoteRepository(
        isar,
        hnswIndex: freshIndex,
        embeddingService: embeddingService,
      );

      expect(freshIndex.size, 0);

      // Rebuild index from stored entities
      await repoWithEmptyIndex.rebuildIndex();

      // Index should be restored
      expect(freshIndex.size, 3);
      expect(freshIndex.contains(note1.uuid), isTrue);
      expect(freshIndex.contains(note2.uuid), isTrue);
      expect(freshIndex.contains(note3.uuid), isTrue);

      // Search with exact content should work
      // (Mock embeddings are hash-based, not semantic)
      final results = await repoWithEmptyIndex.semanticSearch('Note 1\nContent 1', limit: 10);
      expect(results.length, 1);
      expect(results.first.title, 'Note 1');
    });

    test('rebuildIndex regenerates missing embeddings', () async {
      // Manually insert entities without embeddings (simulating data migration)
      await isar.writeTxn(() async {
        await isar.testNotes.putAll([
          TestNote(title: 'No Embedding 1'),
          TestNote(title: 'No Embedding 2'),
        ]);
      });

      // Verify embeddings are null
      final all = await noteRepo.findAll();
      expect(all.every((n) => n.embedding == null), isTrue);

      // Create fresh index and rebuild
      final freshIndex = HnswIndex(
        dimensions: EmbeddingService.dimension,
        seed: 42,
      );
      final repoWithEmptyIndex = TestNoteRepository(
        isar,
        hnswIndex: freshIndex,
        embeddingService: embeddingService,
      );

      await repoWithEmptyIndex.rebuildIndex();

      // All entities should now have embeddings
      final afterRebuild = await repoWithEmptyIndex.findAll();
      expect(afterRebuild.every((n) => n.embedding != null), isTrue);

      // And be in the index
      expect(freshIndex.size, 2);
    });

    test('rebuildIndex skips entities with empty embedding input', () async {
      // Save entity with content and one without
      await noteRepo.save(TestNote(title: 'Has Content'));

      // Manually insert empty entity
      await isar.writeTxn(() async {
        await isar.testNotes.put(TestNote(title: '', content: ''));
      });

      final freshIndex = HnswIndex(
        dimensions: EmbeddingService.dimension,
        seed: 42,
      );
      final repoWithEmptyIndex = TestNoteRepository(
        isar,
        hnswIndex: freshIndex,
        embeddingService: embeddingService,
      );

      await repoWithEmptyIndex.rebuildIndex();

      // Only entity with content should be indexed
      expect(freshIndex.size, 1);
    });
  });

  group('Non-Embeddable entities', () {
    test('non-Embeddable entity not added to index', () async {
      final config = TestConfig(key: 'setting', value: 'enabled');

      await configRepo.save(config);

      // Should not be in HNSW index (uuid not added)
      expect(hnswIndex.contains(config.uuid), isFalse);
      expect(hnswIndex.size, 0);
    });

    test('semantic search on non-Embeddable returns empty', () async {
      final config = TestConfig(key: 'api_key', value: 'secret');
      await configRepo.save(config);

      // semanticSearch should return empty (no embeddings to search)
      final results = await configRepo.semanticSearch('api key');
      expect(results, isEmpty);
    });

    test('mixed save does not affect non-Embeddable', () async {
      final note = TestNote(title: 'Note');
      final config = TestConfig(key: 'key', value: 'value');

      await noteRepo.save(note);
      await configRepo.save(config);

      // Only note should be in index (by uuid)
      // With uuid keys, there's no ID collision issue
      expect(hnswIndex.size, 1);
      expect(hnswIndex.contains(note.uuid), isTrue);
      expect(hnswIndex.contains(config.uuid), isFalse);
    });
  });

  group('UUID uniqueness', () {
    test('each entity gets unique uuid', () async {
      final note1 = TestNote(title: 'Note 1');
      final note2 = TestNote(title: 'Note 2');
      final config = TestConfig(key: 'key', value: 'value');

      expect(note1.uuid, isNot(equals(note2.uuid)));
      expect(note1.uuid, isNot(equals(config.uuid)));
      expect(note2.uuid, isNot(equals(config.uuid)));
    });

    test('uuid is stable across saves', () async {
      final note = TestNote(title: 'Original');
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
      final note = TestNote(title: 'Findable');
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
      final note = TestNote(title: '', content: '');
      final noteUuid = note.uuid;
      await noteRepo.save(note);

      // Empty input should result in null embedding
      final saved = await noteRepo.findByUuid(noteUuid);
      expect(saved!.embedding, isNull);

      // Should not be in index
      expect(hnswIndex.contains(noteUuid), isFalse);
    });

    test('search with no indexed entities returns empty', () async {
      final results = await noteRepo.semanticSearch('anything');
      expect(results, isEmpty);
    });

    test('concurrent saves maintain index consistency', () async {
      // Save multiple entities concurrently
      final notes = List.generate(10, (i) => TestNote(title: 'Note $i'));
      final uuids = notes.map((n) => n.uuid).toList();

      final futures = notes.map((n) => noteRepo.save(n));
      await Future.wait(futures);

      expect(hnswIndex.size, 10);
      for (final uuid in uuids) {
        expect(hnswIndex.contains(uuid), isTrue);
      }
    });

    test('re-saving same entity updates rather than duplicates', () async {
      final note = TestNote(title: 'Original');
      final noteUuid = note.uuid;
      await noteRepo.save(note);

      // Save again (simulating update)
      note.title = 'Updated';
      await noteRepo.save(note);

      // Should still be only one entry
      expect(hnswIndex.size, 1);
      expect(hnswIndex.contains(noteUuid), isTrue);
    });
  });

  group('UUID preservation and indexed lookup', () {
    test('uuid is preserved when loading from Isar (not regenerated by late default)', () async {
      // Create entity - uuid is auto-generated
      final original = TestNote(title: 'Test', content: 'Content');
      final originalUuid = original.uuid;

      // Save to database
      await noteRepo.save(original);

      // Load from database using the O(1) indexed uuid lookup
      final loaded = await noteRepo.findByUuid(originalUuid);

      // Verify uuid is identical (not regenerated)
      expect(loaded, isNotNull);
      expect(loaded!.uuid, equals(originalUuid),
          reason: 'uuid should be preserved from database, not regenerated by late default');
    });

    test('O(1) indexed findByUuid lookup works correctly', () async {
      // Create multiple entities with different uuids
      final note1 = TestNote(title: 'Note 1');
      final note2 = TestNote(title: 'Note 2');
      final note3 = TestNote(title: 'Note 3');

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
