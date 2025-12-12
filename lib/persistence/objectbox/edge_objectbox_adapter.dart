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
import 'base_objectbox_adapter.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/edge_persistence_adapter.dart';
import '../../core/edge.dart';
import '../../objectbox.g.dart';

class EdgeObjectBoxAdapter extends BaseObjectBoxAdapter<Edge>
    implements EdgePersistenceAdapter {
  EdgeObjectBoxAdapter(Store store) : super(store);

  // ============ Entity-Specific Query Conditions ============

  @override
  Condition<Edge> uuidEqualsCondition(String uuid) => Edge_.uuid.equals(uuid);

  @override
  Condition<Edge> syncStatusLocalCondition() =>
      Edge_.dbSyncStatus.equals(SyncStatus.local.index);

  // ============ Edge-specific queries ============
  // These are used by EdgeRepository for graph traversal

  @override
  Future<List<Edge>> findBySource(String sourceUuid) async {
    final query = box.query(Edge_.sourceUuid.equals(sourceUuid)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Edge>> findByTarget(String targetUuid) async {
    final query = box.query(Edge_.targetUuid.equals(targetUuid)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Edge>> findByType(String edgeType) async {
    final query = box.query(Edge_.edgeType.equals(edgeType)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}
