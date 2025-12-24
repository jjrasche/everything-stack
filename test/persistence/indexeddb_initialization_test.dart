/// Test IndexedDB database initialization and schema creation.
///
/// Verifies:
/// 1. Database opens successfully
/// 2. All object stores created
/// 3. All indexes created
/// 4. Basic CRUD operations work
/// 5. Database closes cleanly

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:everything_stack_template/persistence/indexeddb/database_init.dart';
import 'package:everything_stack_template/persistence/indexeddb/database_schema.dart';
import 'package:everything_stack_template/persistence/indexeddb/note_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/edge_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/entity_version_indexeddb_adapter.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/core/edge.dart';
import 'package:everything_stack_template/core/entity_version.dart';

void main() {
  late IdbFactory idbFactory;
  late Database db;

  setUp(() async {
    // Use in-memory IndexedDB for testing
    idbFactory = newIdbFactoryMemory();

    // Open database
    db = await openIndexedDatabase(idbFactory: idbFactory);
  });

  tearDown(() async {
    // Close database
    await closeIndexedDatabase(db);

    // Delete database
    await deleteIndexedDatabase(idbFactory: idbFactory);
  });

  group('IndexedDB Initialization', () {
    test('database opens successfully', () {
      expect(db, isNotNull);
      expect(db.name, DatabaseSchema.name);
      expect(db.version, DatabaseSchema.version);
    });

    test('all object stores are created', () {
      final storeNames = db.objectStoreNames;

      expect(storeNames.contains(ObjectStores.notes), isTrue);
      expect(storeNames.contains(ObjectStores.edges), isTrue);
      expect(storeNames.contains(ObjectStores.entityVersions), isTrue);
      expect(storeNames.contains(ObjectStores.hnswIndex), isTrue);
    });

    test('notes object store has correct indexes', () async {
      final txn = db.transaction(ObjectStores.notes, idbModeReadOnly);
      final store = txn.objectStore(ObjectStores.notes);

      expect(store.keyPath, 'uuid');
      expect(store.autoIncrement, isFalse);

      final indexNames = store.indexNames;
      expect(indexNames.contains(Indexes.notesId), isTrue);
      expect(indexNames.contains(Indexes.notesUuid), isTrue);
      expect(indexNames.contains(Indexes.notesSyncStatus), isTrue);
      expect(indexNames.contains(Indexes.notesPinned), isTrue);
      expect(indexNames.contains(Indexes.notesArchived), isTrue);
    });

    test('edges object store has correct indexes', () async {
      final txn = db.transaction(ObjectStores.edges, idbModeReadOnly);
      final store = txn.objectStore(ObjectStores.edges);

      expect(store.keyPath, 'uuid');
      expect(store.autoIncrement, isFalse);

      final indexNames = store.indexNames;
      expect(indexNames.contains(Indexes.edgesId), isTrue);
      expect(indexNames.contains(Indexes.edgesUuid), isTrue);
      expect(indexNames.contains(Indexes.edgesSyncStatus), isTrue);
      expect(indexNames.contains(Indexes.edgesSourceUuid), isTrue);
      expect(indexNames.contains(Indexes.edgesTargetUuid), isTrue);
      expect(indexNames.contains(Indexes.edgesEdgeType), isTrue);
    });

    test('entity_versions object store has correct indexes', () async {
      final txn = db.transaction(ObjectStores.entityVersions, idbModeReadOnly);
      final store = txn.objectStore(ObjectStores.entityVersions);

      expect(store.keyPath, 'uuid');
      expect(store.autoIncrement, isFalse);

      final indexNames = store.indexNames;
      expect(indexNames.contains(Indexes.versionsId), isTrue);
      expect(indexNames.contains(Indexes.versionsUuid), isTrue);
      expect(indexNames.contains(Indexes.versionsSyncStatus), isTrue);
      expect(indexNames.contains(Indexes.versionsEntityUuid), isTrue);
      expect(indexNames.contains(Indexes.versionsEntityType), isTrue);
    });

    test('_hnsw_index object store exists', () async {
      final txn = db.transaction(ObjectStores.hnswIndex, idbModeReadOnly);
      final store = txn.objectStore(ObjectStores.hnswIndex);

      expect(store.keyPath, 'key');
      expect(store.autoIncrement, isFalse);
    });
  });

  group('IndexedDB Adapters - CRUD Operations', () {
    late NoteIndexedDBAdapter noteAdapter;
    late EdgeIndexedDBAdapter edgeAdapter;
    late EntityVersionIndexedDBAdapter versionAdapter;

    setUp(() {
      noteAdapter = NoteIndexedDBAdapter(db);
      edgeAdapter = EdgeIndexedDBAdapter(db);
      versionAdapter = EntityVersionIndexedDBAdapter(db);
    });

    test('can save and retrieve a note', () async {
      // Create note
      final note = Note(
        title: 'Test Note',
        content: 'Test content',
        tags: ['test', 'indexeddb'],
      );

      // Save note
      final saved = await noteAdapter.save(note);
      expect(saved.id, greaterThan(0)); // Should have ID assigned
      expect(saved.uuid, isNotEmpty);

      // Retrieve by UUID
      final retrieved = await noteAdapter.findByUuid(saved.uuid);
      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Test Note');
      expect(retrieved.content, 'Test content');
      expect(retrieved.tags, ['test', 'indexeddb']);

      // Retrieve by ID
      final retrievedById = await noteAdapter.findById(saved.id);
      expect(retrievedById, isNotNull);
      expect(retrievedById!.uuid, saved.uuid);
    });

    test('can save and retrieve an edge', () async {
      // Create edge
      final edge = Edge(
        sourceType: 'Note',
        sourceUuid: 'note-uuid-1',
        targetType: 'Note',
        targetUuid: 'note-uuid-2',
        edgeType: 'references',
      );

      // Save edge
      final saved = await edgeAdapter.save(edge);
      expect(saved.id, greaterThan(0));
      expect(saved.uuid, isNotEmpty);

      // Retrieve by UUID
      final retrieved = await edgeAdapter.findByUuid(saved.uuid);
      expect(retrieved, isNotNull);
      expect(retrieved!.sourceUuid, 'note-uuid-1');
      expect(retrieved.targetUuid, 'note-uuid-2');
      expect(retrieved.edgeType, 'references');

      // Retrieve by ID
      final retrievedById = await edgeAdapter.findById(saved.id);
      expect(retrievedById, isNotNull);
      expect(retrievedById!.uuid, saved.uuid);
    });

    test('can save and retrieve an entity version', () async {
      // Create version
      final version = EntityVersion(
        entityType: 'Note',
        entityUuid: 'note-uuid-1',
        timestamp: DateTime.now(),
        versionNumber: 1,
        deltaJson: '{"op": "add", "path": "/title", "value": "New Title"}',
        changedFields: ['title'],
        isSnapshot: true,
        snapshotJson: '{"title": "New Title", "content": "..."}',
      );

      // Save version
      final saved = await versionAdapter.save(version);
      expect(saved.id, greaterThan(0));
      expect(saved.uuid, isNotEmpty);

      // Retrieve by UUID
      final retrieved = await versionAdapter.findByUuid(saved.uuid);
      expect(retrieved, isNotNull);
      expect(retrieved!.entityUuid, 'note-uuid-1');
      expect(retrieved.versionNumber, 1);
      expect(retrieved.isSnapshot, isTrue);

      // Retrieve by ID
      final retrievedById = await versionAdapter.findById(saved.id);
      expect(retrievedById, isNotNull);
      expect(retrievedById!.uuid, saved.uuid);
    });

    test('can update and delete entities', () async {
      // Create and save note
      final note = Note(title: 'Original Title');
      final saved = await noteAdapter.save(note);

      // Update note
      saved.title = 'Updated Title';
      await noteAdapter.save(saved);

      // Verify update
      final updated = await noteAdapter.findByUuid(saved.uuid);
      expect(updated!.title, 'Updated Title');

      // Delete note
      final deleted = await noteAdapter.deleteByUuid(saved.uuid);
      expect(deleted, isTrue);

      // Verify deletion
      final notFound = await noteAdapter.findByUuid(saved.uuid);
      expect(notFound, isNull);
    });

    test('findAll returns all entities', () async {
      // Create multiple notes
      await noteAdapter.save(Note(title: 'Note 1'));
      await noteAdapter.save(Note(title: 'Note 2'));
      await noteAdapter.save(Note(title: 'Note 3'));

      // Find all
      final all = await noteAdapter.findAll();
      expect(all.length, 3);
      expect(all.map((n) => n.title).toSet(), {'Note 1', 'Note 2', 'Note 3'});
    });

    test('count returns correct number of entities', () async {
      // Initially empty
      expect(await noteAdapter.count(), 0);

      // Add notes
      await noteAdapter.save(Note(title: 'Note 1'));
      await noteAdapter.save(Note(title: 'Note 2'));

      // Count
      expect(await noteAdapter.count(), 2);
    });
  });

  group('IndexedDB Indexes', () {
    late NoteIndexedDBAdapter noteAdapter;

    setUp(() {
      noteAdapter = NoteIndexedDBAdapter(db);
    });

    test('id index allows efficient findById', () async {
      // Create note
      final note = Note(title: 'Test Note');
      final saved = await noteAdapter.save(note);

      // findById should use index (not cursor scan)
      final found = await noteAdapter.findById(saved.id);
      expect(found, isNotNull);
      expect(found!.uuid, saved.uuid);
    });

    test('uuid index is unique', () async {
      // Create note with specific UUID
      final note1 = Note(title: 'Note 1');
      note1.uuid = 'test-uuid-123';
      await noteAdapter.save(note1);

      // Try to save another note with same UUID (should replace)
      final note2 = Note(title: 'Note 2');
      note2.uuid = 'test-uuid-123';
      await noteAdapter.save(note2);

      // Should only have one note with that UUID
      final found = await noteAdapter.findByUuid('test-uuid-123');
      expect(found!.title, 'Note 2'); // Latest wins
    });
  });

  group('HNSW Persistence', () {
    late NoteIndexedDBAdapter noteAdapter;

    setUp(() async {
      noteAdapter = NoteIndexedDBAdapter(db);
      await noteAdapter.initialize(); // Initialize HNSW index
    });

    tearDown(() async {
      await noteAdapter.close(); // Persist index
    });

    test('can save notes with embeddings and perform semantic search',
        () async {
      // Create notes with embeddings (384 dimensions)
      final embedding1 = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final embedding2 = List.generate(384, (i) => i % 2 == 0 ? 0.0 : 1.0);
      final embedding3 =
          List.generate(384, (i) => i % 3 == 0 ? 1.0 : 0.0); // Similar to 1

      final note1 = Note(title: 'Note 1', content: 'Content 1');
      note1.embedding = embedding1;

      final note2 = Note(title: 'Note 2', content: 'Content 2');
      note2.embedding = embedding2;

      final note3 = Note(title: 'Note 3', content: 'Content 3');
      note3.embedding = embedding3;

      // Save notes
      await noteAdapter.save(note1);
      await noteAdapter.save(note2);
      await noteAdapter.save(note3);

      // Perform semantic search with query similar to embedding1
      final queryVector = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final results = await noteAdapter.semanticSearch(queryVector, limit: 2);

      // Should return note1 first (exact match), then note3 (partial match)
      expect(results.length, greaterThan(0));
      expect(results.first.uuid, note1.uuid);
    });

    test('HNSW index persists across database close/reopen', () async {
      // Create and save notes with embeddings
      final embedding1 = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final embedding2 = List.generate(384, (i) => i % 2 == 0 ? 0.0 : 1.0);

      final note1 = Note(title: 'Persisted Note 1');
      note1.embedding = embedding1;

      final note2 = Note(title: 'Persisted Note 2');
      note2.embedding = embedding2;

      await noteAdapter.save(note1);
      await noteAdapter.save(note2);

      // Close database to trigger serialization
      await noteAdapter.close();
      await closeIndexedDatabase(db);

      // Reopen database
      db = await openIndexedDatabase(idbFactory: idbFactory);
      noteAdapter = NoteIndexedDBAdapter(db);
      await noteAdapter.initialize(); // Should deserialize index

      // Perform semantic search - should work without rebuild
      final queryVector = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final results = await noteAdapter.semanticSearch(queryVector, limit: 1);

      // Should find note1 without rebuilding index
      expect(results.length, greaterThan(0));
      expect(results.first.uuid, note1.uuid);
    });

    test('can rebuild HNSW index from embeddings', () async {
      // Create notes with embeddings
      final embedding1 = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final embedding2 = List.generate(384, (i) => i % 2 == 0 ? 0.0 : 1.0);

      final note1 = Note(title: 'Rebuild Note 1');
      note1.embedding = embedding1;

      final note2 = Note(title: 'Rebuild Note 2');
      note2.embedding = embedding2;

      await noteAdapter.save(note1);
      await noteAdapter.save(note2);

      // Manually rebuild index
      await noteAdapter.rebuildIndex();

      // Perform semantic search
      final queryVector = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final results = await noteAdapter.semanticSearch(queryVector, limit: 1);

      expect(results.length, greaterThan(0));
      expect(results.first.uuid, note1.uuid);
    });

    test('HNSW index updates on save and delete', () async {
      // Create note with embedding
      final embedding1 = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      final note1 = Note(title: 'Update Test Note');
      note1.embedding = embedding1;

      await noteAdapter.save(note1);

      // Verify in index
      final queryVector = List.generate(384, (i) => i % 2 == 0 ? 1.0 : 0.0);
      var results = await noteAdapter.semanticSearch(queryVector);
      expect(results.length, 1);
      expect(results.first.uuid, note1.uuid);

      // Delete note
      await noteAdapter.deleteByUuid(note1.uuid);

      // Index should be updated (empty results or no match)
      results = await noteAdapter.semanticSearch(queryVector);
      expect(results.where((n) => n.uuid == note1.uuid).isEmpty, isTrue,
          reason: 'Deleted note should not appear in search results');
    });

    test('semantic search returns empty list when no embeddings exist',
        () async {
      // Create note without embedding
      final note = Note(title: 'No Embedding Note');
      await noteAdapter.save(note);

      // Search should return empty (no embeddings to search)
      final queryVector = List.generate(384, (i) => 1.0);
      final results = await noteAdapter.semanticSearch(queryVector);

      expect(results, isEmpty);
    });
  });
}
