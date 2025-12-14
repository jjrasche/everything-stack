/// # Persistence Performance Benchmarks
///
/// ## What this tests
/// Measures performance of key persistence operations on both platforms:
/// - Bulk insert (1000 notes with embeddings)
/// - Semantic search (HNSW index queries)
/// - Graph traversal (multi-hop edge queries)
/// - Version history (time travel reconstruction)
///
/// ## Platform coverage
/// **MUST run on both platforms to establish/verify dual-persistence performance:**
///
/// ```bash
/// # Run on native (ObjectBox)
/// flutter test test/performance/persistence_benchmarks.dart
///
/// # Run on web (IndexedDB)
/// flutter test --platform chrome test/performance/persistence_benchmarks.dart
/// ```
///
/// ## Baseline establishment
/// First run establishes baseline results:
/// ```bash
/// # Generate baseline for native
/// flutter test test/performance/persistence_benchmarks.dart > benchmarks/native_baseline.txt
///
/// # Generate baseline for web
/// flutter test --platform chrome test/performance/persistence_benchmarks.dart > benchmarks/web_baseline.txt
/// ```
///
/// JSON results are output to console - redirect to benchmarks/baseline_results.json
///
/// ## Pass criteria (configurable via environment)
/// Set ENFORCE_THRESHOLDS=true to fail tests on regression:
/// - Web semantic search p95 < 200ms
/// - Native semantic search p95 < 50ms
/// - Insert rate > 50 notes/sec on both platforms
///
/// Default: measurement-only mode (report but don't fail).
///
/// ## CI Integration
/// - Runs on both platforms in CI
/// - Measures performance and reports results
/// - Optionally enforces thresholds (set ENFORCE_THRESHOLDS=true)
/// - Compares against committed baseline (future enhancement)

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/domain/note_repository.dart';
import 'package:everything_stack_template/core/edge.dart';
import 'package:everything_stack_template/core/edge_repository.dart';
import 'package:everything_stack_template/core/version_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

import '../harness/benchmark_runner.dart';
import '../harness/persistence_test_harness.dart';

