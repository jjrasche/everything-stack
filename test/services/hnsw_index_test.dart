/// # HNSW Index Tests
///
/// Tests for the pure Dart HNSW implementation.
/// Verifies correctness of insert, search, delete, and serialization.
/// Uses String UUIDs as keys for cross-type entity identification.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';

void main() {
  group('HnswIndex', () {
    // ============ Construction ============

    test('creates empty index with correct parameters', () {
      final index = HnswIndex(dimensions: 128);

      expect(index.dimensions, 128);
      expect(index.size, 0);
      expect(index.isEmpty, true);
    });

    test('creates index with custom parameters', () {
      final index = HnswIndex(
        dimensions: 384,
        maxConnections: 32,
        efConstruction: 100,
        efSearch: 25,
        metric: DistanceMetric.euclidean,
      );

      expect(index.dimensions, 384);
      expect(index.maxConnections, 32);
      expect(index.efConstruction, 100);
      expect(index.efSearch, 25);
      expect(index.metric, DistanceMetric.euclidean);
    });

    // ============ Insert ============

    test('inserts single vector', () {
      final index = HnswIndex(dimensions: 3, seed: 42);
      final vector = [1.0, 2.0, 3.0];

      index.insert('uuid-1', vector);

      expect(index.size, 1);
      expect(index.isEmpty, false);
      expect(index.contains('uuid-1'), true);
      expect(index.getVector('uuid-1'), vector);
    });

    test('inserts multiple vectors', () {
      final index = HnswIndex(dimensions: 3, seed: 42);

      index.insert('uuid-1', [1.0, 0.0, 0.0]);
      index.insert('uuid-2', [0.0, 1.0, 0.0]);
      index.insert('uuid-3', [0.0, 0.0, 1.0]);

      expect(index.size, 3);
      expect(index.contains('uuid-1'), true);
      expect(index.contains('uuid-2'), true);
      expect(index.contains('uuid-3'), true);
    });

    test('throws on wrong dimensions', () {
      final index = HnswIndex(dimensions: 3);

      expect(
        () => index.insert('uuid-1', [1.0, 2.0]),
        throwsArgumentError,
      );
    });

    test('throws on duplicate ID', () {
      final index = HnswIndex(dimensions: 3);
      index.insert('uuid-1', [1.0, 2.0, 3.0]);

      expect(
        () => index.insert('uuid-1', [4.0, 5.0, 6.0]),
        throwsArgumentError,
      );
    });

    // ============ Search ============

    test('returns empty list when searching empty index', () {
      final index = HnswIndex(dimensions: 3);
      final results = index.search([1.0, 2.0, 3.0], k: 5);

      expect(results, isEmpty);
    });

    test('finds exact match', () {
      final index = HnswIndex(dimensions: 3, seed: 42);
      final vector = [1.0, 2.0, 3.0];
      index.insert('uuid-1', vector);

      final results = index.search(vector, k: 1);

      expect(results.length, 1);
      expect(results[0].id, 'uuid-1');
      expect(results[0].distance, closeTo(0.0, 0.0001));
    });

    test('finds nearest neighbors in correct order', () {
      final index = HnswIndex(
        dimensions: 2,
        metric: DistanceMetric.euclidean,
        seed: 42,
      );

      // Create points at known distances from origin
      index.insert('id-1', [1.0, 0.0]); // distance 1
      index.insert('id-2', [2.0, 0.0]); // distance 2
      index.insert('id-3', [3.0, 0.0]); // distance 3
      index.insert('id-4', [0.5, 0.0]); // distance 0.5

      final results = index.search([0.0, 0.0], k: 4);

      expect(results.length, 4);
      expect(results[0].id, 'id-4'); // closest
      expect(results[1].id, 'id-1');
      expect(results[2].id, 'id-2');
      expect(results[3].id, 'id-3'); // furthest
    });

    test('returns only k results when more exist', () {
      final index = HnswIndex(dimensions: 2, seed: 42);

      for (var i = 0; i < 100; i++) {
        index.insert('id-$i', [i.toDouble(), 0.0]);
      }

      final results = index.search([50.0, 0.0], k: 5);

      expect(results.length, 5);
    });

    test('throws on wrong query dimensions', () {
      final index = HnswIndex(dimensions: 3);
      index.insert('uuid-1', [1.0, 2.0, 3.0]);

      expect(
        () => index.search([1.0, 2.0], k: 1),
        throwsArgumentError,
      );
    });

    // ============ Cosine Similarity ============

    test('cosine distance is 0 for identical normalized vectors', () {
      final index = HnswIndex(
        dimensions: 3,
        metric: DistanceMetric.cosine,
        seed: 42,
      );

      // Normalized vector
      final v = [1 / sqrt(3), 1 / sqrt(3), 1 / sqrt(3)];
      index.insert('uuid-1', v);

      final results = index.search(v, k: 1);

      expect(results[0].distance, closeTo(0.0, 0.0001));
    });

    test('cosine distance is 2 for opposite vectors', () {
      final index = HnswIndex(
        dimensions: 3,
        metric: DistanceMetric.cosine,
        seed: 42,
      );

      index.insert('uuid-1', [1.0, 0.0, 0.0]);

      final results = index.search([-1.0, 0.0, 0.0], k: 1);

      expect(results[0].distance, closeTo(2.0, 0.0001));
    });

    test('cosine finds semantically similar vectors', () {
      final index = HnswIndex(
        dimensions: 3,
        metric: DistanceMetric.cosine,
        seed: 42,
      );

      // Similar direction, different magnitudes
      index.insert('id-1', [1.0, 1.0, 0.0]);
      index.insert('id-2', [2.0, 2.0, 0.0]); // Same direction as 1
      index.insert('id-3', [-1.0, -1.0, 0.0]); // Opposite to 1

      final results = index.search([1.0, 1.0, 0.0], k: 3);

      // Both 1 and 2 should have distance ~0 (same direction)
      expect(results[0].distance, closeTo(0.0, 0.0001));
      expect(results[1].distance, closeTo(0.0, 0.0001));
      // 3 should have distance ~2 (opposite)
      expect(results[2].distance, closeTo(2.0, 0.0001));
    });

    // ============ Delete ============

    test('deletes existing vector', () {
      final index = HnswIndex(dimensions: 3, seed: 42);
      index.insert('uuid-1', [1.0, 2.0, 3.0]);

      final deleted = index.delete('uuid-1');

      expect(deleted, true);
      expect(index.size, 0);
      expect(index.contains('uuid-1'), false);
    });

    test('returns false when deleting non-existent vector', () {
      final index = HnswIndex(dimensions: 3);

      final deleted = index.delete('non-existent-uuid');

      expect(deleted, false);
    });

    test('search works after deletion', () {
      final index = HnswIndex(
        dimensions: 2,
        metric: DistanceMetric.euclidean,
        seed: 42,
      );

      index.insert('id-1', [1.0, 0.0]);
      index.insert('id-2', [2.0, 0.0]);
      index.insert('id-3', [3.0, 0.0]);

      index.delete('id-2');

      final results = index.search([0.0, 0.0], k: 3);

      expect(results.length, 2);
      expect(results.map((r) => r.id), isNot(contains('id-2')));
    });

    // ============ Serialization ============

    test('serializes and deserializes empty index', () {
      final index = HnswIndex(dimensions: 128);

      final bytes = index.toBytes();
      final restored = HnswIndex.fromBytes(bytes);

      expect(restored.dimensions, 128);
      expect(restored.size, 0);
    });

    test('serializes and deserializes index with data', () {
      final index = HnswIndex(
        dimensions: 3,
        maxConnections: 8,
        metric: DistanceMetric.euclidean,
        seed: 42,
      );

      index.insert('uuid-1', [1.0, 2.0, 3.0]);
      index.insert('uuid-2', [4.0, 5.0, 6.0]);
      index.insert('uuid-3', [7.0, 8.0, 9.0]);

      final bytes = index.toBytes();
      final restored = HnswIndex.fromBytes(bytes);

      expect(restored.dimensions, 3);
      expect(restored.maxConnections, 8);
      expect(restored.metric, DistanceMetric.euclidean);
      expect(restored.size, 3);
      expect(restored.contains('uuid-1'), true);
      expect(restored.contains('uuid-2'), true);
      expect(restored.contains('uuid-3'), true);
      expect(restored.getVector('uuid-1'), [1.0, 2.0, 3.0]);
    });

    test('search works on deserialized index', () {
      final index = HnswIndex(
        dimensions: 2,
        metric: DistanceMetric.euclidean,
        seed: 42,
      );

      index.insert('id-1', [1.0, 0.0]);
      index.insert('id-2', [2.0, 0.0]);
      index.insert('id-3', [3.0, 0.0]);

      final bytes = index.toBytes();
      final restored = HnswIndex.fromBytes(bytes);

      final results = restored.search([0.0, 0.0], k: 3);

      expect(results.length, 3);
      expect(results[0].id, 'id-1'); // Closest to origin
    });

    // ============ Approximate Recall ============

    test('achieves reasonable recall on random data', () {
      final random = Random(42);
      final index = HnswIndex(
        dimensions: 32,
        maxConnections: 16,
        efConstruction: 100,
        efSearch: 50,
        metric: DistanceMetric.euclidean,
        seed: 42,
      );

      // Insert random vectors
      final vectors = <String, List<double>>{};
      for (var i = 0; i < 500; i++) {
        final v = List.generate(32, (_) => random.nextDouble());
        final id = 'id-$i';
        vectors[id] = v;
        index.insert(id, v);
      }

      // Pick a random query
      const queryId = 'id-250';
      final query = vectors[queryId]!;

      // Get HNSW results
      final hnswResults = index.search(query, k: 10, ef: 100);

      // Compute true nearest neighbors (brute force)
      final scored = <MapEntry<String, double>>[];
      for (final entry in vectors.entries) {
        var dist = 0.0;
        for (var i = 0; i < 32; i++) {
          final diff = query[i] - entry.value[i];
          dist += diff * diff;
        }
        scored.add(MapEntry(entry.key, sqrt(dist)));
      }
      scored.sort((a, b) => a.value.compareTo(b.value));
      final trueNearest = scored.take(10).map((e) => e.key).toSet();

      // Check recall (how many of true nearest are in HNSW results)
      final hnswIds = hnswResults.map((r) => r.id).toSet();
      final recall = hnswIds.intersection(trueNearest).length / 10;

      // HNSW should achieve at least 80% recall
      expect(recall, greaterThanOrEqualTo(0.8),
          reason: 'HNSW recall should be at least 80%');
    });

    // ============ Stats ============

    test('getStats returns correct information', () {
      final index = HnswIndex(dimensions: 3, seed: 42);

      index.insert('uuid-1', [1.0, 0.0, 0.0]);
      index.insert('uuid-2', [0.0, 1.0, 0.0]);
      index.insert('uuid-3', [0.0, 0.0, 1.0]);

      final stats = index.getStats();

      expect(stats['size'], 3);
      expect(stats['dimensions'], 3);
      expect(stats['maxLevel'], greaterThanOrEqualTo(0));
    });

    // ============ Edge Cases ============

    test('handles single vector index', () {
      final index = HnswIndex(dimensions: 3, seed: 42);
      index.insert('uuid-1', [1.0, 2.0, 3.0]);

      final results = index.search([1.0, 2.0, 3.0], k: 10);

      expect(results.length, 1);
      expect(results[0].id, 'uuid-1');
    });

    test('handles zero vector', () {
      final index = HnswIndex(dimensions: 3, seed: 42);
      index.insert('uuid-1', [0.0, 0.0, 0.0]);
      index.insert('uuid-2', [1.0, 1.0, 1.0]);

      final results = index.search([1.0, 1.0, 1.0], k: 2);

      expect(results.length, 2);
    });

    test('handles large number of insertions', () {
      final index = HnswIndex(dimensions: 16, seed: 42);
      final random = Random(42);

      for (var i = 0; i < 1000; i++) {
        final v = List.generate(16, (_) => random.nextDouble());
        index.insert('id-$i', v);
      }

      expect(index.size, 1000);

      final query = List.generate(16, (_) => random.nextDouble());
      final results = index.search(query, k: 10);

      expect(results.length, 10);
    });

    // ============ UUID-specific tests ============

    test('handles realistic UUID format', () {
      final index = HnswIndex(dimensions: 3, seed: 42);

      // Real UUID v4 format
      index.insert('550e8400-e29b-41d4-a716-446655440000', [1.0, 0.0, 0.0]);
      index.insert('6ba7b810-9dad-11d1-80b4-00c04fd430c8', [0.0, 1.0, 0.0]);
      index.insert('f47ac10b-58cc-4372-a567-0e02b2c3d479', [0.0, 0.0, 1.0]);

      expect(index.size, 3);

      final results = index.search([1.0, 0.0, 0.0], k: 3);
      expect(results.length, 3);
      expect(results[0].id, '550e8400-e29b-41d4-a716-446655440000');
    });

    test('serializes and deserializes UUIDs correctly', () {
      final index = HnswIndex(dimensions: 3, seed: 42);

      final uuid1 = '550e8400-e29b-41d4-a716-446655440000';
      final uuid2 = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

      index.insert(uuid1, [1.0, 2.0, 3.0]);
      index.insert(uuid2, [4.0, 5.0, 6.0]);

      final bytes = index.toBytes();
      final restored = HnswIndex.fromBytes(bytes);

      expect(restored.contains(uuid1), isTrue);
      expect(restored.contains(uuid2), isTrue);
      expect(restored.getVector(uuid1), [1.0, 2.0, 3.0]);
      expect(restored.getVector(uuid2), [4.0, 5.0, 6.0]);
    });
  });
}
