/// # HnswIndex
///
/// ## What it does
/// Pure Dart implementation of Hierarchical Navigable Small World (HNSW)
/// algorithm for approximate nearest neighbor search.
///
/// ## What it enables
/// - Fast semantic search across thousands of vectors
/// - O(log n) search complexity vs O(n) brute force
/// - Works on ALL platforms including web (no FFI required)
/// - Offline-capable vector search
///
/// ## Algorithm reference
/// Based on: "Efficient and robust approximate nearest neighbor search
/// using Hierarchical Navigable Small World graphs" (Malkov & Yashunin, 2016)
/// https://arxiv.org/abs/1603.09320
///
/// ## Usage
/// ```dart
/// final index = HnswIndex(dimensions: 384);
///
/// // Insert vectors
/// await index.insert(1, embedding1);
/// await index.insert(2, embedding2);
///
/// // Search for k nearest neighbors
/// final results = index.search(queryVector, k: 5);
/// // Returns [(id: 2, distance: 0.1), (id: 1, distance: 0.3), ...]
///
/// // Serialize for persistence
/// final bytes = index.toBytes();
/// final restored = HnswIndex.fromBytes(bytes);
/// ```
///
/// ## Parameters
/// - M: Max connections per node (default 16). Higher = better recall, more memory
/// - efConstruction: Build-time candidate pool (default 200). Higher = better quality, slower build
/// - efSearch: Query-time candidate pool (default 50). Higher = better recall, slower search
///
/// ## Performance characteristics
/// - Insert: O(log n) average
/// - Search: O(log n) average
/// - Memory: O(n * M) for connections + O(n * d) for vectors
/// - Suitable for up to ~100k vectors in pure Dart

import 'dart:math';
import 'dart:typed_data';

/// Result of a nearest neighbor search
class SearchResult {
  final int id;
  final double distance;

  SearchResult(this.id, this.distance);

  @override
  String toString() => 'SearchResult(id: $id, distance: ${distance.toStringAsFixed(4)})';
}

/// Distance metric for comparing vectors
enum DistanceMetric {
  /// Cosine distance: 1 - cosine_similarity. Range [0, 2], 0 = identical
  cosine,

  /// Euclidean (L2) distance. Range [0, inf), 0 = identical
  euclidean,
}

/// A node in the HNSW graph
class _HnswNode {
  final int id;
  final List<double> vector;
  final int maxLayer;

  /// Neighbors at each layer. Index 0 = bottom layer.
  final List<Set<int>> neighbors;

  _HnswNode({
    required this.id,
    required this.vector,
    required this.maxLayer,
  }) : neighbors = List.generate(maxLayer + 1, (_) => <int>{});
}

/// Priority queue entry for search
class _Candidate implements Comparable<_Candidate> {
  final int id;
  final double distance;

  _Candidate(this.id, this.distance);

  @override
  int compareTo(_Candidate other) => distance.compareTo(other.distance);
}

/// HNSW Index for approximate nearest neighbor search
class HnswIndex {
  /// Vector dimensions
  final int dimensions;

  /// Max connections per node (M parameter)
  final int maxConnections;

  /// Max connections at layer 0 (typically 2*M)
  final int maxConnections0;

  /// Candidate pool size during construction
  final int efConstruction;

  /// Default candidate pool size during search
  int efSearch;

  /// Distance metric to use
  final DistanceMetric metric;

  /// Level generation multiplier (1/ln(M))
  final double _levelMult;

  /// All nodes indexed by ID
  final Map<int, _HnswNode> _nodes = {};

  /// Entry point node ID (node at highest layer)
  int? _entryPointId;

  /// Current max layer in the index
  int _maxLevel = -1;

  /// Random number generator for level assignment
  final Random _random;

  /// Creates a new HNSW index
  ///
  /// [dimensions] - Vector size (must match all inserted vectors)
  /// [maxConnections] - M parameter, typically 16-64
  /// [efConstruction] - Build quality, typically 100-500
  /// [efSearch] - Search quality, typically 50-200
  /// [metric] - Distance function to use
  /// [seed] - Random seed for reproducible builds
  HnswIndex({
    required this.dimensions,
    this.maxConnections = 16,
    this.efConstruction = 200,
    this.efSearch = 50,
    this.metric = DistanceMetric.cosine,
    int? seed,
  })  : maxConnections0 = maxConnections * 2,
        _levelMult = 1.0 / log(maxConnections),
        _random = Random(seed);

  /// Number of vectors in the index
  int get size => _nodes.length;

  /// Whether the index is empty
  bool get isEmpty => _nodes.isEmpty;

