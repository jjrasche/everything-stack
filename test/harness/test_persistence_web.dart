/// Web test persistence implementation.
/// Uses in-memory IndexedDB for testing.
library;

import 'package:idb_shim/idb_client_memory.dart';
import 'package:everything_stack_template/bootstrap/persistence_factory.dart';
import 'package:everything_stack_template/persistence/indexeddb/database_init.dart';
import 'package:everything_stack_template/persistence/indexeddb/media_item_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/channel_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/edge_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/entity_version_indexeddb_adapter.dart';
import 'package:everything_stack_template/persistence/indexeddb/invocation_indexeddb_adapter.dart';

var _idbFactory = newIdbFactoryMemory();
dynamic _db; // Database type

/// Platform detection - returns true for web
bool detectWebPlatform() => true;

/// Initialize IndexedDB test persistence in-memory.
Future<PersistenceFactory> initializeTestPersistence() async {
  // Use in-memory IndexedDB for testing
  _idbFactory = newIdbFactoryMemory();

  // Open IndexedDB database
  _db = await openIndexedDatabase(idbFactory: _idbFactory);

  // Create adapters
  final mediaItemAdapter = MediaItemIndexedDBAdapter(_db);
  final channelAdapter = ChannelIndexedDBAdapter(_db);
  final edgeAdapter = EdgeIndexedDBAdapter(_db);
  final versionAdapter = EntityVersionIndexedDBAdapter(_db);
  final invocationAdapter = InvocationIndexedDBAdapter(_db);

  // Initialize HNSW indexes
  await mediaItemAdapter.initialize();

  return PersistenceFactory(
    noteAdapter: null,
    mediaItemAdapter: mediaItemAdapter,
    channelAdapter: channelAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    invocationAdapter: invocationAdapter,
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
