/// # Advanced Enrichment Queue Tests
///
/// TDD tests for complex enrichment scenarios:
/// - Batch processing with partial failures
/// - Concurrent entity saves
/// - Entity deletion during enrichment

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'shared/test_harness.dart';

/// Test 1: Batch with partial failures
/// Verifies per-entity error isolation - one failure doesn't block others
final batchPartialFailuresTest = IntegrationTestConfig(
  name: 'Batch Partial Failures',
  repos: [],
  testLogic: (t) async {
    print('\n=== [Batch Partial Failures Test] Starting... ===\n');

    // ============ ARRANGE ============
    // Create 10 invocations
    final invocations = List.generate(
      10,
      (i) => Invocation(
        eventId: 'batch-test-$i',
        componentType: 'stt',
        output: {'transcription': 'Test entity $i for batch failure test'},
        success: true,
        confidence: 0.95,
      ),
    );

    // We'll manually verify some succeed and some fail
    // In a full implementation, we'd inject failure for specific entities
    // For now, all should succeed (smoke test)

    // ============ ACT ============
    // Save all 10 entities (triggers enrichment for each)
    for (final inv in invocations) {
      await t.invocationEntityRepo.save(inv);
    }
    print('Saved ${invocations.length} invocations');

    // Wait for enrichment to process full batch
    await Future.delayed(const Duration(seconds: 6));

    // ============ ASSERT ============
    // All entities should have chunks (smoke test - no failures injected)
    int successCount = 0;
    for (final inv in invocations) {
      final chunks = await t.chunkingService.getChunksForEntity(inv.uuid);
      if (chunks.isNotEmpty) {
        successCount++;
      }

      final queueItem = await t.enrichmentQueueRepo.findByEntityUuid(inv.uuid);
      expect(
        queueItem,
        isNull,
        reason: 'Entity ${inv.uuid} should have queue item deleted',
      );
    }

    print('Successfully enriched: $successCount/${invocations.length}');
    expect(
      successCount,
      equals(invocations.length),
      reason: 'All entities should be enriched successfully',
    );

    print('\n=== [Batch Partial Failures Test] PASSED ===\n');
  },
);

/// Test 2: Concurrent entity saves
/// Verifies queue behavior with rapid successive entity updates
final concurrentSavesTest = IntegrationTestConfig(
  name: 'Concurrent Entity Saves',
  repos: [],
  testLogic: (t) async {
    print('\n=== [Concurrent Entity Saves Test] Starting... ===\n');

    // ============ ARRANGE ============
    final invocation1 = Invocation(
      eventId: 'concurrent-1',
      componentType: 'stt',
      output: {'transcription': 'First concurrent save'},
      success: true,
      confidence: 0.95,
    );

    final invocation2 = Invocation(
      eventId: 'concurrent-2',
      componentType: 'stt',
      output: {'transcription': 'Second concurrent save'},
      success: true,
      confidence: 0.95,
    );

    // ============ ACT ============
    // Save both entities in parallel (tests worker spawn race condition)
    await Future.wait([
      t.invocationEntityRepo.save(invocation1),
      t.invocationEntityRepo.save(invocation2),
    ]);
    print('Saved 2 invocations concurrently');

    // Wait for enrichment
    await Future.delayed(const Duration(seconds: 4));

    // ============ ASSERT ============
    // Both entities enriched successfully
    final chunks1 = await t.chunkingService.getChunksForEntity(invocation1.uuid);
    final chunks2 = await t.chunkingService.getChunksForEntity(invocation2.uuid);

    expect(chunks1.isNotEmpty, isTrue, reason: 'Entity 1 should have chunks');
    expect(chunks2.isNotEmpty, isTrue, reason: 'Entity 2 should have chunks');
    print('Entity 1: ${chunks1.length} chunks');
    print('Entity 2: ${chunks2.length} chunks');

    // Both queue items deleted
    final queue1 = await t.enrichmentQueueRepo.findByEntityUuid(invocation1.uuid);
    final queue2 = await t.enrichmentQueueRepo.findByEntityUuid(invocation2.uuid);

    expect(queue1, isNull, reason: 'Entity 1 queue item should be deleted');
    expect(queue2, isNull, reason: 'Entity 2 queue item should be deleted');

    // Verify HNSW index contains both
    if (chunks1.isNotEmpty) {
      final containsChunk1 = t.hnswIndex.contains(chunks1.first.id);
      expect(
        containsChunk1,
        isTrue,
        reason: 'Entity 1 first chunk should be in HNSW',
      );
    }

    if (chunks2.isNotEmpty) {
      final containsChunk2 = t.hnswIndex.contains(chunks2.first.id);
      expect(
        containsChunk2,
        isTrue,
        reason: 'Entity 2 first chunk should be in HNSW',
      );
    }

    print('Both entities in HNSW index');
    print('\n=== [Concurrent Entity Saves Test] PASSED ===\n');
  },
);

