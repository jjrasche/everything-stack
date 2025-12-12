/// Web implementation of PersistenceFactory.
/// Uses IndexedDB with persisted HNSW semantic search.
library;

import 'persistence_factory.dart';
import '../persistence/indexeddb/database_init.dart';
import '../persistence/indexeddb/note_indexeddb_adapter.dart';
import '../persistence/indexeddb/edge_indexeddb_adapter.dart';
import '../persistence/indexeddb/entity_version_indexeddb_adapter.dart';

/// Initialize IndexedDB persistence layer for web platform.
///
/// Opens IndexedDB database and creates adapters for all entity types.
/// Loads persisted HNSW index for semantic search.
Future<PersistenceFactory> initializePersistence() async {
  // Open IndexedDB database
  final db = await openIndexedDatabase();

  // Create adapters
  final noteAdapter = NoteIndexedDBAdapter(db);
  final edgeAdapter = EdgeIndexedDBAdapter(db);
  final versionAdapter = EntityVersionIndexedDBAdapter(db);

  // Initialize HNSW index from IndexedDB storage
  await noteAdapter.initialize();

  return PersistenceFactory(
    noteAdapter: noteAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    handle: db,
  );
}