void main() {
  // Initialize test bindings
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistenceTestHarness harness;
  late BenchmarkRunner benchmarkRunner;
  late BenchmarkSuite suite;

  // Configuration: enforce thresholds or measurement-only?
  final enforceThresholds = const String.fromEnvironment('ENFORCE_THRESHOLDS') == 'true';

  setUpAll(() async {
    harness = PersistenceTestHarness();
    await harness.initialize();
    benchmarkRunner = BenchmarkRunner(
      platform: harness.isWeb ? 'web' : 'native',
    );
    suite = BenchmarkSuite(
      name: 'Persistence Benchmarks (${harness.isWeb ? 'Web' : 'Native'})',
      results: [],
    );

    print('\n' + '=' * 80);
    print('Performance Benchmarks - ${harness.isWeb ? 'Web (IndexedDB)' : 'Native (ObjectBox)'}');
    print('Threshold enforcement: ${enforceThresholds ? 'ENABLED' : 'DISABLED (measurement only)'}');
    print('=' * 80 + '\n');
  });

  tearDownAll(() async {
    // Print full suite results
    print('\n' + '=' * 80);
    print(suite.toString());
    print('=' * 80);
    print('\nJSON Output:');
    print(jsonEncode(suite.toJson()));
    print('=' * 80 + '\n');

    await harness.dispose();
  });

  group('Bulk Insert Performance', () {
    test('insert 1000 notes with embeddings', () async {
      final noteRepo = NoteRepository(
        adapter: harness.factory.noteAdapter,
        embeddingService: MockEmbeddingService(),
        versionRepo: VersionRepository(adapter: harness.factory.versionAdapter),
      );

      // Generate test data
      final notes = _generateNotes(1000);

      // Benchmark bulk insert
      final result = await benchmarkRunner.measure(
        'bulk_insert_1000_notes',
        () async {
          // Clear DB first
          final all = await noteRepo.findAll();
          for (final note in all) {
            await noteRepo.delete(note.uuid);
          }

          // Insert all notes
          await noteRepo.saveAll(notes);
        },
        iterations: 5, // Fewer iterations for bulk operation
        warmup: 1,
      );

      suite.results.add(result);

      // Verify pass criteria: > 50 notes/sec
      final notesPerSecond = 1000 / (result.avg.inMicroseconds / 1000000);
      print('Insert rate: ${notesPerSecond.toStringAsFixed(2)} notes/sec');

      if (enforceThresholds) {
        expect(notesPerSecond, greaterThan(50),
            reason: 'Insert rate must be > 50 notes/sec');
      } else {
        print('  Threshold check: ${notesPerSecond > 50 ? 'PASS' : 'FAIL'} (not enforced)');
      }

      // Clean up
      final all = await noteRepo.findAll();
      for (final note in all) {
        await noteRepo.deleteByUuid(note.uuid);
      }
    });
  });

  group('Semantic Search Performance', () {
    late NoteRepository noteRepo;

    setUp(() async {
      noteRepo = NoteRepository(
        adapter: harness.factory.noteAdapter,
        embeddingService: MockEmbeddingService(),
        versionRepo: VersionRepository(adapter: harness.factory.versionAdapter),
      );

      // Seed database with 1000 notes
      final notes = _generateNotes(1000);
      await noteRepo.saveAll(notes);
    });

    tearDown(() async {
      // Clean up
      final all = await noteRepo.findAll();
      for (final note in all) {
        await noteRepo.deleteByUuid(note.uuid);
      }
    });

    test('semantic search p95 meets threshold', () async {
      // Benchmark semantic search
      final result = await benchmarkRunner.measure(
        'semantic_search_1000_notes',
        () async {
          await noteRepo.semanticSearch('machine learning algorithms', limit: 10);
        },
        iterations: 20, // More iterations for statistical validity
      );

      suite.results.add(result);

      // Platform-specific thresholds
      final threshold = harness.isWeb
          ? Duration(milliseconds: 200) // Web: 200ms
          : Duration(milliseconds: 50); // Native: 50ms

      print('p95: ${result.p95.inMilliseconds}ms (threshold: ${threshold.inMilliseconds}ms)');

      if (enforceThresholds) {
        expect(result.p95, lessThan(threshold),
            reason: 'Semantic search p95 must be < ${threshold.inMilliseconds}ms on ${harness.isWeb ? 'web' : 'native'}');
      } else {
        print('  Threshold check: ${result.p95 < threshold ? 'PASS' : 'FAIL'} (not enforced)');
      }
    });

    test('semantic search with various query sizes', () async {
      final queries = [
        'AI',
        'machine learning',
        'deep neural network architectures',
        'artificial intelligence and natural language processing techniques',
      ];

      for (final query in queries) {
        final result = await benchmarkRunner.measure(
          'search_query_length_${query.length}',
          () async {
            await noteRepo.semanticSearch(query, limit: 10);
          },
          iterations: 10,
        );
        suite.results.add(result);
        print('Query "$query" (${query.length} chars): p95=${result.p95.inMilliseconds}ms');
      }
    });
  });

  group('Graph Traversal Performance', () {
    late EdgeRepository edgeRepo;
    late NoteRepository noteRepo;
    final noteUuids = <String>[];

    setUp(() async {
      edgeRepo = EdgeRepository(adapter: harness.factory.edgeAdapter);
      noteRepo = NoteRepository(
        adapter: harness.factory.noteAdapter,
        embeddingService: MockEmbeddingService(),
        versionRepo: VersionRepository(adapter: harness.factory.versionAdapter),
      );

      // Create graph: 100 notes, each linked to 3 others (300 edges)
      final notes = _generateNotes(100);
      await noteRepo.saveAll(notes);
      noteUuids.addAll(notes.map((n) => n.uuid));

      for (int i = 0; i < 100; i++) {
        for (int j = 1; j <= 3; j++) {
          final targetIndex = (i + j) % 100;
          final edge = Edge(
            sourceType: 'Note',
            sourceUuid: noteUuids[i],
            targetType: 'Note',
            targetUuid: noteUuids[targetIndex],
            edgeType: 'relates_to',
          );
          await edgeRepo.save(edge);
        }
      }
    });

    tearDown(() async {
      // Clean up edges
      final edges = await edgeRepo.findAll();
      for (final edge in edges) {
        await edgeRepo.deleteEdge(
          edge.sourceUuid,
          edge.targetUuid,
          edge.edgeType,
        );
      }

      // Clean up notes
      final notes = await noteRepo.findAll();
      for (final note in notes) {
        await noteRepo.deleteByUuid(note.uuid);
      }
    });

    test('3-hop traversal performance', () async {
      final result = await benchmarkRunner.measure(
        'graph_traverse_3_hops',
        () async {
          await edgeRepo.traverse(
            startUuid: noteUuids.first,
            depth: 3,
            direction: 'outgoing',
          );
        },
        iterations: 15,
      );

      suite.results.add(result);
      print('3-hop traversal p95: ${result.p95.inMilliseconds}ms');

      // Reasonable threshold: < 100ms for 3-hop on 300 edges
      if (enforceThresholds) {
        expect(result.p95, lessThan(Duration(milliseconds: 100)),
            reason: '3-hop traversal should be < 100ms');
      } else {
        print('  Threshold check: ${result.p95.inMilliseconds < 100 ? 'PASS' : 'FAIL'} (not enforced)');
      }
    });
  });

  group('Version History Performance', () {
    late VersionRepository versionRepo;
    late NoteRepository noteRepo;
    late String testNoteUuid;

    setUp(() async {
      versionRepo = VersionRepository(adapter: harness.factory.versionAdapter);
      noteRepo = NoteRepository(
        adapter: harness.factory.noteAdapter,
        embeddingService: MockEmbeddingService(),
        versionRepo: versionRepo,
      );

      // Create note with 50 versions
      final note = Note(
        title: 'Test Note',
        content: 'Initial content',
      );
      await noteRepo.save(note);
      testNoteUuid = note.uuid;

      // Create 49 more versions
      for (int i = 1; i < 50; i++) {
        note.content = 'Updated content version $i';
        await noteRepo.save(note);
      }
    });

    tearDown(() async {
      // Clean up versions
      final versions = await versionRepo.findAll();
      for (final version in versions) {
        await versionRepo.deleteByUuid(version.uuid);
      }

      // Clean up note
      await noteRepo.deleteByUuid(testNoteUuid);
    });

    test('load version history (50 versions)', () async {
      final result = await benchmarkRunner.measure(
        'version_history_50_versions',
        () async {
          await versionRepo.getHistory(testNoteUuid);
        },
        iterations: 15,
      );

      suite.results.add(result);
      print('Load 50 versions p95: ${result.p95.inMilliseconds}ms');

      // Should be fast: < 50ms
      if (enforceThresholds) {
        expect(result.p95, lessThan(Duration(milliseconds: 50)),
            reason: 'Loading version history should be < 50ms');
      } else {
        print('  Threshold check: ${result.p95.inMilliseconds < 50 ? 'PASS' : 'FAIL'} (not enforced)');
      }
    });

    test('reconstruct state from deltas', () async {
      final versions = await versionRepo.getHistory(testNoteUuid);
      final midpoint = versions[versions.length ~/ 2].timestamp;

      final result = await benchmarkRunner.measure(
        'reconstruct_state_25_deltas',
        () async {
          await versionRepo.reconstruct<Note>(
            testNoteUuid,
            'Note',
            midpoint,
            (json) => Note.fromJson(json),
          );
        },
        iterations: 15,
      );

      suite.results.add(result);
      print('Reconstruct from 25 deltas p95: ${result.p95.inMilliseconds}ms');

      // Delta reconstruction should be fast: < 100ms
      if (enforceThresholds) {
        expect(result.p95, lessThan(Duration(milliseconds: 100)),
            reason: 'State reconstruction should be < 100ms');
      } else {
        print('  Threshold check: ${result.p95.inMilliseconds < 100 ? 'PASS' : 'FAIL'} (not enforced)');
      }
    });
  });
}