  /// Insert a vector with the given ID
  ///
  /// [id] - Unique identifier for this vector
  /// [vector] - The vector to insert (must have [dimensions] elements)
  ///
  /// Throws [ArgumentError] if vector dimensions don't match
  void insert(int id, List<double> vector) {
    if (vector.length != dimensions) {
      throw ArgumentError(
        'Vector has ${vector.length} dimensions, expected $dimensions',
      );
    }

    // Don't allow duplicate IDs
    if (_nodes.containsKey(id)) {
      throw ArgumentError('ID $id already exists in index');
    }

    // Generate random level for this node
    final level = _randomLevel();

    // Create the node
    final node = _HnswNode(
      id: id,
      vector: List.unmodifiable(vector),
      maxLayer: level,
    );
    _nodes[id] = node;

    // If this is the first node, just set it as entry point
    if (_entryPointId == null) {
      _entryPointId = id;
      _maxLevel = level;
      return;
    }

    var currentNodeId = _entryPointId!;

    // Phase 1: Traverse from top to level+1, finding closest node
    // (greedy search with ef=1)
    for (var l = _maxLevel; l > level; l--) {
      final closest = _searchLayer(vector, currentNodeId, 1, l);
      if (closest.isNotEmpty) {
        currentNodeId = closest.first.id;
      }
    }

    // Phase 2: From min(level, maxLevel) down to 0, find efConstruction neighbors
    // and create bidirectional links
    for (var l = min(level, _maxLevel); l >= 0; l--) {
      final candidates = _searchLayer(vector, currentNodeId, efConstruction, l);

      // Select M best neighbors
      final maxConn = l == 0 ? maxConnections0 : maxConnections;
      final neighbors = _selectNeighbors(vector, candidates, maxConn);

      // Add bidirectional edges
      for (final neighbor in neighbors) {
        node.neighbors[l].add(neighbor.id);
        _nodes[neighbor.id]!.neighbors[l].add(id);

        // Prune neighbor's connections if exceeded
        _pruneConnections(_nodes[neighbor.id]!, l, maxConn);
      }

      if (candidates.isNotEmpty) {
        currentNodeId = candidates.first.id;
      }
    }

    // Update entry point if new node has higher level
    if (level > _maxLevel) {
      _maxLevel = level;
      _entryPointId = id;
    }
  }

  /// Search for k nearest neighbors to the query vector
  ///
  /// [query] - The query vector
  /// [k] - Number of neighbors to return
  /// [ef] - Search candidate pool size (defaults to [efSearch])
  ///
  /// Returns list of [SearchResult] sorted by distance (closest first)
  List<SearchResult> search(List<double> query, {int k = 10, int? ef}) {
    if (query.length != dimensions) {
      throw ArgumentError(
        'Query has ${query.length} dimensions, expected $dimensions',
      );
    }

    if (_entryPointId == null) {
      return [];
    }

    ef ??= efSearch;
    if (ef < k) ef = k;

    var currentNodeId = _entryPointId!;

    // Phase 1: Traverse from top to layer 1 with ef=1
    for (var l = _maxLevel; l > 0; l--) {
      final closest = _searchLayer(query, currentNodeId, 1, l);
      if (closest.isNotEmpty) {
        currentNodeId = closest.first.id;
      }
    }

    // Phase 2: Search layer 0 with full ef
    final candidates = _searchLayer(query, currentNodeId, ef, 0);

    // Return top k results
    return candidates
        .take(k)
        .map((c) => SearchResult(c.id, c.distance))
        .toList();
  }

  /// Delete a vector by ID
  ///
  /// Note: This marks the node as deleted but doesn't repair graph connections.
  /// For best results, rebuild the index periodically if many deletions occur.
  bool delete(int id) {
    final node = _nodes.remove(id);
    if (node == null) return false;

    // Remove all edges pointing to this node
    for (var l = 0; l <= node.maxLayer; l++) {
      for (final neighborId in node.neighbors[l]) {
        _nodes[neighborId]?.neighbors[l].remove(id);
      }
    }

    // If we deleted the entry point, find a new one
    if (_entryPointId == id) {
      _entryPointId = null;
      _maxLevel = -1;

      for (final n in _nodes.values) {
        if (n.maxLayer > _maxLevel) {
          _maxLevel = n.maxLayer;
          _entryPointId = n.id;
        }
      }
    }

    return true;
  }

  /// Check if a vector with the given ID exists
  bool contains(int id) => _nodes.containsKey(id);

  /// Get the vector for a given ID
  List<double>? getVector(int id) => _nodes[id]?.vector;

