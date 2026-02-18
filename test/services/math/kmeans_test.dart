import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/math/kmeans.dart';

void main() {
  group('clusterVectors', () {
    test('returns empty result for empty input', () {
      final result = clusterVectors(vectors: [], k: 3);

      expect(result.assignments, isEmpty);
      expect(result.centroids, isEmpty);
      expect(result.distances, isEmpty);
    });

    test('assigns each vector to exactly one cluster', () {
      final vectors = [
        [1.0, 0.0, 0.0],
        [0.9, 0.1, 0.0],
        [0.0, 1.0, 0.0],
        [0.1, 0.9, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.1, 0.9],
      ];

      final result = clusterVectors(vectors: vectors, k: 3, seed: 42);

      expect(result.assignments.length, vectors.length);
      expect(result.centroids.length, 3);
      expect(result.distances.length, vectors.length);

      for (final cluster in result.assignments) {
        expect(cluster, inInclusiveRange(0, 2));
      }
    });

    test('groups similar vectors into same cluster', () {
      // Three well-separated clusters along each axis
      final vectors = [
        [1.0, 0.0, 0.0],
        [0.95, 0.05, 0.0],
        [0.0, 1.0, 0.0],
        [0.05, 0.95, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.05, 0.95],
      ];

      final result = clusterVectors(vectors: vectors, k: 3, seed: 42);

      // Vectors 0,1 should share a cluster
      expect(result.assignments[0], result.assignments[1]);
      // Vectors 2,3 should share a cluster
      expect(result.assignments[2], result.assignments[3]);
      // Vectors 4,5 should share a cluster
      expect(result.assignments[4], result.assignments[5]);
      // The three clusters should be distinct
      expect(result.assignments[0], isNot(result.assignments[2]));
      expect(result.assignments[0], isNot(result.assignments[4]));
      expect(result.assignments[2], isNot(result.assignments[4]));
    });

    test('produces distances that are non-negative', () {
      final vectors = [
        [1.0, 0.0],
        [0.0, 1.0],
        [0.7, 0.7],
      ];

      final result = clusterVectors(vectors: vectors, k: 2, seed: 42);

      for (final distance in result.distances) {
        expect(distance, greaterThanOrEqualTo(0.0));
      }
    });

    test('clamps k to vector count when k exceeds vector count', () {
      final vectors = [
        [1.0, 0.0],
        [0.0, 1.0],
      ];

      final result = clusterVectors(vectors: vectors, k: 10, seed: 42);

      expect(result.assignments.length, 2);
      // Should not crash, k clamped to 2
      expect(result.centroids.length, 2);
    });

    test('throws on non-positive k', () {
      expect(
        () => clusterVectors(vectors: [[1.0]], k: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('converges deterministically with seed', () {
      final vectors = [
        [1.0, 0.0, 0.0],
        [0.8, 0.2, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.8, 0.2],
      ];

      final resultA = clusterVectors(vectors: vectors, k: 2, seed: 99);
      final resultB = clusterVectors(vectors: vectors, k: 2, seed: 99);

      expect(resultA.assignments, resultB.assignments);
    });
  });
}
