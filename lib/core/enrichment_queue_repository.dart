/// # EnrichmentQueueRepository
///
/// ## What it does
/// Repository for EnrichmentQueueItem entities.
/// Provides specialized queries for the enrichment runner and workers.
///
/// ## Query Operations
/// - findByEntityUuid(): Find queue item for a specific entity
/// - findReadyForStep(): Find items ready for a specific enrichment step
/// - findReadyForStepWithDeps(): Find items with dependencies satisfied
/// - findStuckItems(): Find items stuck in processing (for recovery)
///
/// ## Usage
/// ```dart
/// final repo = EnrichmentQueueRepository(adapter: adapter);
/// final items = await repo.findReadyForStep('semantic_enrichment');
/// ```

import 'enrichment_queue_item.dart';

/// Abstract interface for EnrichmentQueueItem persistence
abstract class EnrichmentQueueAdapter {
  /// Find queue item by UUID
  Future<EnrichmentQueueItem?> findByUuid(String uuid);

  /// Find queue item for a specific entity
  Future<EnrichmentQueueItem?> findByEntityUuid(String entityUuid);

  /// Find all items with a step in pendingSteps AND currentStep is null
  Future<List<EnrichmentQueueItem>> findReadyForStep(String stepType);

  /// Find items ready for step with all required steps completed
  Future<List<EnrichmentQueueItem>> findReadyForStepWithDeps(
    String stepType,
    List<String> requiredSteps,
  );

  /// Find items stuck in processing (currentStep not null)
  Future<List<EnrichmentQueueItem>> findStuckItems();

  /// Find all items
  Future<List<EnrichmentQueueItem>> findAll();

  /// Save queue item
  Future<EnrichmentQueueItem> save(EnrichmentQueueItem item);

  /// Delete queue item
  Future<bool> delete(EnrichmentQueueItem item);

  /// Delete queue item by UUID
  Future<bool> deleteByUuid(String uuid);

  /// Close adapter and release resources
  Future<void> close();
}

/// EnrichmentQueueRepository
///
/// Provides access to EnrichmentQueueItem entities with specialized
/// queries for the enrichment system.
class EnrichmentQueueRepository {
  final EnrichmentQueueAdapter adapter;

  EnrichmentQueueRepository({required this.adapter});

  // ============ CRUD ============

  /// Find queue item by UUID
  Future<EnrichmentQueueItem?> findByUuid(String uuid) {
    return adapter.findByUuid(uuid);
  }

  /// Find queue item for a specific entity
  Future<EnrichmentQueueItem?> findByEntityUuid(String entityUuid) {
    return adapter.findByEntityUuid(entityUuid);
  }

  /// Find all queue items
  Future<List<EnrichmentQueueItem>> findAll() {
    return adapter.findAll();
  }

  /// Save queue item
  Future<EnrichmentQueueItem> save(EnrichmentQueueItem item) {
    item.updatedAt = DateTime.now();
    return adapter.save(item);
  }

  /// Delete queue item
  Future<bool> delete(EnrichmentQueueItem item) {
    return adapter.delete(item);
  }

  /// Delete queue item by UUID
  Future<bool> deleteByUuid(String uuid) {
    return adapter.deleteByUuid(uuid);
  }

  // ============ Worker Queries ============

  /// Find items ready for a specific enrichment step.
  ///
  /// Returns items where:
  /// - pendingSteps contains [stepType]
  /// - currentStep is null (not being processed)
  Future<List<EnrichmentQueueItem>> findReadyForStep(String stepType) {
    return adapter.findReadyForStep(stepType);
  }

  /// Find items ready for step with dependencies satisfied.
  ///
  /// Returns items where:
  /// - pendingSteps contains [stepType]
  /// - currentStep is null (not being processed)
  /// - completedSteps contains all [requiredSteps]
  Future<List<EnrichmentQueueItem>> findReadyForStepWithDeps(
    String stepType,
    List<String> requiredSteps,
  ) {
    return adapter.findReadyForStepWithDeps(stepType, requiredSteps);
  }

  // ============ Recovery Queries ============

  /// Find items stuck in processing (for startup recovery).
  ///
  /// Returns items where currentStep is not null, indicating the app
  /// crashed while processing and needs to reset them.
  Future<List<EnrichmentQueueItem>> findStuckItems() {
    return adapter.findStuckItems();
  }

  // ============ Cleanup ============

  /// Close adapter and release resources
  Future<void> close() {
    return adapter.close();
  }
}