  /// Search a single layer using greedy algorithm
  ///
  /// Based on SEARCH-LAYER from HNSW paper.
  /// Returns candidates sorted by distance (closest first)
  List<_Candidate> _searchLayer(
    List<double> query,
    int entryId,
    int ef,
    int layer,
  ) {
    final visited = <int>{entryId};

    // Results: the ef closest nodes found (we track furthest for pruning)
    // Using a list and sorting is simpler than managing heap invariants
    final results = <_Candidate>[];

    // Candidates to explore: min-heap (explore closest first)
    final toExplore = <_Candidate>[];

    final entryNode = _nodes[entryId]!;
    final entryDist = _distance(query, entryNode.vector);
    final entryCandidate = _Candidate(entryId, entryDist);

    results.add(entryCandidate);
    toExplore.add(entryCandidate);

    while (toExplore.isNotEmpty) {
      // Get closest candidate to explore (min extraction)
      toExplore.sort((a, b) => a.distance.compareTo(b.distance));
      final current = toExplore.removeAt(0);

      // Get furthest in results
      results.sort((a, b) => a.distance.compareTo(b.distance));
      final furthestDist = results.last.distance;

      // If closest to explore is further than furthest result and we have ef results, stop
      if (current.distance > furthestDist && results.length >= ef) {
        break;
      }

      // Explore neighbors at this layer
      final currentNode = _nodes[current.id];
      if (currentNode == null) continue;

      // Check if node has neighbors at this layer
      if (layer > currentNode.maxLayer) continue;

      for (final neighborId in currentNode.neighbors[layer]) {
        if (visited.contains(neighborId)) continue;
        visited.add(neighborId);

        final neighborNode = _nodes[neighborId];
        if (neighborNode == null) continue;

        final dist = _distance(query, neighborNode.vector);

        // Get current furthest in results
        results.sort((a, b) => a.distance.compareTo(b.distance));
        final currentFurthest = results.isNotEmpty ? results.last.distance : double.infinity;

        // Add if closer than furthest, or we haven't filled ef yet
        if (dist < currentFurthest || results.length < ef) {
          final candidate = _Candidate(neighborId, dist);
          results.add(candidate);
          toExplore.add(candidate);

          // Prune results if exceeded ef
          if (results.length > ef) {
            results.sort((a, b) => a.distance.compareTo(b.distance));
            results.removeLast();
          }
        }
      }
    }

    results.sort((a, b) => a.distance.compareTo(b.distance));
    return results;
  }

  /// Select best neighbors using simple heuristic
  List<_Candidate> _selectNeighbors(
    List<double> query,
    List<_Candidate> candidates,
    int maxCount,
  ) {
    // Simple selection: just take the closest ones
    // More advanced: use heuristic that prefers diverse connections
    return candidates.take(maxCount).toList();
  }

  /// Prune connections if a node has too many
  void _pruneConnections(_HnswNode node, int layer, int maxCount) {
    if (node.neighbors[layer].length <= maxCount) return;

    // Calculate distances to all neighbors
    final scored = <_Candidate>[];
    for (final neighborId in node.neighbors[layer]) {
      final neighborNode = _nodes[neighborId];
      if (neighborNode != null) {
        final dist = _distance(node.vector, neighborNode.vector);
        scored.add(_Candidate(neighborId, dist));
      }
    }

    // Sort by distance and keep closest
    scored.sort((a, b) => a.distance.compareTo(b.distance));
    final keep = scored.take(maxCount).map((c) => c.id).toSet();

    // Remove edges to pruned neighbors
    final toRemove = node.neighbors[layer].difference(keep);
    for (final removedId in toRemove) {
      node.neighbors[layer].remove(removedId);
      // Also remove reverse edge
      _nodes[removedId]?.neighbors[layer].remove(node.id);
    }
  }

  /// Generate random level for a new node
  int _randomLevel() {
    // level = floor(-ln(uniform(0,1)) * mL)
    final r = _random.nextDouble();
    if (r == 0) return 0; // Avoid log(0)
    return (-log(r) * _levelMult).floor();
  }

  /// Calculate distance between two vectors
  double _distance(List<double> a, List<double> b) {
    switch (metric) {
      case DistanceMetric.cosine:
        return _cosineDistance(a, b);
      case DistanceMetric.euclidean:
        return _euclideanDistance(a, b);
    }
  }

  /// Cosine distance: 1 - cosine_similarity
  double _cosineDistance(List<double> a, List<double> b) {
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 1.0;

    final similarity = dot / (sqrt(normA) * sqrt(normB));
    return 1.0 - similarity;
  }

