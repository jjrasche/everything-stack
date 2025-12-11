/// # EntityVersionObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for EntityVersion entities.
/// Handles CRUD operations for version tracking records.
///
/// ## Note on semantic search
/// EntityVersion records don't have embeddings, so semantic search methods
/// return empty results. This is expected behavior.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = EntityVersionObjectBoxAdapter(store);
/// final repo = VersionRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../core/entity_version.dart';
import '../../core/base_entity.dart';
import '../../objectbox.g.dart';

class EntityVersionObjectBoxAdapter
    implements PersistenceAdapter<EntityVersion> {
  final Store _store;
  late final Box<EntityVersion> _box;

  EntityVersionObjectBoxAdapter(this._store) {
    _box = _store.box<EntityVersion>();
  }

  // ============ CRUD ============

  @override
  Future<EntityVersion?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<EntityVersion?> findByUuid(String uuid) async {
    final query = _box.query(EntityVersion_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EntityVersion>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<EntityVersion> save(EntityVersion entity) async {
    // Versions are immutable - don't touch() them
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<EntityVersion>> saveAll(List<EntityVersion> entities) async {
    _box.putMany(entities);
    return entities;
  }

  @override
  Future<bool> delete(int id) async {
    return _box.remove(id);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) return false;
    return _box.remove(entity.id);
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    _box.removeMany(ids);
  }

  // ============ Queries ============

  @override
  Future<List<EntityVersion>> findUnsynced() async {
    final query = _box
        .query(EntityVersion_.dbSyncStatus.equals(SyncStatus.local.index))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  // ============ Version-specific queries ============
  // These are used by VersionRepository for version management

  /// Get all versions for an entity, ordered by version number.
  Future<List<EntityVersion>> findByEntityUuid(String entityUuid) async {
    final query = _box
        .query(EntityVersion_.entityUuid.equals(entityUuid))
        .order(EntityVersion_.versionNumber)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Get the latest version for an entity.
  Future<EntityVersion?> findLatestByEntityUuid(String entityUuid) async {
    final query = _box
        .query(EntityVersion_.entityUuid.equals(entityUuid))
        .order(EntityVersion_.versionNumber, flags: Order.descending)
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Find versions up to a specific timestamp.
  Future<List<EntityVersion>> findByEntityUuidBeforeTimestamp(
    String entityUuid,
    DateTime timestamp,
  ) async {
    final timestampMs =
        timestamp.add(const Duration(milliseconds: 1)).millisecondsSinceEpoch;
    final query = _box
        .query(EntityVersion_.entityUuid
            .equals(entityUuid)
            .and(EntityVersion_.createdAt.lessThan(timestampMs)))
        .order(EntityVersion_.versionNumber)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find versions in a time range.
  Future<List<EntityVersion>> findByEntityUuidBetween(
    String entityUuid,
    DateTime from,
    DateTime to,
  ) async {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final query = _box
        .query(EntityVersion_.entityUuid
            .equals(entityUuid)
            .and(EntityVersion_.createdAt.between(fromMs, toMs)))
        .order(EntityVersion_.versionNumber)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find unsynced versions for a specific entity.
  Future<List<EntityVersion>> findByEntityUuidUnsynced(
      String entityUuid) async {
    final query = _box
        .query(EntityVersion_.entityUuid
            .equals(entityUuid)
            .and(EntityVersion_.dbSyncStatus.equals(SyncStatus.local.index)))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Semantic Search ============
  // EntityVersion records don't have embeddings - these return empty/zero

  @override
  Future<List<EntityVersion>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Version records don't have embeddings - semantic search not applicable
    return [];
  }

  @override
  int get indexSize => 0; // No embeddings on EntityVersion

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(EntityVersion entity) generateEmbedding,
  ) async {
    // No-op for EntityVersion - no embeddings to rebuild
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle is managed externally
  }
}
