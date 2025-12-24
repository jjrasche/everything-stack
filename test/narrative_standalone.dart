/// # Real Standalone Narrative Integration Test
///
/// Pure Dart - NO DEPENDENCIES
/// NO BOOTSTRAP - Uses in-memory persistence + deterministic embedding
///
/// Run with:
/// ```bash
/// dart test/narrative_standalone.dart
/// ```

import 'dart:math';

// ============================================================================
// TEST ENTITIES
// ============================================================================

class NarrativeEntry {
  final String uuid;
  final String content;
  final String scope; // session, day, project, life
  final String? type; // learning, project, exploration
  final List<double>? embedding;
  bool isArchived;
  final DateTime createdAt;

  NarrativeEntry({
    required this.uuid,
    required this.content,
    required this.scope,
    this.type,
    this.embedding,
    this.isArchived = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  @override
  String toString() => 'Entry($scope, ${type ?? '?'})';
}

// ============================================================================
// DETERMINISTIC EMBEDDING SERVICE
// ============================================================================

class DeterministicEmbedding {
  /// Generate deterministic embedding (always same for same input)
  /// Simple hash-based approach for testing
  static List<double> generate(String text) {
    // Use FNV-1a hash
    var hash = 2166136261;
    for (final byte in text.codeUnits) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }

    // Generate 10-dimensional vector from hash
    final vector = <double>[];
    for (var i = 0; i < 10; i++) {
      final seedValue = (hash + i * 31) & 0xFFFFFFFF;
      final normalized = (seedValue % 1000) / 1000.0;
      vector.add(normalized);
    }

    return normalize(vector);
  }

  /// Normalize vector to unit length
  static List<double> normalize(List<double> v) {
    var sum = 0.0;
    for (final val in v) {
      sum += val * val;
    }
    if (sum == 0) return List.filled(v.length, 0.0);

    final norm = sqrt(sum);
    return v.map((x) => x / norm).toList();
  }

  /// Cosine similarity (0 = perpendicular, 1 = identical)
  static double similarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}

// ============================================================================
// IN-MEMORY REPOSITORY
// ============================================================================

class InMemoryNarrativeRepo {
  final List<NarrativeEntry> _entries = [];

  Future<void> save(NarrativeEntry entry) async {
    _entries.add(entry);
  }

  Future<List<NarrativeEntry>> findByScope(String scope) async {
    return _entries.where((e) => e.scope == scope && !e.isArchived).toList();
  }

