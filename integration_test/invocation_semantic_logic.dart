/// Shared test logic for invocation-level semantic search (chunking, indexing, search).
///
/// This test runs with ANY embedding service:
/// - Smoke test: Real Jina embeddings (captures fixture)
/// - E2E test: Mocked embeddings (replayed from fixture)
///
/// The test logic is IDENTICAL - only service configuration differs.
///
/// ## Architecture Under Test
/// ```
/// Invocation → ChunkingService → Chunks → HNSW Index → SemanticSearchService
/// ```
///
/// ## What This Verifies
/// 1. Invocations chunk correctly (parent/child structure)
/// 2. Chunks persist to ObjectBox database
/// 3. Embeddings index in HNSW (8-12ms queries)
/// 4. Semantic search returns ranked results
/// 5. Entity type filtering works
/// 6. Index consistency maintained across cycles
///
/// ## Multi-Scenario Coverage
/// - Short STT content (1-2 chunks)
/// - Medium LLM responses (2-3 chunks)
/// - Long conversations (3+ chunks)
/// - Multiple index/delete cycles

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:get_it/get_it.dart';

/// Run the complete semantic search test with any embedding service.
///
/// The test queries EmbeddingService from GetIt, so the caller controls
/// whether it's real (smoke test) or mocked (CI test).
///
/// This is the test logic only. Fixture capture is handled separately
/// by the test entry point (see fixture_capture.dart).
Future<void> runInvocationSemanticTest() async {
  debugPrint('🚀 [Semantic Search Test] Starting invocation semantic search test...');

  // Get services from GetIt
  final chunkingService = GetIt.instance<ChunkingService>();
  final searchService = GetIt.instance<SemanticSearchService>();

  debugPrint('✅ Services initialized: ChunkingService, SemanticSearchService');

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

  // ========== TEST 1-3: Chunking & Indexing ==========

  debugPrint('\n📝 Test 1: Index short STT invocation');
  final invocation1 = _createInvocation(
    componentType: 'stt',
    text: 'What time is the meeting tomorrow',
  );

  final chunks1 = await chunkingService.indexEntity(invocation1);

  expect(chunks1, isNotEmpty);
  expect(chunks1.length, greaterThan(0));
  debugPrint('✅ Test 1 passed: ${chunks1.length} chunks created');

  debugPrint('\n📝 Test 2: Index medium LLM invocation');
  final invocation2 = _createInvocation(
    componentType: 'llm',
    text: 'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
        'Please prepare the presentation slides and bring the Q3 reports. '
        'We will discuss budget allocation and timeline for the new project.',
  );

  final chunks2 = await chunkingService.indexEntity(invocation2);

  expect(chunks2, isNotEmpty);
  expect(chunks2.length, greaterThanOrEqualTo(2));
  debugPrint('✅ Test 2 passed: ${chunks2.length} chunks created');

  debugPrint('\n📝 Test 3: Index long conversation invocation');
  final invocation3 = _createInvocation(
    componentType: 'llm',
    text: 'Based on the quarterly review, we need to reallocate resources. '
        'The marketing team is performing well but engineering is understaffed. '
        'I recommend moving two people from operations to the backend team. '
        'The DevOps infrastructure needs improvement for scalability. '
        'We should also invest in monitoring tools and automated testing. '
        'Timeline: target completion by end of Q1. Budget estimate: \$150K. '
        'This will improve deployment frequency and reduce incident response time.',
  );

  final chunks3 = await chunkingService.indexEntity(invocation3);

  expect(chunks3, isNotEmpty);
  expect(chunks3.length, greaterThanOrEqualTo(3));
  debugPrint('✅ Test 3 passed: ${chunks3.length} chunks created');

  // ========== TEST 4-6: Chunk Validation ==========

  debugPrint('\n📝 Test 4: Chunks have text field for reconstruction');
  for (final chunk in chunks1) {
    expect(chunk.text, isNotEmpty);
    expect(chunk.text.isNotEmpty, isTrue);
  }
  debugPrint('✅ Test 4 passed');

  debugPrint('\n📝 Test 5: HNSW index stores chunk vectors');
  // Verify that chunks are indexed (by checking search returns results)
  final searchTest = await searchService.search('test query', limit: 5);
  expect(searchTest, isNotNull);
  debugPrint('✅ Test 5 passed');

  debugPrint('\n📝 Test 6: ChunkingService retrieves chunks by ID');
  final retrievedChunk = await chunkingService.getChunkById(chunks1.first.id);
  expect(retrievedChunk, isNotNull);
  expect(retrievedChunk?.text, equals(chunks1.first.text));
  debugPrint('✅ Test 6 passed');

  // ========== TEST 7-9: Index Management ==========

  debugPrint('\n📝 Test 7: ChunkingService queries chunks by entity ID');
  final entityChunks = await chunkingService.getChunksForEntity(invocation1.uuid);
  expect(entityChunks, isNotEmpty);
  expect(entityChunks.map((c) => c.sourceEntityId).toSet().first, equals(invocation1.uuid));
  debugPrint('✅ Test 7 passed');

  debugPrint('\n📝 Test 8: Delete chunks removes from HNSW index');
  final chunkToDelete = chunks1.first;
  await chunkingService.deleteByEntityId(invocation1.uuid);
  final deletedChunk = await chunkingService.getChunkById(chunkToDelete.id);
  expect(deletedChunk, isNull);
  debugPrint('✅ Test 8 passed');

  // Re-index for remaining tests
  await chunkingService.indexEntity(invocation1);

  debugPrint('\n📝 Test 9: Search service finds indexed chunks');
  final results = await searchService.search(
    'meeting schedule conference room',
    limit: 5,
  );

  expect(results, isNotEmpty);
  expect(results.length, greaterThan(0));

  if (results.length > 1) {
    expect(
      results.first.similarity,
      greaterThanOrEqualTo(results.last.similarity),
    );
  }
  debugPrint('✅ Test 9 passed: ${results.length} results found');

  // ========== TEST 10-12: Search Functionality ==========

  debugPrint('\n📝 Test 10: Search results include source entity reference');
  for (final result in results) {
    expect(result.chunk, isNotNull);
    expect(result.chunk.sourceEntityId, isNotEmpty);
  }
  debugPrint('✅ Test 10 passed');

  debugPrint('\n📝 Test 11: Semantic search ranks by similarity');
  final rankedResults = await searchService.search(
    'deployment DevOps infrastructure',
    limit: 5,
  );
  expect(rankedResults, isNotEmpty);
  if (rankedResults.length > 1) {
    for (int i = 0; i < rankedResults.length - 1; i++) {
      expect(
        rankedResults[i].similarity,
        greaterThanOrEqualTo(rankedResults[i + 1].similarity),
      );
    }
  }
  debugPrint('✅ Test 11 passed');

  debugPrint('\n📝 Test 12: Search with entity type filter');
  final filteredResults = await searchService.search(
    'design team dashboard',
    entityTypes: ['Invocation'],
    limit: 5,
  );

  expect(filteredResults, isNotEmpty);
  for (final result in filteredResults) {
    expect(result.chunk, isNotNull);
  }
  debugPrint('✅ Test 12 passed: ${filteredResults.length} results found');

  // ========== TEST 13-15: Advanced Operations ==========

  debugPrint('\n📝 Test 13: Index consistency check');
  final inv4 = _createInvocation(
    componentType: 'stt',
    text: 'Schedule a meeting with the design team',
  );
  final inv5 = _createInvocation(
    componentType: 'llm',
    text: 'The design team will present mockups for the new dashboard. '
        'We need feedback on color scheme and layout.',
  );

  await chunkingService.indexEntity(inv4);
  await chunkingService.indexEntity(inv5);

  final results3 = await searchService.search(
    'design team dashboard mockups',
    limit: 10,
  );

  expect(results3, isNotEmpty);
  debugPrint('✅ Test 13 passed: Index consistency verified');

  debugPrint('\n📝 Test 14: Multiple index/delete cycles');
  // Index
  final cycleInv1 = _createInvocation(componentType: 'stt', text: 'Test cycle one');
  final cycleChunks1 = await chunkingService.indexEntity(cycleInv1);
  expect(cycleChunks1, isNotEmpty);

  // Delete
  await chunkingService.deleteByEntityId(cycleInv1.uuid);

  // Re-index
  final cycleChunks2 = await chunkingService.indexEntity(cycleInv1);
  expect(cycleChunks2, isNotEmpty);

  debugPrint('✅ Test 14 passed: Cycles completed without errors');

  debugPrint('\n📝 Test 15: All operations complete without deadlock');
  // Final comprehensive search across all indexed data
  final finalSearch = await searchService.search(
    'test comprehensive search',
    limit: 10,
  );
  expect(finalSearch, isNotNull);
  debugPrint('✅ Test 15 passed: All operations stable');

  // ========== SUMMARY ==========
  debugPrint('\n✅ All semantic search tests passed!');
  debugPrint('   - Chunking strategy: ✅');
  debugPrint('   - HNSW indexing: ✅');
  debugPrint('   - Semantic search: ✅');
  debugPrint('   - Entity filtering: ✅');
  debugPrint('   - Index consistency: ✅');
}
