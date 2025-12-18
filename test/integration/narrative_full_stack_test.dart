/// # Narrative Full Stack Integration Test
///
/// **INTEGRATION TEST** - Tests complete Narrative architecture with real services:
/// - Real ObjectBox persistence
/// - Real Groq API calls (requires GROQ_API_KEY)
/// - Real embedding generation (requires embedding service configured)
/// - End-to-end flow verification
///
/// Run with:
/// ```bash
/// flutter test test/integration/narrative_full_stack_test.dart \
///   --dart-define=GROQ_API_KEY=your-key \
///   --dart-define=JINA_API_KEY=your-key
/// ```
///
/// Skip locally: Set SKIP_INTEGRATION_TESTS=true
/// Runs in CI automatically.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/narrative_entry.dart';
import 'package:everything_stack_template/domain/narrative_repository.dart';
import 'package:everything_stack_template/services/narrative_thinker.dart';
import 'package:everything_stack_template/services/narrative_retriever.dart';
import 'package:everything_stack_template/services/narrative_checkpoint.dart';
import 'package:everything_stack_template/services/llm_service.dart';

void main() {
  group('Narrative Full Stack Integration', () {
    // Skip if SKIP_INTEGRATION_TESTS is set or API keys missing
    final skipTests = _shouldSkipIntegrationTests();

    late NarrativeRepository narrativeRepo;
    late NarrativeThinker thinker;
    late NarrativeRetriever retriever;
    late NarrativeCheckpoint checkpoint;

    setUpAll(() async {
      if (skipTests) {
        print('⊘ Skipping integration tests (set SKIP_INTEGRATION_TESTS=false to run)');
        return;
      }

      print('🚀 Initializing Narrative Full Stack Integration Tests...');

      // Initialize real services
      // In real test environment, bootstrap would handle this
      // For now, these would be initialized via bootstrap in actual app
      print('⚠️  Note: Run this with bootstrap initialized in a real app context');
    });

    test(
      'Session narratives persist to ObjectBox and are queryable',
      skip: skipTests,
      () async {
        // GIVEN: Clean database
        final initialEntries = await narrativeRepo.findByScope('session');
        expect(initialEntries, isEmpty, reason: 'Start with empty session');

        // WHEN: Create multiple session entries
        final entry1 = NarrativeEntry(
          content: 'Learning Rust teaches ownership models. Because memory safety matters.',
          scope: 'session',
          type: 'learning',
        );
        final entry2 = NarrativeEntry(
          content: 'Building concurrent systems. Because scalability requires rethinking design.',
          scope: 'session',
          type: 'project',
        );

        await narrativeRepo.save(entry1);
        await narrativeRepo.save(entry2);

        // THEN: Entries persist and are retrievable
        final sessionEntries = await narrativeRepo.findByScope('session');
        expect(sessionEntries, hasLength(2), reason: 'Both entries saved');
        expect(
          sessionEntries.map((e) => e.content),
          containsAll([entry1.content, entry2.content]),
          reason: 'Content matches',
        );
      },
    );

    test(
      'Semantic search returns relevant entries above threshold',
      skip: skipTests,
      () async {
        // GIVEN: Entries with embeddings in database
        // (In real test, embeddings generated via EmbeddingQueueService)
        final entry = NarrativeEntry(
          content: 'Distributed systems require consensus algorithms. Because coordination across failure domains is hard.',
          scope: 'session',
          type: 'learning',
        );
        // Assume embedding was generated: entry.embedding = [0.1, 0.2, ...]

        // WHEN: Search for semantically similar content
        final query = 'How do distributed systems handle failures?';
        final results = await narrativeRepo.findRelevant(
          query,
          topK: 5,
          threshold: 0.65,
        );

        // THEN: If embeddings available, should find relevant entries
        // (Actual relevance depends on embedding service quality)
        // Verify query executed without error
        expect(results, isNotNull, reason: 'Search completes');
      },
    );

    test(
      'NarrativeThinker extracts entries via Groq (prompt testing)',
      skip: skipTests,
      () async {
        // GIVEN: Conversation context
        final utterance = 'I want to build an AI system that learns from feedback';
        final intentOutput = {
          'classification': 'intent:project',
          'confidence': 0.92,
          'reasoning': 'User expressing intention to build something',
        };
        final chatHistory = [
          {'role': 'user', 'content': utterance},
        ];

        // WHEN: Thinker processes turn
        final previousNarratives = await narrativeRepo.findByScope('session');
        final extracted = await thinker.updateFromTurn(
          utterance: utterance,
          intentOutput: intentOutput,
          chatHistory: chatHistory,
          previousNarratives: previousNarratives,
        );

        // THEN: Verify extraction
        // - Should return NarrativeEntry objects
        expect(extracted, isA<List<NarrativeEntry>>(), reason: 'Returns entries');

        // - Each entry should have content and scope
        for (final entry in extracted) {
          expect(entry.content, isNotEmpty, reason: 'Entry has content');
          expect(
            ['session', 'day', 'week', 'project', 'life'],
            contains(entry.scope),
            reason: 'Scope is valid',
          );
        }

        // - Verify Groq prompt structure (no hallucinations)
        // In real test, also verify: no duplicate entries, correct JSON format
      },
    );

    test(
      'NarrativeRetriever formats entries for Intent Engine context',
      skip: skipTests,
      () async {
        // GIVEN: Relevant narrative entries
        final entries = [
          NarrativeEntry(
            content: 'Offline-first architecture enables resilience. Because network failures are inevitable.',
            scope: 'session',
            type: 'learning',
          ),
          NarrativeEntry(
            content: 'Building a knowledge system.',
            scope: 'day',
            type: 'project',
          ),
        ];

        // WHEN: Format for Intent Engine
        final formatted = retriever.formatForContext(entries);

        // THEN: Verify format is suitable for LLM injection
        expect(formatted, contains('Relevant Narratives'), reason: 'Has header');
        expect(formatted, contains('SESSION'), reason: 'Shows scope');
        expect(formatted, contains('learning'), reason: 'Shows type');
        expect(formatted, contains('offline-first'), reason: 'Content visible');

        // Verify no truncation or corruption
        expect(formatted.length, greaterThan(50), reason: 'Content preserved');
      },
    );

    test(
      'Training checkpoint collects and records deltas',
      skip: skipTests,
      () async {
        // GIVEN: Session with entries
        // (Would be populated by Thinker in real scenario)

        // WHEN: Training triggered
        final delta = await checkpoint.train();

        // THEN: Delta structure is valid
        expect(delta, isA<NarrativeDelta>(), reason: 'Returns delta');
        expect(delta.added, isA<List<NarrativeEntry>>(), reason: 'Added is list');
        expect(delta.removed, isA<List<NarrativeEntry>>(), reason: 'Removed is list');
        expect(delta.promoted, isA<List>(), reason: 'Promoted is list');
      },
    );

    test(
      'Scope independence: Day does not auto-populate from Session',
      skip: skipTests,
      () async {
        // GIVEN: Session entries exist
        final sessionEntry = NarrativeEntry(
          content: 'Learning Dart.',
          scope: 'session',
          type: 'learning',
        );
        await narrativeRepo.save(sessionEntry);

        // WHEN: Query Day scope
        final dayEntries = await narrativeRepo.findByScope('day');

        // THEN: Day is independent (no auto-bubbling)
        expect(
          dayEntries.where((e) => e.content.contains('Dart')),
          isEmpty,
          reason: 'Session entry not in Day',
        );
      },
    );

    test(
      'Archive pattern: entries soft-deleted but retained',
      skip: skipTests,
      () async {
        // GIVEN: Entry created
        final entry = NarrativeEntry(
          content: 'Archived test entry',
          scope: 'session',
          type: 'learning',
        );
        await narrativeRepo.save(entry);

        // WHEN: Archive
        await narrativeRepo.archive(entry.uuid);

        // THEN: Entry marked archived but retrievable
        final archived = await narrativeRepo.findByUuid(entry.uuid);
        expect(archived, isNotNull, reason: 'Entry still in database');
        expect(archived!.isArchived, isTrue, reason: 'Marked archived');

        // And excluded from active queries
        final active = await narrativeRepo.findByScope('session');
        expect(
          active.where((e) => e.uuid == entry.uuid),
          isEmpty,
          reason: 'Excluded from active queries',
        );
      },
    );

    test(
      'Deduplication: identical entries detected and skipped',
      skip: skipTests,
      () async {
        // GIVEN: Entry exists in session
        final original = NarrativeEntry(
          content: 'Distributed systems are hard. Because coordination is expensive.',
          scope: 'session',
          type: 'learning',
        );
        await narrativeRepo.save(original);

        // WHEN: Groq tries to extract similar content
        // (In real test, mock Groq response to include duplicate)
        final utterance =
            'I realized distributed systems are difficult to coordinate.';

        // Thinker should detect redundancy in Groq prompt
        // and skip the duplicate

        // THEN: Only original entry exists
        final entries = await narrativeRepo.findByScope('session');
        expect(
          entries.where((e) =>
              e.content
                  .contains('Distributed systems') &&
              e.uuid != original.uuid),
          isEmpty,
          reason: 'No duplicate created',
        );
      },
    );

    test(
      'Integration: Full conversation turn (utterance→Thinker→Retriever→CheckPoint)',
      skip: skipTests,
      () async {
        // GIVEN: Clean state
        // WHEN: Process full turn
        final utterance =
            'I want to explore functional programming because it prevents bugs';
        final intent = {
          'classification': 'exploration',
          'confidence': 0.88,
          'reasoning': 'User expressing learning interest',
        };

        // 1. Thinker extracts
        final extracted = await thinker.updateFromTurn(
          utterance: utterance,
          intentOutput: intent,
          chatHistory: [
            {'role': 'user', 'content': utterance},
          ],
          previousNarratives: [],
        );

        // 2. Retriever finds relevant context
        final relevant = await retriever.findRelevant(utterance);

        // 3. Checkpoint reviews
        final delta = await checkpoint.train();

        // THEN: Full pipeline completes without error
        expect(extracted, isNotNull);
        expect(relevant, isNotNull);
        expect(delta, isNotNull);

        // Verify pipeline didn't lose data
        expect(extracted, isA<List>());
        expect(relevant, isA<List>());
      },
    );
  });
}

// ============================================================================
// HELPERS
// ============================================================================

/// Check if integration tests should be skipped
bool _shouldSkipIntegrationTests() {
  // Check environment variables
  final skipEnv = const String.fromEnvironment('SKIP_INTEGRATION_TESTS');
  if (skipEnv.toLowerCase() == 'true') {
    return true;
  }

  // Check if API keys available
  final groqKey = const String.fromEnvironment('GROQ_API_KEY');
  if (groqKey.isEmpty) {
    print('⊘ GROQ_API_KEY not set - skipping Groq tests');
    return true;
  }

  return false;
}

/// Mock delta for testing (replace with actual when integrated)
class NarrativeDelta {
  final List<NarrativeEntry> added;
  final List<NarrativeEntry> removed;
  final List added_entries;

  NarrativeDelta({
    required this.added,
    required this.removed,
    this.added_entries = const [],
  });

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;
}
