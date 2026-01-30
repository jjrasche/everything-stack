/// # Invocation Semantic Search Test
///
/// Tests semantic search infrastructure:
/// - Chunking strategy
/// - HNSW indexing
/// - Semantic search ranking
/// - Entity filtering
/// - Index consistency
///
/// ## Architecture Under Test
/// ```
/// Invocation → ChunkingService → Chunks → HNSW Index → SemanticSearchService
/// ```

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';

final invocationSemanticTest = IntegrationTestConfig(
  name: 'Invocation Semantic Search',

  repos: [
    InvocationRepository<Invocation>,
  ],

  // No mockResponses - this test doesn't need Coordinator

  testLogic: (t) async {
    // Get services from GetIt
    final chunkingService = GetIt.instance<ChunkingService>();
    final searchService = GetIt.instance<SemanticSearchService>();

  // Helper to create invocation with text content
  Invocation _createInvocation({
    required String componentType,
    required String text,
  }) {
    return Invocation(
      eventId: 'test-event-${DateTime.now().millisecondsSinceEpoch}',
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

  final invocation1 = _createInvocation(
    componentType: 'stt',
    text: 'What time is the meeting tomorrow',
  );

  final chunks1 = await chunkingService.indexEntity(invocation1);

  expect(chunks1, isNotEmpty);
  expect(chunks1.length, greaterThan(0));

  final invocation2 = _createInvocation(
    componentType: 'llm',
    text: 'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
        'Please prepare the presentation slides and bring the Q3 reports. '
        'We will discuss budget allocation and timeline for the new project.',
  );

  final chunks2 = await chunkingService.indexEntity(invocation2);

  expect(chunks2, isNotEmpty);
  expect(chunks2.length, greaterThanOrEqualTo(2));

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

  // ========== TEST 4-6: Chunk Validation ==========

  for (final chunk in chunks1) {
    expect(chunk.text, isNotEmpty);
    expect(chunk.text.isNotEmpty, isTrue);
  }

  // Verify that chunks are indexed (by checking search returns results)
  final searchTest = await searchService.search('test query', limit: 5);
  expect(searchTest, isNotNull);

  final retrievedChunk = await chunkingService.getChunkById(chunks1.first.id);
  expect(retrievedChunk, isNotNull);
  expect(retrievedChunk?.text, equals(chunks1.first.text));

  // ========== TEST 7-9: Index Management ==========

  final entityChunks = await chunkingService.getChunksForEntity(invocation1.uuid);
  expect(entityChunks, isNotEmpty);
  expect(entityChunks.map((c) => c.sourceEntityId).toSet().first, equals(invocation1.uuid));

  final chunkToDelete = chunks1.first;
  await chunkingService.deleteByEntityId(invocation1.uuid);
  final deletedChunk = await chunkingService.getChunkById(chunkToDelete.id);
  expect(deletedChunk, isNull);

  // Re-index for remaining tests
  await chunkingService.indexEntity(invocation1);

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

  // ========== TEST 10-12: Search Functionality ==========

  for (final result in results) {
    expect(result.chunk, isNotNull);
    expect(result.chunk.sourceEntityId, isNotEmpty);
  }

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

  final filteredResults = await searchService.search(
    'design team dashboard',
    entityTypes: ['Invocation'],
    limit: 5,
  );

  expect(filteredResults, isNotEmpty);
  for (final result in filteredResults) {
    expect(result.chunk, isNotNull);
  }

  // ========== TEST 13-15: Advanced Operations ==========

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

  // Index
  final cycleInv1 = _createInvocation(componentType: 'stt', text: 'Test cycle one');
  final cycleChunks1 = await chunkingService.indexEntity(cycleInv1);
  expect(cycleChunks1, isNotEmpty);

  // Delete
  await chunkingService.deleteByEntityId(cycleInv1.uuid);

  // Re-index
  final cycleChunks2 = await chunkingService.indexEntity(cycleInv1);
  expect(cycleChunks2, isNotEmpty);


  // Final comprehensive search across all indexed data
  final finalSearch = await searchService.search(
    'test comprehensive search',
    limit: 10,
  );
  expect(finalSearch, isNotNull);

  },
);
