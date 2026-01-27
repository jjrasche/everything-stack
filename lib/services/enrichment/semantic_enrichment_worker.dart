/// # SemanticEnrichmentWorker
///
/// ## What it does
/// Processes semantic enrichment for entities.
/// Chunks entity content, generates embeddings, and inserts into HNSW index.
///
/// ## Design
/// - Sequential processing (N=1) - HNSW not thread-safe
/// - Fetches entities just-in-time to minimize staleness
/// - Race condition handling via re-fetch before save
/// - Delegates all semantic work to ChunkingService.indexEntity()

import '../../core/enrichment_queue_item.dart';
import '../../core/enrichment_queue_repository.dart';
import '../../core/repository_registry.dart';
import '../../patterns/semantic_indexable.dart';
import '../chunking_service.dart';
import 'enrichment_worker.dart';

class SemanticEnrichmentWorker implements EnrichmentWorker {
  final ChunkingService chunkingService;
  final RepositoryRegistry repoRegistry;

  SemanticEnrichmentWorker({
    required this.chunkingService,
    required this.repoRegistry,
  });

  @override
  String get stepType => 'semantic_enrichment';

  @override
  List<String> get requiredSteps => []; // No dependencies

  @override
  Future<List<EnrichmentQueueItem>> getReadyItems(
    EnrichmentQueueRepository queueRepo,
  ) async {
    return queueRepo.findReadyForStep(stepType);
  }

  @override
  Future<void> processBatch(
    List<EnrichmentQueueItem> items,
    EnrichmentQueueRepository queueRepo,
  ) async {
    // SEQUENTIAL processing (N=1) - HNSW not thread-safe
    for (final item in items) {
      await _processItem(item, queueRepo);
    }
  }

  Future<void> _processItem(
    EnrichmentQueueItem item,
    EnrichmentQueueRepository queueRepo,
  ) async {
    // 1. Mark as processing (lock)
    item.currentStep = stepType;
    item.pendingSteps.remove(stepType);
    await queueRepo.save(item);

    try {
      // 2. Fetch entity fresh (minimizes staleness)
      final entity = await repoRegistry.fetchEntity(
        item.entityUuid,
        item.entityType,
      );

      if (entity == null) {
        // Entity was deleted during enrichment
        item.lastError =
            'Entity not found: ${item.entityType}:${item.entityUuid}';
        item.currentStep = null;
        await queueRepo.save(item);
        return;
      }

      // 3. Verify entity is SemanticIndexable
      if (entity is! SemanticIndexable) {
        item.lastError =
            'Entity ${item.entityType} does not implement SemanticIndexable';
        item.currentStep = null;
        await queueRepo.save(item);
        return;
      }

      // 4. Do the work (HNSW mutations happen here)
      // CRITICAL: Delete old chunks first to ensure idempotency (restart-safe)
      // If app crashed mid-processing, old chunks may exist from previous attempt
      await chunkingService.deleteByEntityId(item.entityUuid);

      // ChunkingService handles: chunking, embedding, HNSW insert
      await chunkingService.indexEntity(entity);

      // 5. RACE CONDITION CHECK: Re-fetch item before marking complete
      final stillValid = await queueRepo.findByUuid(item.uuid);
      if (stillValid == null) {
        // Item was cancelled during processing (entity was updated or deleted)
        // Clean up orphaned chunks - entity may have been deleted, won't be re-enriched
        await chunkingService.deleteByEntityId(item.entityUuid);
        return;
      }

      // 6. Mark completed
      stillValid.completedSteps.add(stepType);
      stillValid.currentStep = null;

      if (stillValid.isComplete) {
        // All enrichment done - delete queue item
        await queueRepo.delete(stillValid);
      } else {
        // More steps pending - save updated item
        await queueRepo.save(stillValid);
      }
    } catch (e, stackTrace) {
      // Handle errors - re-fetch item before updating (may have been cancelled)
      final stillValid = await queueRepo.findByUuid(item.uuid);
      if (stillValid != null) {
        stillValid.lastError = e.toString();
        stillValid.currentStep = null;
        stillValid.retries++;
        await queueRepo.save(stillValid);
      }
      // Log error for debugging
      // ignore: avoid_print
      print('SemanticEnrichmentWorker error for ${item.entityUuid}: $e');
      // ignore: avoid_print
      print(stackTrace);
    }
  }
}
