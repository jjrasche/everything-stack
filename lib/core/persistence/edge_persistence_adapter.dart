/// Specialized persistence adapter interface for Edge entities.
/// Adds edge-specific query methods on top of base PersistenceAdapter.

import 'persistence_adapter.dart';
import '../edge.dart';

/// Persistence adapter interface for Edge entities.
///
/// Adds edge-specific query methods on top of base CRUD operations.
abstract class EdgePersistenceAdapter implements PersistenceAdapter<Edge> {
  /// Find all edges originating from sourceUuid (outgoing edges)
  Future<List<Edge>> findBySource(String sourceUuid);

  /// Find all edges pointing to targetUuid (incoming edges)
  Future<List<Edge>> findByTarget(String targetUuid);

  /// Find all edges of specific type
  Future<List<Edge>> findByType(String edgeType);
}
