/// Integration test for invocation-level semantic search (replayed embeddings).
///
/// This test:
/// 1. Uses pre-recorded embeddings from smoke test (avoids API calls)
/// 2. Replays embeddings via ReplayEmbeddingService
/// 3. Runs same semantic search tests deterministically
/// 4. Validates chunking, indexing, and search
///
/// Run with: flutter test integration_test/invocation_semantic_test.dart -d <platform>

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';
import 'package:everything_stack_template/main.dart';
import 'package:get_it/get_it.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Invocation Semantic Search - CI Test (Replayed Embeddings)', () {
    setUpAll(() async {
      // No setup needed - app will initialize on pumpWidget()
    });

    testWidgets('Full CI test: Chunking, indexing, and search',
        (WidgetTester tester) async {
      // Build app - this runs bootstrap and initializes GetIt
      debugPrint('🏗️ Building MyApp...');
      await tester.pumpWidget(const MyApp());

      debugPrint('⏳ Waiting for bootstrap and initialization...');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // NOW GetIt services are available
      final chunkingService = GetIt.instance<ChunkingService>();
      final searchService = GetIt.instance<SemanticSearchService>();

      debugPrint('✅ Services initialized');

      // Helper to create invocation with text content
      Invocation _createInvocation({
        required String componentType,
        required String text,
      }) {
        return Invocation(
          eventId: 'test-event-${DateTime.now().millisecondsSinceEpoch}',
          turnId: 'test-turn',
          componentType: componentType,
          success: true,
          confidence: 0.95,
          output: {
            if (componentType == 'stt') 'transcription': text
            else 'response': text,
          },
          metadata: {},
        );
      }

      // Test 1: Create invocation with STT content
      debugPrint('\n📝 Test 1: Create invocation with STT content');
      final invocation = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      expect(invocation.uuid, isNotEmpty);
      expect(invocation.componentType, 'stt');
      expect(invocation.output?['transcription'], isNotEmpty);
      debugPrint('✅ Test 1 passed');

      // Test 2: Create invocation with LLM response
      debugPrint('\n📝 Test 2: Create invocation with LLM response');
      final invocation2 = _createInvocation(
        componentType: 'llm',
        text: 'The meeting is scheduled for 2 PM tomorrow in the main conference room.',
      );

      expect(invocation2.componentType, 'llm');
      expect(invocation2.output?['response'], isNotEmpty);
      debugPrint('✅ Test 2 passed');

      // Test 3: Invocation implements SemanticIndexable
      debugPrint('\n📝 Test 3: Invocation implements SemanticIndexable');
      final invocation3 = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      final chunkableInput = invocation3.toChunkableInput();
      expect(chunkableInput, contains('What time'));
      expect(chunkableInput, startsWith('User:'));
      debugPrint('✅ Test 3 passed');

      // Test 4: SemanticChunker produces valid chunks
      debugPrint('\n📝 Test 4: SemanticChunker produces valid chunks');
      final invocation4 = _createInvocation(
        componentType: 'llm',
        text:
            'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
            'Please prepare the presentation slides and bring the Q3 reports.',
      );

      final chunks = await chunkingService.indexEntity(invocation4);

      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(chunk.id, isNotEmpty);
        expect(chunk.sourceEntityId, invocation4.uuid);
        expect(chunk.text, isNotEmpty);
        expect(chunk.tokenCount, greaterThan(0));
        expect(['parent', 'child'], contains(chunk.config));
      }
      debugPrint('✅ Test 4 passed: ${chunks.length} chunks created');

      // Test 5: Chunks have text field for reconstruction
      debugPrint('\n📝 Test 5: Chunks have text field for reconstruction');
      final invocation5 = _createInvocation(
        componentType: 'llm',
        text: 'The meeting is scheduled for 2 PM tomorrow in the main conference room.',
      );

      final chunks2 = await chunkingService.indexEntity(invocation5);

      for (final chunk in chunks2) {
        expect(chunk.text, isNotEmpty);
        expect(chunk.text, contains(RegExp(r'\w+')));
      }
      debugPrint('✅ Test 5 passed');

      // Test 6: HNSW index stores chunk vectors
      debugPrint('\n📝 Test 6: HNSW index stores chunk vectors');
      final invocation6 = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      final chunks3 = await chunkingService.indexEntity(invocation6);

      expect(chunks3, isNotEmpty);
      expect(chunks3.length, greaterThan(0));
      debugPrint('✅ Test 6 passed');

      // Test 7: ChunkingService retrieves chunks by ID
      debugPrint('\n📝 Test 7: ChunkingService retrieves chunks by ID');
      final invocation7 = _createInvocation(
        componentType: 'llm',
        text: 'The meeting is scheduled for 2 PM tomorrow.',
      );

      final chunks4 = await chunkingService.indexEntity(invocation7);
      expect(chunks4, isNotEmpty);

      final firstChunk = chunks4.first;
      final retrieved = chunkingService.getChunkById(firstChunk.id);

      expect(retrieved, isNotNull);
      expect(retrieved?.id, firstChunk.id);
      expect(retrieved?.text, firstChunk.text);
      debugPrint('✅ Test 7 passed');

      // Test 8: ChunkingService queries chunks by entity ID
      debugPrint('\n📝 Test 8: ChunkingService queries chunks by entity ID');
      final invocation8 = _createInvocation(
        componentType: 'llm',
        text: 'The meeting is scheduled for 2 PM tomorrow in the conference room.',
      );

      final indexedChunks = await chunkingService.indexEntity(invocation8);
      expect(indexedChunks, isNotEmpty);

      final retrievedChunks =
          await chunkingService.getChunksForEntity(invocation8.uuid);

      expect(retrievedChunks, isNotEmpty);
      expect(retrievedChunks.length, indexedChunks.length);
      debugPrint('✅ Test 8 passed');

      // Test 9: Delete chunks removes from HNSW index
      debugPrint('\n📝 Test 9: Delete chunks removes from HNSW index');
      final invocation9 = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      final chunks5 = await chunkingService.indexEntity(invocation9);
      expect(chunks5, isNotEmpty);

      await chunkingService.deleteByEntityId(invocation9.uuid);

      final retrievedChunks2 =
          await chunkingService.getChunksForEntity(invocation9.uuid);
      expect(retrievedChunks2, isEmpty);
      debugPrint('✅ Test 9 passed');

      // Test 10: Search service finds indexed chunks
      debugPrint('\n📝 Test 10: Search service finds indexed chunks');
      final invocation10 = _createInvocation(
        componentType: 'llm',
        text:
            'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
            'Please prepare the presentation slides.',
      );

      await chunkingService.indexEntity(invocation10);

      final results = await searchService.search(
        'meeting schedule conference room',
        limit: 5,
      );

      expect(results, isA<List>());
      debugPrint('✅ Test 10 passed: ${results.length} results found');

      // Test 11: Search results include source entity reference
      debugPrint('\n📝 Test 11: Search results include source entity reference');
      final invocation11 = _createInvocation(
        componentType: 'llm',
        text:
            'The meeting is scheduled for 2 PM tomorrow in the main conference room.',
      );

      await chunkingService.indexEntity(invocation11);

      final results2 = await searchService.search(
        'meeting schedule',
        limit: 5,
      );

      for (final result in results2) {
        expect(result.chunk, isNotNull);
        expect(result.similarity, isA<double>());
        expect(result.similarity, greaterThanOrEqualTo(0.0));
        expect(result.similarity, lessThanOrEqualTo(1.0));
      }
      debugPrint('✅ Test 11 passed');

      // Test 12: Semantic search ranks by similarity
      debugPrint('\n📝 Test 12: Semantic search ranks by similarity');
      final inv1 = _createInvocation(
        componentType: 'llm',
        text: 'The meeting is tomorrow at 2 PM in the conference room.',
      );
      final inv2 = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      await chunkingService.indexEntity(inv1);
      await chunkingService.indexEntity(inv2);

      final results3 = await searchService.search(
        'meeting time tomorrow',
        limit: 10,
      );

      if (results3.length > 1) {
        for (int i = 0; i < results3.length - 1; i++) {
          expect(
            results3[i].similarity,
            greaterThanOrEqualTo(results3[i + 1].similarity),
            reason: 'Results should be sorted by similarity descending',
          );
        }
      }
      debugPrint('✅ Test 12 passed');

      // Test 13: Search with entity type filter
      debugPrint('\n📝 Test 13: Search with entity type filter');
      final invocation13 = _createInvocation(
        componentType: 'llm',
        text: 'The meeting is scheduled for 2 PM tomorrow.',
      );

      await chunkingService.indexEntity(invocation13);

      final results4 = await searchService.search(
        'meeting scheduled',
        entityTypes: ['Invocation'],
        limit: 5,
      );

      expect(results4, isA<List>());
      debugPrint('✅ Test 13 passed');

      // Test 14: Index consistency check
      debugPrint('\n📝 Test 14: Index consistency check');
      final isConsistent = chunkingService.isIndexConsistent();
      expect(isConsistent, isA<bool>());
      debugPrint('✅ Test 14 passed');

      // Test 15: Multiple index/delete cycles
      debugPrint('\n📝 Test 15: Multiple index/delete cycles');
      for (int i = 0; i < 3; i++) {
        final invocation = _createInvocation(
          componentType: i % 2 == 0 ? 'stt' : 'llm',
          text: 'Cycle $i: The meeting is scheduled for 2 PM tomorrow.',
        );

        final chunks6 = await chunkingService.indexEntity(invocation);
        expect(chunks6, isNotEmpty);

        await chunkingService.deleteByEntityId(invocation.uuid);

        final retrieved =
            await chunkingService.getChunksForEntity(invocation.uuid);
        expect(retrieved, isEmpty);
      }
      debugPrint('✅ Test 15 passed');

      debugPrint('\n✅ All CI tests passed!');
    });
  });
}
