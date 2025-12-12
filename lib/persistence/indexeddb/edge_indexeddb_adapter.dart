/// # EdgeIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for Edge entities.
/// Handles CRUD operations for entity-to-entity connections on web platform.
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final adapter = EdgeIndexedDBAdapter(db);
/// final repo = EdgeRepository(adapter: adapter);
/// ```

import 'package:idb_shim/idb.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';
import '../../core/edge.dart';
import '../../core/persistence/edge_persistence_adapter.dart';

class EdgeIndexedDBAdapter extends BaseIndexedDBAdapter<Edge>
    implements EdgePersistenceAdapter {
  EdgeIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.edges;

  @override
  Edge fromJson(Map<String, dynamic> json) => Edge.fromJson(json);

  // ============ Edge-Specific Queries ============

  @override
  Future<List<Edge>> findBySource(String sourceUuid) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);
    final index = store.index(Indexes.edgesSourceUuid);

    final List<Edge> results = [];
    final cursor = index.openCursor(key: sourceUuid, autoAdvance: true);

    await for (final cursorWithValue in cursor) {
      final data = cursorWithValue.value as Map<String, dynamic>;
      results.add(fromJson(data));
    }

    return results;
  }

  @override
  Future<List<Edge>> findByTarget(String targetUuid) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);
    final index = store.index(Indexes.edgesTargetUuid);

    final List<Edge> results = [];
    final cursor = index.openCursor(key: targetUuid, autoAdvance: true);

    await for (final cursorWithValue in cursor) {
      final data = cursorWithValue.value as Map<String, dynamic>;
      results.add(fromJson(data));
    }

    return results;
  }

  @override
  Future<List<Edge>> findByType(String edgeType) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);
    final index = store.index(Indexes.edgesEdgeType);

    final List<Edge> results = [];
    final cursor = index.openCursor(key: edgeType, autoAdvance: true);

    await for (final cursorWithValue in cursor) {
      final data = cursorWithValue.value as Map<String, dynamic>;
      results.add(fromJson(data));
    }

    return results;
  }
}
