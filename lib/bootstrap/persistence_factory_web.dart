/// Web implementation of PersistenceFactory.
/// Uses IndexedDB with persisted HNSW semantic search.
library;

import 'persistence_factory.dart';
import '../persistence/indexeddb/database_init.dart';
import '../persistence/indexeddb/media_item_indexeddb_adapter.dart';
import '../persistence/indexeddb/channel_indexeddb_adapter.dart';
import '../persistence/indexeddb/edge_indexeddb_adapter.dart';
import '../persistence/indexeddb/entity_version_indexeddb_adapter.dart';
import '../persistence/indexeddb/invocation_indexeddb_adapter.dart';

/// Initialize IndexedDB persistence layer for web platform.
///
/// Opens IndexedDB database and creates adapters for all entity types.
/// Loads persisted HNSW index for semantic search.
Future<PersistenceFactory> initializePersistence() async {
  // Open IndexedDB database
  final db = await openIndexedDatabase();

  // Create adapters
  final mediaItemAdapter = MediaItemIndexedDBAdapter(db);
  final channelAdapter = ChannelIndexedDBAdapter(db);
  final edgeAdapter = EdgeIndexedDBAdapter(db);
  final versionAdapter = EntityVersionIndexedDBAdapter(db);
  final invocationAdapter = InvocationIndexedDBAdapter(db);

  // Initialize HNSW indexes from IndexedDB storage
  await mediaItemAdapter.initialize();

  return PersistenceFactory(
    noteAdapter: null, // Notes removed - use media search on web
    mediaItemAdapter: mediaItemAdapter,
    channelAdapter: channelAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    invocationAdapter: invocationAdapter,
    handle: db,
  );
}