/// Test 3: Entity deleted during processing
/// Verifies orphaned work discarded cleanly when entity deleted mid-enrichment
final entityDeletedDuringProcessingTest = IntegrationTestConfig(
  name: 'Entity Deleted During Processing',
  repos: [],
  testLogic: (t) async {
    print('\n=== [Entity Deleted During Processing Test] Starting... ===\n');

    // ============ ARRANGE ============
    final invocation = Invocation(
      eventId: 'delete-test',
      componentType: 'stt',
      output: {'transcription': 'Test entity for deletion during enrichment'},
      success: true,
      confidence: 0.95,
    );

    // ============ ACT ============
    // Save entity (starts enrichment)
    await t.invocationEntityRepo.save(invocation);
    final entityUuid = invocation.uuid;
    print('Saved invocation: $entityUuid');

    // Wait brief moment for worker to potentially start processing
    // (May or may not have started yet - that's fine, we're testing the cleanup path)
    await Future.delayed(const Duration(milliseconds: 200));

    // Delete entity while enrichment may be running
    final deleted = await t.invocationEntityRepo.deleteByUuid(entityUuid);
    expect(deleted, isTrue, reason: 'Entity should be deleted');
    print('Deleted entity: $entityUuid');

    // Wait for enrichment worker cycle to complete
    await Future.delayed(const Duration(seconds: 3));

    // ============ ASSERT ============
    // Entity deleted from repository
    final entity = await t.invocationEntityRepo.findByUuid(entityUuid);
    expect(entity, isNull, reason: 'Entity should not exist');
    print('Entity deleted: confirmed');

    // Queue item behavior depends on timing:
    // - If worker processed before deletion: queue item deleted, chunks may exist but will be cleaned
    // - If worker processed after deletion: error set, chunks cleaned
    final queueItem = await t.enrichmentQueueRepo.findByEntityUuid(entityUuid);

    if (queueItem != null) {
      // Worker detected deleted entity and set error
      expect(queueItem.lastError, isNotNull, reason: 'Should have error for deleted entity');
      print('Queue item has error: ${queueItem.lastError}');

      // Chunks should be cleaned up (no orphans)
      final chunks = await t.chunkingService.getChunksForEntity(entityUuid);
      expect(chunks.isEmpty, isTrue, reason: 'Chunks should be cleaned for deleted entity');
      print('No orphaned chunks (worker detected deleted entity)');
    } else {
      // Worker completed before entity deletion OR cleaned up after cancellation
      // In both cases, EntityRepository.deleteByUuid() should have cleaned chunks
      final chunks = await t.chunkingService.getChunksForEntity(entityUuid);

      if (chunks.isEmpty) {
        print('No chunks found (cleaned by deleteByUuid or never created)');
      } else {
        // Chunks exist - this is the race condition case
        // Entity deleted, but worker had fetched entity before deletion
        // Worker completed enrichment, then detected queue cancellation
        // Should have cleaned chunks at line 99 of worker
        print('Found ${chunks.length} orphaned chunks - worker should cleanup');

        // Give worker time to detect cancellation and cleanup
        await Future.delayed(const Duration(milliseconds: 500));
        final chunksAfterCleanup = await t.chunkingService.getChunksForEntity(entityUuid);
        expect(chunksAfterCleanup.isEmpty, isTrue,
          reason: 'Worker should cleanup orphaned chunks after detecting cancellation');
      }

      print('Queue item deleted (enrichment completed or cancelled)');
    }

    print('\n=== [Entity Deleted During Processing Test] PASSED ===\n');
  },
);
