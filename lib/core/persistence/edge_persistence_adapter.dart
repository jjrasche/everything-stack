/// # EdgePersistenceAdapter
///
/// ## What it does
/// Specialized persistence adapter interface for Edge entities.
/// Extends base PersistenceAdapter with edge-specific query methods.
///
/// ## What it enables
/// - EdgeRepository can depend on interface, not concrete ObjectBox type
/// - Same EdgeRepository works with ObjectBox and IndexedDB adapters
/// - Edge-specific queries (by source, target, type) abstracted from implementation
///
/// ## Usage
/// ```dart
/// // ObjectBox implementation
/// final adapter = EdgeObjectBoxAdapter(store);
/// final repo = EdgeRepository(adapter: adapter);
///
/// // Future: IndexedDB implementation
/// final adapter = EdgeIndexedDBAdapter(database);
/// final repo = EdgeRepository(adapter: adapter);
/// ```

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
