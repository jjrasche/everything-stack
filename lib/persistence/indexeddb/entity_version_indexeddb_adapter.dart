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
import 'database_schema.dart';
import '../../core/entity_version.dart';
import '../../core/persistence/version_persistence_adapter.dart';

class EntityVersionIndexedDBAdapter extends BaseIndexedDBAdapter<EntityVersion>
    implements VersionPersistenceAdapter {
  EntityVersionIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.entityVersions;

  @override
  EntityVersion fromJson(Map<String, dynamic> json) =>
      EntityVersion.fromJson(json);

  /// EntityVersion is immutable - don't touch on save
  @override
  bool get shouldTouchOnSave => false;

  // ============ Version-Specific Queries ============

  @override
  Future<List<EntityVersion>> findByEntityUuid(String entityUuid) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);
    final index = store.index(Indexes.versionsEntityUuid);

    final List<EntityVersion> results = [];
    final cursor = index.openCursor(key: entityUuid, autoAdvance: true);

    await for (final cursorWithValue in cursor) {
      final data = cursorWithValue.value as Map<String, dynamic>;
      results.add(fromJson(data));
    }

    // Sort by version number ascending
    results.sort((a, b) => a.versionNumber.compareTo(b.versionNumber));
    return results;
  }

  @override
  Future<EntityVersion?> findLatestByEntityUuid(String entityUuid) async {
    final versions = await findByEntityUuid(entityUuid);
    if (versions.isEmpty) return null;
    // Return last version (highest version number)
    return versions.last;
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidBeforeTimestamp(
    String entityUuid,
    DateTime timestamp,
  ) async {
    final versions = await findByEntityUuid(entityUuid);
    // Filter to versions created before timestamp
    return versions
        .where((v) => v.createdAt.isBefore(timestamp))
        .toList();
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidBetween(
    String entityUuid,
    DateTime from,
    DateTime to,
  ) async {
    final versions = await findByEntityUuid(entityUuid);
    // Filter to versions within time range
    return versions
        .where((v) => v.createdAt.isAfter(from) && v.createdAt.isBefore(to))
        .toList();
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidUnsynced(String entityUuid) async {
    final versions = await findByEntityUuid(entityUuid);
    // Filter to unsynced versions (syncStatus == SyncStatus.local)
    return versions
        .where((v) => v.dbSyncStatus == 0) // 0 = SyncStatus.local.index
        .toList();
  }

  @override
  EntityVersion? findLatestByEntityUuidInTx(ctx, String entityUuid) {
    // IndexedDB doesn't support synchronous operations
    // This method is for ObjectBox transactions only
    throw UnsupportedError(
      'Synchronous transactions not supported in IndexedDB. Use async methods.',
    );
  }
}
