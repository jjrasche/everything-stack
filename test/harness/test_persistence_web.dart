/// Web test persistence implementation.
/// Uses in-memory IndexedDB for testing.
library;

import 'package:idb_shim/idb_client_memory.dart';
import 'package:everything_stack_template/bootstrap/persistence_factory.dart';
import 'package:everything_stack_template/persistence/indexeddb/database_init.dart';
import 'package:everything_stack_template/persistence/indexeddb/note_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/edge_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/entity_version_indexeddb_adapter.dart';

var _idbFactory = newIdbFactoryMemory();
dynamic _db; // Database type

/// Initialize IndexedDB test persistence in-memory.
Future<PersistenceFactory> initTestPersistence() async {
  // Use in-memory IndexedDB for testing
  _idbFactory = newIdbFactoryMemory();

  // Open IndexedDB database
  _db = await openIndexedDatabase(idbFactory: _idbFactory);

  // Create adapters
  final noteAdapter = NoteIndexedDBAdapter(_db);
  final edgeAdapter = EdgeIndexedDBAdapter(_db);
  final versionAdapter = EntityVersionIndexedDBAdapter(_db);

  // Initialize HNSW index
  await noteAdapter.initialize();

  return PersistenceFactory(
    noteAdapter: noteAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    handle: _db,
  );
}

/// Cleanup test persistence (close and delete database).
Future<void> cleanupTestPersistence() async {
  if (_db != null) {
    await closeIndexedDatabase(_db);
    _db = null;
  }

  // Delete database
  await deleteIndexedDatabase(idbFactory: _idbFactory);
}
