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
import '../../core/edge.dart';

class EdgeIndexedDBAdapter extends BaseIndexedDBAdapter<Edge> {
  EdgeIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => 'edges';

  @override
  Edge fromJson(Map<String, dynamic> json) => Edge.fromJson(json);
}