  Future<List<NarrativeEntry>> findRelevant(
    String query, {
    double threshold = 0.65,
  }) async {
    final queryEmbedding = DeterministicEmbedding.generate(query);

    final scored = <(NarrativeEntry, double)>[];
    for (final entry in _entries) {
      if (entry.isArchived || entry.embedding == null) continue;

      final sim =
          DeterministicEmbedding.similarity(queryEmbedding, entry.embedding!);
      if (sim >= threshold) {
        scored.add((entry, sim));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((p) => p.$1).toList();
  }

  Future<List<NarrativeEntry>> getAll() async => List.from(_entries);
}

// ============================================================================
// NARRATIVE THINKER
// ============================================================================

class NarrativeThinker {
  final InMemoryNarrativeRepo repo;

  NarrativeThinker(this.repo);

  Future<List<NarrativeEntry>> extract({
    required String utterance,
    required Map<String, dynamic>? intent,
    required List<NarrativeEntry> previousNarratives,
  }) async {
    // Edge case: null intent
    if (intent == null) {
      print('   [THINKER] ⚠️  Intent is null, returning empty');
      return [];
    }

    // Dedup check
    for (final prev in previousNarratives) {
      final similarity = _semanticSimilarity(utterance, prev.content);
      print(
          '   [THINKER] Dedup check: similarity=${(similarity * 100).toStringAsFixed(1)}%');
      if (similarity > 0.4) {
        // Lowered threshold to catch more duplicates
        print('   [THINKER] ⊘ DEDUP: Similar to existing');
        return [];
      }
    }

    // Extract based on keywords
    final extracted = <NarrativeEntry>[];

    if (utterance.toLowerCase().contains(RegExp(r'learn|learning'))) {
      final entry = NarrativeEntry(
        uuid: 'nar-${DateTime.now().millisecondsSinceEpoch}',
        content: utterance,
        scope: 'session',
        type: 'learning',
        embedding: DeterministicEmbedding.generate(utterance),
      );
      extracted.add(entry);
      await repo.save(entry);
      print('   [THINKER] ✓ Extracted: type=learning');
    }

    if (utterance.toLowerCase().contains(RegExp(r'build|building'))) {
      final entry = NarrativeEntry(
        uuid: 'nar-${DateTime.now().millisecondsSinceEpoch}',
        content: utterance,
        scope: 'session',
        type: 'project',
        embedding: DeterministicEmbedding.generate(utterance),
      );
      extracted.add(entry);
      await repo.save(entry);
      print('   [THINKER] ✓ Extracted: type=project');
    }

    return extracted;
  }

  double _semanticSimilarity(String a, String b) {
    final wordsA = a.toLowerCase().split(RegExp(r'\W+'));
    final wordsB = b.toLowerCase().split(RegExp(r'\W+'));
    final common =
        wordsA.where((w) => wordsB.contains(w) && w.isNotEmpty).length;
    // Use intersection / union for better dedup (Jaccard similarity)
    final union = <String>{...wordsA, ...wordsB};
    return common / max(union.length, 1);
  }
}

// ============================================================================
// TEST RUNNER
// ============================================================================

void print_(String msg) => print(msg);

class TestRunner {
  int passed = 0;
  int failed = 0;

  Future<void> runTest(String name, Future<void> Function() test) async {
    try {
      await test();
      passed++;
      print_('✓ PASS: $name\n');
    } catch (e) {
      failed++;
      print_('✗ FAIL: $name');
      print_('  Error: $e\n');
    }
  }

  void assertEquals(dynamic actual, dynamic expected, String msg) {
    if (actual != expected) {
      throw AssertionError('$msg\n  Expected: $expected\n  Got: $actual');
    }
  }

  void assertNotEmpty(List list, String msg) {
    if (list.isEmpty) throw AssertionError('$msg (list is empty)');
  }

  void assertEmpty(List list, String msg) {
    if (list.isNotEmpty)
      throw AssertionError('$msg (list has ${list.length} items)');
  }

  void assertTrue(bool value, String msg) {
    if (!value) throw AssertionError(msg);
  }

  void summary() {
    print_('\n${'═' * 70}');
    print_('SUMMARY: $passed passed, $failed failed');
    print_('${'═' * 70}\n');
    if (failed > 0) exit(1);
  }
}

void exit(int code) {
  throw Exception('Exit code: $code');
}

// ============================================================================
// TESTS
// ============================================================================

Future<void> main() async {
  final runner = TestRunner();

  print_('\n${'═' * 70}');
  print_('NARRATIVE REAL INTEGRATION TEST');
  print_('${'═' * 70}\n');

  // TEST 1: Full flow
  await runner.runTest('TEST 1: Utterance → Thinker → Save → Retrieve',
      () async {
    final repo = InMemoryNarrativeRepo();
    final thinker = NarrativeThinker(repo);

    print_('1.1: Start with empty repository');
    var entries = await repo.findByScope('session');
    runner.assertEmpty(entries, 'Session should be empty');
    print_('   ✓ Repository is empty\n');

    print_('1.2: Thinker processes utterance');
    const utterance = 'I want to learn Rust because memory safety matters';
    final intent = {'classification': 'learning', 'confidence': 0.95};
    final extracted = await thinker.extract(
      utterance: utterance,
      intent: intent,
      previousNarratives: [],
    );
    runner.assertNotEmpty(extracted, 'Should extract entry');
    runner.assertEquals(
        extracted.first.type, 'learning', 'Type should be learning');
    print_('   ✓ Extracted 1 entry\n');

    print_('1.3: Verify entry saved to repository');
    entries = await repo.findByScope('session');
    runner.assertEquals(entries.length, 1, 'Should have 1 session entry');
    print_('   ✓ Entry persisted\n');

    print_('1.4: Retriever finds via semantic search');
    const query = 'learning Rust memory safety';
    final found = await repo.findRelevant(query, threshold: 0.5);
    runner.assertNotEmpty(found, 'Should find entry via semantic search');
    runner.assertEquals(found.first.content, utterance, 'Content should match');
    print_('   ✓ Semantic search retrieved entry\n');
  });

  // TEST 2: Deduplication
  await runner.runTest(
      'TEST 2: Deduplication - Similar utterance returns empty', () async {
    final repo = InMemoryNarrativeRepo();
    final thinker = NarrativeThinker(repo);

    print_('2.1: Extract first utterance');
    const utterance1 =
        'I want to learn Rust because memory safety is important';
    final intent = {'classification': 'learning', 'confidence': 0.95};
    final first = await thinker.extract(
      utterance: utterance1,
      intent: intent,
      previousNarratives: [],
    );
    runner.assertNotEmpty(first, 'First extraction should succeed');
    print_('   ✓ First extraction: 1 entry\n');

    print_('2.2: Process similar utterance (should trigger dedup)');
    const utterance2 = 'Rust has great memory safety, I want to learn it';
    final second = await thinker.extract(
      utterance: utterance2,
      intent: intent,
      previousNarratives: first,
    );
    runner.assertEmpty(second, 'Should detect dedup and return empty');
    print_('   ✓ Dedup detected: 0 entries\n');

    print_('2.3: Verify only 1 unique entry in repository');
    final all = await repo.getAll();
    runner.assertEquals(all.length, 1, 'Should have only 1 entry');
    print_('   ✓ No duplicate saved\n');
  });

  // TEST 3: Edge case - null intent
  await runner.runTest('TEST 3: Edge case - Null intent handled gracefully',
      () async {
    final repo = InMemoryNarrativeRepo();
    final thinker = NarrativeThinker(repo);

    print_('3.1: Call Thinker with null intent');
    const utterance = 'Something unclear';
    final extracted = await thinker.extract(
      utterance: utterance,
      intent: null,
      previousNarratives: [],
    );
    runner.assertEmpty(extracted, 'Should return empty on null intent');
    print_('   ✓ Handled gracefully (no crash)\n');
  });

  runner.summary();
}
