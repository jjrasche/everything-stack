/// # EdgeObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Edge entities.
/// Handles CRUD operations for entity-to-entity connections.
///
/// ## Note on semantic search
/// Edge entities don't have embeddings, so semantic search methods
/// return empty results. This is expected behavior.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = EdgeObjectBoxAdapter(store);
/// final repo = EdgeRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../core/edge.dart';
import '../../core/base_entity.dart';
import '../../objectbox.g.dart';

class EdgeObjectBoxAdapter implements PersistenceAdapter<Edge> {
  final Store _store;
  late final Box<Edge> _box;

  EdgeObjectBoxAdapter(this._store) {
    _box = _store.box<Edge>();
  }

  // ============ CRUD ============

  @override
  Future<Edge?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<Edge?> findByUuid(String uuid) async {
    final query = _box.query(Edge_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Edge>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Edge> save(Edge entity) async {
    entity.touch();
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Edge>> saveAll(List<Edge> entities) async {
    for (final entity in entities) {
      entity.touch();
    }
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
  Future<List<Edge>> findUnsynced() async {
    final query = _box
        .query(Edge_.dbSyncStatus.equals(SyncStatus.local.index))
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

  // ============ Edge-specific queries ============
  // These are used by EdgeRepository for graph traversal

  /// Find all edges originating from sourceUuid (outgoing edges)
  Future<List<Edge>> findBySource(String sourceUuid) async {
    final query = _box.query(Edge_.sourceUuid.equals(sourceUuid)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find all edges pointing to targetUuid (incoming edges)
  Future<List<Edge>> findByTarget(String targetUuid) async {
    final query = _box.query(Edge_.targetUuid.equals(targetUuid)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find all edges of specific type
  Future<List<Edge>> findByType(String edgeType) async {
    final query = _box.query(Edge_.edgeType.equals(edgeType)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Semantic Search ============
  // Edge entities don't have embeddings - these return empty/zero

  @override
  Future<List<Edge>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Edges don't have embeddings - semantic search not applicable
    return [];
  }

  @override
  int get indexSize => 0; // No embeddings on Edge

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Edge entity) generateEmbedding,
  ) async {
    // No-op for Edge - no embeddings to rebuild
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle is managed externally
  }
}