// ============================================================================
// Test Data Generation Strategy
// ============================================================================
//
// **Approach: Deterministic + Fast + Repeatable**
//
// 1. Content Generation:
//    - NOT random Lorem ipsum (meaningless for semantic search)
//    - NOT real AI model calls (too slow, non-deterministic, API costs)
//    - YES: Template-based with topic variation (realistic structure, fast)
//
// 2. Embedding Generation:
//    - MockEmbeddingService generates deterministic 384-dim vectors
//    - Based on content hash (same content = same embedding)
//    - Fast (no API calls), repeatable (same input = same output)
//    - Adequate for performance testing (HNSW cares about vector math, not semantics)
//
// 3. Trade-offs:
//    - ✅ Fast: 1000 notes generated in < 1 second
//    - ✅ Repeatable: Deterministic results across runs
//    - ✅ Realistic size: 100-500 words per note (typical user content)
//    - ⚠️  Not real embeddings: Semantic quality not tested (that's functional, not performance)
//
// **Conclusion**: This strategy is correct for PERFORMANCE testing.
// For FUNCTIONAL testing of semantic search quality, use real embeddings in
// test/integration/hnsw_integration_test.dart (which does).
//
// ============================================================================

/// Generate test notes with realistic content and embeddings
List<Note> _generateNotes(int count) {
  final topics = [
    'machine learning algorithms',
    'deep neural networks',
    'natural language processing',
    'computer vision techniques',
    'reinforcement learning',
    'data science methods',
    'artificial intelligence research',
    'software engineering practices',
    'cloud computing infrastructure',
    'database optimization',
  ];

  final notes = <Note>[];
  for (int i = 0; i < count; i++) {
    final topic = topics[i % topics.length];
    final note = Note(
      title: '$topic - Note ${i + 1}',
      content: _generateContent(topic, 100 + (i % 400)), // 100-500 words
      tags: [topic.split(' ').first, 'benchmark', 'test'],
    );
    notes.add(note);
  }
  return notes;
}

/// Generate realistic content for a given topic
String _generateContent(String topic, int wordCount) {
  final sentences = [
    'This note discusses $topic in detail.',
    'Key concepts include various approaches and methodologies.',
    'Recent research has shown significant improvements in this area.',
    'Practical applications are numerous and growing.',
    'Future directions include advanced techniques and optimizations.',
    'Implementation requires careful consideration of trade-offs.',
    'Performance characteristics vary across different scenarios.',
    'Best practices have emerged from extensive experimentation.',
  ];

  final buffer = StringBuffer();
  int words = 0;

  while (words < wordCount) {
    for (final sentence in sentences) {
      buffer.write(sentence);
      buffer.write(' ');
      words += sentence.split(' ').length;
      if (words >= wordCount) break;
    }
  }

  return buffer.toString().trim();
}
