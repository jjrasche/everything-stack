/// Smoke test for invocation-level semantic search (real Jina embeddings).
///
/// This test:
/// 1. Creates invocations with real Jina embeddings
/// 2. Indexes them via ChunkingService
/// 3. Searches via SemanticSearchService
/// 4. Captures embeddings for CI tests
///
/// Run with: flutter test integration_test/invocation_semantic_smoke_test.dart -d <platform>

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:get_it/get_it.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Invocation Semantic Search - Smoke Test (Real Embeddings)', () {
    late ChunkingService chunkingService;
    late SemanticSearchService searchService;
    late EmbeddingService embeddingService;
    late Map<String, List<double>> capturedEmbeddings;

    setUpAll(() async {
      // Get services from GetIt (initialized by app)
      chunkingService = GetIt.instance<ChunkingService>();
      searchService = GetIt.instance<SemanticSearchService>();
      embeddingService = EmbeddingService.instance;
      capturedEmbeddings = {};
    });

    /// Helper to create invocation with text content
    Invocation _createInvocation({
      required String componentType,
      required String text,
    }) {
      return Invocation(
        uuid: 'test-invocation-${DateTime.now().millisecondsSinceEpoch}',
        turnId: 'test-turn',
        componentType: componentType,
        output: {
          if (componentType == 'stt') 'transcription': text
          else 'response': text,
        },
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        adaptationContext: const {},
        metadata: {},
      );
    }

    /// Capture embedding from semantic search
    Future<void> _captureEmbedding(String text) async {
      try {
        final embedding = await embeddingService.generate(text);
        capturedEmbeddings[text] = embedding;
      } catch (e) {
        // Silently skip if capture fails
      }
    }

    test('Index short STT invocation', () async {
      final invocation = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      // Index the invocation
      final chunks = await chunkingService.indexEntity(invocation);

      expect(chunks, isNotEmpty);
      expect(chunks.length, greaterThan(0));

      // Capture embeddings from chunks
      for (final chunk in chunks) {
        await _captureEmbedding(chunk.text);
      }
    });

    test('Index medium LLM invocation', () async {
      final invocation = _createInvocation(
        componentType: 'llm',
        text:
            'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
            'Please prepare the presentation slides and bring the Q3 reports. '
            'We will discuss budget allocation and timeline for the new project.',
      );

      final chunks = await chunkingService.indexEntity(invocation);

      expect(chunks, isNotEmpty);
      expect(chunks.length, greaterThanOrEqualTo(2)); // Should have parent + children

      // Capture embeddings from chunks
      for (final chunk in chunks) {
        await _captureEmbedding(chunk.text);
      }
    });

    test('Index long conversation invocation', () async {
      final invocation = _createInvocation(
        componentType: 'llm',
        text:
            'Based on the quarterly review, we need to reallocate resources. '
            'The marketing team is performing well but engineering is understaffed. '
            'I recommend moving two people from operations to the backend team. '
            'The DevOps infrastructure needs improvement for scalability. '
            'We should also invest in monitoring tools and automated testing. '
            'Timeline: target completion by end of Q1. Budget estimate: \$150K. '
            'This will improve deployment frequency and reduce incident response time.',
      );

      final chunks = await chunkingService.indexEntity(invocation);

      expect(chunks, isNotEmpty);
      // Long text should produce multiple chunks
      expect(chunks.length, greaterThanOrEqualTo(3));

      // Capture embeddings from chunks
      for (final chunk in chunks) {
        await _captureEmbedding(chunk.text);
      }
    });

    test('Search returns semantic results', () async {
      // Query that should match our indexed content
      final results = await searchService.search(
        'meeting schedule conference room',
        limit: 5,
      );

      expect(results, isNotEmpty);
      // Should find chunks related to meeting
      expect(results.length, greaterThan(0));

      // Results should be ranked by similarity
      if (results.length > 1) {
        expect(
          results.first.similarity,
          greaterThanOrEqualTo(results.last.similarity),
        );
      }

      // Capture search query embedding
      await _captureEmbedding('meeting schedule conference room');
    });

    test('Search with entity type filter', () async {
      final results = await searchService.search(
        'deployment DevOps infrastructure',
        entityTypes: ['Invocation'],
        limit: 5,
      );

      expect(results, isNotEmpty);
      for (final result in results) {
        expect(result.sourceEntity, isNotNull);
      }

      await _captureEmbedding('deployment DevOps infrastructure');
    });

    test('Index multiple invocations and search across them', () async {
      final inv1 = _createInvocation(
        componentType: 'stt',
        text: 'Schedule a meeting with the design team',
      );
      final inv2 = _createInvocation(
        componentType: 'llm',
        text:
            'The design team will present mockups for the new dashboard. '
            'We need feedback on color scheme and layout.',
      );

      await chunkingService.indexEntity(inv1);
      await chunkingService.indexEntity(inv2);

      // Search should find content from both invocations
      final results = await searchService.search(
        'design team dashboard mockups',
        limit: 10,
      );

      expect(results, isNotEmpty);

      await _captureEmbedding('design team dashboard mockups');
    });

    tearDownAll(() async {
      // Save captured embeddings for CI tests
      if (capturedEmbeddings.isNotEmpty) {
        final json = jsonEncode(capturedEmbeddings);
        debugPrint('💾 Captured ${capturedEmbeddings.length} embeddings');
        debugPrint('📄 Save this to test/fixtures/invocation_embeddings.json:');
        debugPrint(json);
      }
    });
  });
}
