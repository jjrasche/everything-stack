/// # HNSW Index Load Benchmark
///
/// Measures and verifies HNSW index loading performance.
///
/// ## What it tests
/// - Index serialization/deserialization speed
/// - Round-trip integrity (save → load preserves data)
/// - Search performance after load
///
/// ## Run (isolated test mode)
/// ```bash
/// flutter test integration_test/hnsw_index_benchmark.dart -d windows --dart-define=TEST_MODE=true
/// ```
///
/// ## Run (against production data - for real-world benchmarks)
/// ```bash
/// flutter test integration_test/hnsw_index_benchmark.dart -d windows
/// ```
///
/// ## Test isolation
/// With TEST_MODE=true: Uses temp directory, creates synthetic test data
/// Without TEST_MODE: Uses production data (reports only, no assertions on first run)

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get_it/get_it.dart';

import 'package:everything_stack_template/bootstrap.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/hnsw_index_store.dart';
import 'package:everything_stack_template/services/chunking_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Check if running in test mode (isolated database)
  const isTestMode = bool.fromEnvironment('TEST_MODE', defaultValue: false);

  group('HNSW Index Performance', () {
    testWidgets('bootstrap measures index load time', (tester) async {
      print('\n' + '═' * 60);
      print('🔬 HNSW INDEX LOAD BENCHMARK');
      print('   TEST_MODE: $isTestMode ${isTestMode ? "(isolated)" : "(production data)"}');
      print('═' * 60);

      // Measure total bootstrap time (includes index loading)
      final bootstrapStopwatch = Stopwatch()..start();
      await initializeEverythingStack();
      await setupServiceLocator();
      bootstrapStopwatch.stop();

      final bootstrapMs = bootstrapStopwatch.elapsedMilliseconds;
      print('\n⏱️  Total bootstrap time: ${bootstrapMs}ms');

      // Get the loaded index
      final hnswIndex = GetIt.instance<HnswIndex>();
      final indexStore = GetIt.instance<HnswIndexStore>();
      final chunkingService = GetIt.instance<ChunkingService>();

      print('📊 Index size: ${hnswIndex.size} vectors');

      // Get index stats
      final stats = hnswIndex.getStats();
      print('📈 Index stats:');
      print('   - Dimensions: ${stats['dimensions']}');
      print('   - Max level: ${stats['maxLevel']}');
      print('   - Avg connections: ${(stats['avgConnections'] as double).toStringAsFixed(1)}');

      // Check cache metadata
      final metadata = await indexStore.getMetadata();
      if (metadata != null) {
        print('💾 Cache metadata:');
        print('   - Saved at: ${metadata.savedAt}');
        print('   - Size: ${(metadata.sizeBytes / 1024 / 1024).toStringAsFixed(1)}MB');
        print('   - Vectors: ${metadata.vectorCount}');
      } else {
        print('💾 Cache: Not yet created (first run)');
      }

      // Verify index has data (if chunks exist)
      final allChunks = await chunkingService.getAllChunks();
      print('\n📦 Database chunks: ${allChunks.length}');

      if (allChunks.isNotEmpty) {
        // Index should have loaded vectors
        expect(
          hnswIndex.size,
          greaterThan(0),
          reason: 'Index MUST have vectors if chunks exist in database',
        );

        // Index size should roughly match chunk count
        // (may differ slightly due to duplicate handling)
        final sizeDiff = (hnswIndex.size - allChunks.length).abs();
        expect(
          sizeDiff,
          lessThan(allChunks.length * 0.1 + 10), // Allow 10% + 10 tolerance
          reason: 'Index size should be close to chunk count',
        );
      }

      print('\n' + '─' * 60);
      print('PERFORMANCE REPORT');
      print('─' * 60);

      // Performance reporting (not assertions on first run or production data)
      if (metadata != null) {
        print('✓ Cache exists - load was from cache');

        if (bootstrapMs < 1000) {
          print('⚡ EXCELLENT: Bootstrap in <1s (${bootstrapMs}ms)');
        } else if (bootstrapMs < 2000) {
          print('✅ GOOD: Bootstrap in <2s (${bootstrapMs}ms)');
        } else if (bootstrapMs < 5000) {
          print('⚠️  ACCEPTABLE: Bootstrap in <5s (${bootstrapMs}ms)');
        } else {
          print('❌ SLOW: Bootstrap took ${bootstrapMs}ms (target: <5s)');
        }

        // Only enforce threshold when cache exists (not first run)
        if (isTestMode || hnswIndex.size < 1000) {
          // For small indexes or test mode, enforce strict threshold
          expect(
            bootstrapMs,
            lessThan(5000),
            reason: 'Cached bootstrap should complete in <5s (was ${bootstrapMs}ms)',
          );
        }
      } else {
        print('ℹ️  First run (cache being built) - performance not enforced');
        print('   Bootstrap took: ${bootstrapMs}ms');
        print('   Next run should be significantly faster (cache will be used)');
      }

      print('\n' + '═' * 60);
      print('BENCHMARK COMPLETE');
      print('═' * 60 + '\n');
    });

    testWidgets('index cache round-trip integrity', (tester) async {
      print('\n' + '═' * 60);
      print('🔄 CACHE ROUND-TRIP INTEGRITY TEST');
      print('═' * 60);

      // Bootstrap if not already done
      try {
        GetIt.instance<HnswIndex>();
      } catch (_) {
        await initializeEverythingStack();
        await setupServiceLocator();
      }

      final hnswIndex = GetIt.instance<HnswIndex>();
      final indexStore = GetIt.instance<HnswIndexStore>();

      if (hnswIndex.size == 0) {
        print('⏭️  Skipping: No vectors in index');
        return;
      }

      // Get original stats
      final originalSize = hnswIndex.size;
      final originalStats = hnswIndex.getStats();

      print('📊 Original index: $originalSize vectors');

      // Force save to cache
      print('💾 Saving index to cache...');
      final saveStopwatch = Stopwatch()..start();
      await indexStore.saveIndex(hnswIndex);
      saveStopwatch.stop();
      print('   Save time: ${saveStopwatch.elapsedMilliseconds}ms');

      // Load from cache
      print('📂 Loading index from cache...');
      final loadStopwatch = Stopwatch()..start();
      final loadResult = await indexStore.loadIndex();
      loadStopwatch.stop();
      print('   Load time: ${loadStopwatch.elapsedMilliseconds}ms');

      expect(loadResult.isLoaded, isTrue, reason: 'Cache load should succeed');

      final loadedIndex = loadResult.index!;
      final loadedStats = loadedIndex.getStats();

      print('\n📈 Comparing stats:');
      print('   Original size: $originalSize');
      print('   Loaded size: ${loadedIndex.size}');
      print('   Original maxLevel: ${originalStats['maxLevel']}');
      print('   Loaded maxLevel: ${loadedStats['maxLevel']}');

      // Verify integrity
      expect(
        loadedIndex.size,
        equals(originalSize),
        reason: 'Loaded index must have same vector count as original',
      );

      expect(
        loadedStats['maxLevel'],
        equals(originalStats['maxLevel']),
        reason: 'Loaded index must have same max level as original',
      );

      expect(
        loadedStats['dimensions'],
        equals(originalStats['dimensions']),
        reason: 'Loaded index must have same dimensions as original',
      );

      // Performance: Load should be fast
      expect(
        loadStopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'Cache load should complete in <1s (was ${loadStopwatch.elapsedMilliseconds}ms)',
      );

      print('\n✅ Round-trip integrity verified');
      print('═' * 60 + '\n');
    });

    testWidgets('search performance after cache load', (tester) async {
      print('\n' + '═' * 60);
      print('🔍 SEARCH PERFORMANCE TEST');
      print('═' * 60);

      // Bootstrap if not already done
      try {
        GetIt.instance<HnswIndex>();
      } catch (_) {
        await initializeEverythingStack();
        await setupServiceLocator();
      }

      final hnswIndex = GetIt.instance<HnswIndex>();

      if (hnswIndex.size == 0) {
        print('⏭️  Skipping: No vectors in index');
        return;
      }

      print('📊 Index size: ${hnswIndex.size} vectors');

      // Create a random query vector (384 dimensions)
      final queryVector = List<double>.generate(384, (i) => (i % 10) / 10.0);

      // Warm up
      hnswIndex.search(queryVector, k: 5);

      // Measure search time over multiple queries
      const numQueries = 100;
      final searchStopwatch = Stopwatch()..start();

      for (var i = 0; i < numQueries; i++) {
        hnswIndex.search(queryVector, k: 5);
      }

      searchStopwatch.stop();
      final avgSearchMs = searchStopwatch.elapsedMilliseconds / numQueries;

      print('\n⏱️  Search performance ($numQueries queries):');
      print('   Total time: ${searchStopwatch.elapsedMilliseconds}ms');
      print('   Average per query: ${avgSearchMs.toStringAsFixed(2)}ms');

      // HNSW search should be fast (O(log n))
      expect(
        avgSearchMs,
        lessThan(50),
        reason: 'HNSW search should average <50ms per query (was ${avgSearchMs.toStringAsFixed(2)}ms)',
      );

      if (avgSearchMs < 5) {
        print('⚡ EXCELLENT: <5ms per search');
      } else if (avgSearchMs < 20) {
        print('✅ GOOD: <20ms per search');
      } else {
        print('⚠️  SLOW: ${avgSearchMs.toStringAsFixed(2)}ms per search');
      }

      print('\n' + '═' * 60 + '\n');
    });
  });
}