  /// Euclidean (L2) distance
  double _euclideanDistance(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  // ============ Serialization ============

  /// Serialize the index to bytes for persistence
  ///
  /// Format:
  /// - Header: dimensions(4), maxConnections(4), metric(1), nodeCount(4), maxLevel(4), entryPointId(4)
  /// - For each node: id(4), maxLayer(4), vector(dimensions*8), neighborCounts, neighborIds
  Uint8List toBytes() {
    // Calculate size
    var size = 4 + 4 + 1 + 4 + 4 + 4; // Header

    for (final node in _nodes.values) {
      size += 4 + 4; // id, maxLayer
      size += dimensions * 8; // vector (doubles)
      for (var l = 0; l <= node.maxLayer; l++) {
        size += 4; // neighbor count
        size += node.neighbors[l].length * 4; // neighbor ids
      }
    }

    final buffer = ByteData(size);
    var offset = 0;

    // Write header
    buffer.setInt32(offset, dimensions, Endian.little);
    offset += 4;
    buffer.setInt32(offset, maxConnections, Endian.little);
    offset += 4;
    buffer.setUint8(offset, metric.index);
    offset += 1;
    buffer.setInt32(offset, _nodes.length, Endian.little);
    offset += 4;
    buffer.setInt32(offset, _maxLevel, Endian.little);
    offset += 4;
    buffer.setInt32(offset, _entryPointId ?? -1, Endian.little);
    offset += 4;

    // Write nodes
    for (final node in _nodes.values) {
      buffer.setInt32(offset, node.id, Endian.little);
      offset += 4;
      buffer.setInt32(offset, node.maxLayer, Endian.little);
      offset += 4;

      // Write vector
      for (var i = 0; i < dimensions; i++) {
        buffer.setFloat64(offset, node.vector[i], Endian.little);
        offset += 8;
      }

      // Write neighbors for each layer
      for (var l = 0; l <= node.maxLayer; l++) {
        buffer.setInt32(offset, node.neighbors[l].length, Endian.little);
        offset += 4;
        for (final neighborId in node.neighbors[l]) {
          buffer.setInt32(offset, neighborId, Endian.little);
          offset += 4;
        }
      }
    }

    return buffer.buffer.asUint8List();
  }

  /// Deserialize an index from bytes
  ///
  /// [bytes] - Serialized index data from [toBytes]
  /// [efConstruction] - Build parameter (not stored, provide original value)
  /// [efSearch] - Search parameter (not stored, provide original value)
  static HnswIndex fromBytes(
    Uint8List bytes, {
    int efConstruction = 200,
    int efSearch = 50,
  }) {
    final buffer = ByteData.sublistView(bytes);
    var offset = 0;

    // Read header
    final dimensions = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final maxConnections = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final metricIndex = buffer.getUint8(offset);
    offset += 1;
    final nodeCount = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final maxLevel = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final entryPointId = buffer.getInt32(offset, Endian.little);
    offset += 4;

    final index = HnswIndex(
      dimensions: dimensions,
      maxConnections: maxConnections,
      efConstruction: efConstruction,
      efSearch: efSearch,
      metric: DistanceMetric.values[metricIndex],
    );

    index._maxLevel = maxLevel;
    index._entryPointId = entryPointId == -1 ? null : entryPointId;

    // Read nodes
    for (var i = 0; i < nodeCount; i++) {
      final id = buffer.getInt32(offset, Endian.little);
      offset += 4;
      final nodeMaxLayer = buffer.getInt32(offset, Endian.little);
      offset += 4;

      // Read vector
      final vector = List<double>.filled(dimensions, 0);
      for (var j = 0; j < dimensions; j++) {
        vector[j] = buffer.getFloat64(offset, Endian.little);
        offset += 8;
      }

      final node = _HnswNode(
        id: id,
        vector: List.unmodifiable(vector),
        maxLayer: nodeMaxLayer,
      );

      // Read neighbors for each layer
      for (var l = 0; l <= nodeMaxLayer; l++) {
        final neighborCount = buffer.getInt32(offset, Endian.little);
        offset += 4;
        for (var n = 0; n < neighborCount; n++) {
          final neighborId = buffer.getInt32(offset, Endian.little);
          offset += 4;
          node.neighbors[l].add(neighborId);
        }
      }

      index._nodes[id] = node;
    }

    return index;
  }

  /// Get statistics about the index
  Map<String, dynamic> getStats() {
    if (_nodes.isEmpty) {
      return {
        'size': 0,
        'dimensions': dimensions,
        'maxLevel': -1,
        'avgConnections': 0.0,
      };
    }

    var totalConnections = 0;
    final levelCounts = <int, int>{};

    for (final node in _nodes.values) {
      for (var l = 0; l <= node.maxLayer; l++) {
        totalConnections += node.neighbors[l].length;
        levelCounts[l] = (levelCounts[l] ?? 0) + 1;
      }
    }

    return {
      'size': _nodes.length,
      'dimensions': dimensions,
      'maxLevel': _maxLevel,
      'entryPointId': _entryPointId,
      'avgConnections': totalConnections / _nodes.length,
      'nodesPerLevel': levelCounts,
    };
  }
}
