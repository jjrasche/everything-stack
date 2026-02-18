import 'dart:math' as math;

/// Result of k-means clustering.
class KMeansResult {
  /// Cluster index assigned to each input vector (same order as input).
  final List<int> assignments;

  /// Centroid vectors, one per cluster.
  final List<List<double>> centroids;

  /// Distance from each vector to its assigned centroid.
  final List<double> distances;

  KMeansResult({
    required this.assignments,
    required this.centroids,
    required this.distances,
  });
}

/// Cluster [vectors] into [k] groups using Lloyd's algorithm.
///
/// Returns cluster assignments, centroids, and per-vector distances.
/// Uses cosine distance (1 - cosineSimilarity) for high-dimensional
/// embedding vectors where angular separation matters more than magnitude.
KMeansResult clusterVectors({
  required List<List<double>> vectors,
  required int k,
  int maxIterations = 100,
  int? seed,
}) {
  if (vectors.isEmpty) {
    return KMeansResult(assignments: [], centroids: [], distances: []);
  }
  if (k <= 0) throw ArgumentError('k must be positive');
  if (k > vectors.length) k = vectors.length;

  final dimension = vectors.first.length;
  final random = math.Random(seed);

  var centroids = _initializeCentroids(vectors, k, random);
  var assignments = List.filled(vectors.length, 0);

  for (var iteration = 0; iteration < maxIterations; iteration++) {
    final newAssignments = _assignToClusters(vectors, centroids);

    final isConverged = _assignmentsMatch(assignments, newAssignments);
    assignments = newAssignments;

    if (isConverged && iteration > 0) break;

    centroids = _recomputeCentroids(vectors, assignments, k, dimension);
  }

  final distances = _computeDistances(vectors, centroids, assignments);

  return KMeansResult(
    assignments: assignments,
    centroids: centroids,
    distances: distances,
  );
}

/// Pick k initial centroids using k-means++ for better convergence.
List<List<double>> _initializeCentroids(
  List<List<double>> vectors,
  int k,
  math.Random random,
) {
  final centroids = <List<double>>[List.of(vectors[random.nextInt(vectors.length)])];

  for (var i = 1; i < k; i++) {
    final weights = _computeSelectionWeights(vectors, centroids);
    final selected = _weightedRandomSelect(weights, random);
    centroids.add(List.of(vectors[selected]));
  }

  return centroids;
}

/// Weight each vector by squared distance to nearest existing centroid.
/// Farther points are more likely to be picked as the next centroid.
List<double> _computeSelectionWeights(
  List<List<double>> vectors,
  List<List<double>> centroids,
) {
  return vectors.map((vector) {
    var minDistance = double.infinity;
    for (final centroid in centroids) {
      final distance = _cosineDistance(vector, centroid);
      if (distance < minDistance) minDistance = distance;
    }
    return minDistance * minDistance;
  }).toList();
}

/// Select an index with probability proportional to [weights].
int _weightedRandomSelect(List<double> weights, math.Random random) {
  final totalWeight = weights.fold<double>(0, (sum, w) => sum + w);
  if (totalWeight == 0) return random.nextInt(weights.length);

  var threshold = random.nextDouble() * totalWeight;
  for (var i = 0; i < weights.length; i++) {
    threshold -= weights[i];
    if (threshold <= 0) return i;
  }
  return weights.length - 1;
}

/// Assign each vector to its nearest centroid.
List<int> _assignToClusters(
  List<List<double>> vectors,
  List<List<double>> centroids,
) {
  return vectors.map((vector) {
    var nearestCluster = 0;
    var nearestDistance = double.infinity;
    for (var c = 0; c < centroids.length; c++) {
      final distance = _cosineDistance(vector, centroids[c]);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestCluster = c;
      }
    }
    return nearestCluster;
  }).toList();
}

/// Average vectors in each cluster to produce new centroids.
List<List<double>> _recomputeCentroids(
  List<List<double>> vectors,
  List<int> assignments,
  int k,
  int dimension,
) {
  final sums = List.generate(k, (_) => List.filled(dimension, 0.0));
  final counts = List.filled(k, 0);

  for (var i = 0; i < vectors.length; i++) {
    final cluster = assignments[i];
    counts[cluster]++;
    for (var d = 0; d < dimension; d++) {
      sums[cluster][d] += vectors[i][d];
    }
  }

  return List.generate(k, (c) {
    if (counts[c] == 0) return List.filled(dimension, 0.0);
    return List.generate(dimension, (d) => sums[c][d] / counts[c]);
  });
}

bool _assignmentsMatch(List<int> previous, List<int> current) {
  for (var i = 0; i < previous.length; i++) {
    if (previous[i] != current[i]) return false;
  }
  return true;
}

List<double> _computeDistances(
  List<List<double>> vectors,
  List<List<double>> centroids,
  List<int> assignments,
) {
  return List.generate(vectors.length, (i) {
    return _cosineDistance(vectors[i], centroids[assignments[i]]);
  });
}

/// Cosine distance = 1 - cosineSimilarity. Range [0, 2].
double _cosineDistance(List<double> vectorA, List<double> vectorB) {
  double dotProduct = 0;
  double normSquaredA = 0;
  double normSquaredB = 0;

  for (var i = 0; i < vectorA.length; i++) {
    dotProduct += vectorA[i] * vectorB[i];
    normSquaredA += vectorA[i] * vectorA[i];
    normSquaredB += vectorB[i] * vectorB[i];
  }

  if (normSquaredA == 0 || normSquaredB == 0) return 1.0;

  final similarity =
      dotProduct / (math.sqrt(normSquaredA) * math.sqrt(normSquaredB));
  return 1.0 - similarity;
}
