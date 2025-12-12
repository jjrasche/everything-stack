/// # EdgeRepository
///
/// ## What it does
/// Repository for Edge entities. Manages entity-to-entity connections with
/// persistence, uniqueness enforcement, and efficient traversal.
///
/// ## Usage
/// ```dart
/// final adapter = EdgeObjectBoxAdapter(store);
/// final repo = EdgeRepository(adapter: adapter);
///
/// // Connect entities
/// final edge = Edge(
///   sourceType: 'Note',
///   sourceUuid: 'note-1',
///   targetType: 'Project',
///   targetUuid: 'project-1',
///   edgeType: 'belongs_to',
/// );
/// await repo.save(edge);
///
/// // Query edges
/// final outgoing = await repo.findBySource('note-1');
/// final incoming = await repo.findByTarget('project-1');
/// final between = await repo.findBetween('note-1', 'project-1');
/// final byType = await repo.findByType('belongs_to');
///
/// // Traversal (1-3 hops)
/// final connected = await repo.traverse(
///   startUuid: 'note-1',
///   depth: 2,
///   direction: 'outgoing',
/// ); // Returns Map<uuid, depth>
///
/// // Delete
/// await repo.deleteEdge('note-1', 'project-1', 'belongs_to');
/// ```

import 'edge.dart';
import 'base_entity.dart' show SyncStatus;
import 'persistence/edge_persistence_adapter.dart';

/// Exception thrown when attempting to create a duplicate edge
class DuplicateEdgeException implements Exception {
  final String sourceUuid;
  final String targetUuid;
  final String edgeType;

  DuplicateEdgeException({
    required this.sourceUuid,
    required this.targetUuid,
    required this.edgeType,
  });

  @override
  String toString() =>
      'DuplicateEdgeException: Edge already exists: $sourceUuid -[$edgeType]-> $targetUuid';
}

class EdgeRepository {
  final EdgePersistenceAdapter _adapter;

  EdgeRepository({required EdgePersistenceAdapter adapter}) : _adapter = adapter;

  // ============ CRUD ============

  /// Save edge to database, enforcing uniqueness on (sourceUuid, targetUuid, edgeType)
  /// Throws DuplicateEdgeException if edge already exists.
  Future<int> save(Edge edge) async {
    // Check for existing edge with same composite key
    final existing = await findBetween(edge.sourceUuid, edge.targetUuid);
    if (existing.any((e) => e.edgeType == edge.edgeType && e.id != edge.id)) {
      throw DuplicateEdgeException(
        sourceUuid: edge.sourceUuid,
        targetUuid: edge.targetUuid,
        edgeType: edge.edgeType,
      );
    }

    // Set createdAt if not already set
    if (edge.createdAt.year == 1970) {
      edge.createdAt = DateTime.now();
    }

    // Save via adapter (adapter handles touch())
    final saved = await _adapter.save(edge);
    return saved.id;
  }

  /// Delete edge by composite key (sourceUuid, targetUuid, edgeType)
  /// Returns true if edge was deleted, false if it didn't exist.
  Future<bool> deleteEdge(
    String sourceUuid,
    String targetUuid,
    String edgeType,
  ) async {
    final edge = await _findEdge(sourceUuid, targetUuid, edgeType);
    if (edge == null) return false;

    return _adapter.delete(edge.id);
  }

  // ============ Queries ============

  /// Find all edges originating from sourceUuid (outgoing edges)
  Future<List<Edge>> findBySource(String sourceUuid) async {
    return _adapter.findBySource(sourceUuid);
  }

  /// Find all edges pointing to targetUuid (incoming edges)
  Future<List<Edge>> findByTarget(String targetUuid) async {
    return _adapter.findByTarget(targetUuid);
  }

  /// Find all edges between two entities (both directions)
  Future<List<Edge>> findBetween(String sourceUuid, String targetUuid) async {
    // Fetch by source and filter for target
    final edges = await findBySource(sourceUuid);
    return edges.where((e) => e.targetUuid == targetUuid).toList();
  }

  /// Find all edges of specific type
  Future<List<Edge>> findByType(String edgeType) async {
    return _adapter.findByType(edgeType);
  }

  // ============ Traversal ============

