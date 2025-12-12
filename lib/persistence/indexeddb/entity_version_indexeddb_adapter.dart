/// # EntityVersionIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for EntityVersion entities.
/// Handles CRUD operations for version history on web platform.
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final adapter = EntityVersionIndexedDBAdapter(db);
/// final repo = VersionRepository(adapter: adapter);
/// ```

import 'package:idb_shim/idb.dart';
import 'base_indexeddb_adapter.dart';
import '../../core/entity_version.dart';

class EntityVersionIndexedDBAdapter extends BaseIndexedDBAdapter<EntityVersion> {
  EntityVersionIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => 'entity_versions';

  @override
  EntityVersion fromJson(Map<String, dynamic> json) =>
      EntityVersion.fromJson(json);

  /// EntityVersion is immutable - don't touch on save
  @override
  bool get shouldTouchOnSave => false;
}