  /// Traverse entity graph up to depth (1-3 hops)
  /// Returns Map<uuid, depth> of reachable entities
  /// direction: 'incoming', 'outgoing', or 'both'
  Future<Map<String, int>> traverse({
    required String startUuid,
    required int depth,
    required String direction,
  }) async {
    if (depth < 1 || depth > 3) {
      throw ArgumentError('Depth must be between 1 and 3');
    }

    final visited = <String>{}; // Track visited nodes to avoid cycles
    final results = <String, int>{}; // uuid -> depth

    await _traverseImpl(
      currentUuid: startUuid,
      currentDepth: 0,
      maxDepth: depth,
      direction: direction,
      visited: visited,
      results: results,
    );

    // Remove the starting node if it ended up in results
    results.remove(startUuid);

    return results;
  }

  /// Recursive traversal implementation
  Future<void> _traverseImpl({
    required String currentUuid,
    required int currentDepth,
    required int maxDepth,
    required String direction,
    required Set<String> visited,
    required Map<String, int> results,
  }) async {
    // Stop if we've reached max depth
    if (currentDepth >= maxDepth) return;

    // Mark as visited to avoid cycles
    visited.add(currentUuid);

    // Handle 'both' direction by processing outgoing and incoming separately
    if (direction == 'both') {
      final outgoing = await findBySource(currentUuid);
      for (final edge in outgoing) {
        await _processEdge(
          edge: edge,
          nextUuid: edge.targetUuid,
          currentDepth: currentDepth,
          maxDepth: maxDepth,
          direction: direction,
          visited: visited,
          results: results,
        );
      }

      final incoming = await findByTarget(currentUuid);
      for (final edge in incoming) {
        await _processEdge(
          edge: edge,
          nextUuid: edge.sourceUuid,
          currentDepth: currentDepth,
          maxDepth: maxDepth,
          direction: direction,
          visited: visited,
          results: results,
        );
      }
    } else {
      // Get edges to traverse
      final edges = await _getEdgesForDirection(currentUuid, direction);

      // Process each edge
      for (final edge in edges) {
        final nextUuid =
            direction == 'incoming' ? edge.sourceUuid : edge.targetUuid;

        await _processEdge(
          edge: edge,
          nextUuid: nextUuid,
          currentDepth: currentDepth,
          maxDepth: maxDepth,
          direction: direction,
          visited: visited,
          results: results,
        );
      }
    }
  }

  /// Process a single edge during traversal
  Future<void> _processEdge({
    required Edge edge,
    required String nextUuid,
    required int currentDepth,
    required int maxDepth,
    required String direction,
    required Set<String> visited,
    required Map<String, int> results,
  }) async {
    // Skip if already visited (avoid cycles)
    if (visited.contains(nextUuid)) return;

    // Record this node
    final newDepth = currentDepth + 1;
    if (!results.containsKey(nextUuid) || results[nextUuid]! > newDepth) {
      results[nextUuid] = newDepth;
    }

    // Recurse
    await _traverseImpl(
      currentUuid: nextUuid,
      currentDepth: newDepth,
      maxDepth: maxDepth,
      direction: direction,
      visited: visited,
      results: results,
    );
  }

  /// Get edges to traverse based on direction
  Future<List<Edge>> _getEdgesForDirection(
    String uuid,
    String direction,
  ) async {
    switch (direction) {
      case 'outgoing':
        return findBySource(uuid);
      case 'incoming':
        return findByTarget(uuid);
      case 'both':
        final outgoing = await findBySource(uuid);
        final incoming = await findByTarget(uuid);
        return [...outgoing, ...incoming];
      default:
        throw ArgumentError('Invalid direction: $direction');
    }
  }

  // ============ Sync Methods ============

  /// Find edge by UUID using indexed field - O(1) lookup
  Future<Edge?> findByUuid(String uuid) async {
    return _adapter.findByUuid(uuid);
  }

  /// Find all unsynced edges (for sync service)
  Future<List<Edge>> findUnsynced() async {
    return _adapter.findUnsynced();
  }

  /// Mark edge as synced with remote ID
  Future<void> markSynced(String uuid, String syncId) async {
    final edge = await findByUuid(uuid);
    if (edge != null) {
      edge.syncId = syncId;
      edge.syncStatus = SyncStatus.synced;
      await _adapter.save(edge);
    }
  }

  // ============ Helpers ============

  /// Find edge by composite key
  Future<Edge?> _findEdge(
    String sourceUuid,
    String targetUuid,
    String edgeType,
  ) async {
    final edges = await findBetween(sourceUuid, targetUuid);
    try {
      return edges.firstWhere((e) => e.edgeType == edgeType);
    } catch (e) {
      return null;
    }
  }
}
