/// # EnrichmentWorker Interface
///
/// ## What it does
/// Interface for workers that process enrichment steps.
/// Each worker handles one type of enrichment (e.g., semantic, categorization).
///
/// ## Design
/// - Worker fetches entities just-in-time (minimizes staleness)
/// - Worker handles race condition checks (re-fetch QueueItem before saving)
/// - Worker delegates dependency checking to getReadyItems()
/// - Sequential processing (N=1) due to HNSW thread-safety constraints
///
/// ## Usage
/// ```dart
/// class SemanticEnrichmentWorker implements EnrichmentWorker {
///   @override
///   String get stepType => 'semantic_enrichment';
///
///   @override
///   List<String> get requiredSteps => []; // No dependencies
///
///   @override
///   Future<void> processBatch(items, queueRepo) async {
///     for (final item in items) {
///       // 1. Mark as processing
///       // 2. Fetch entity fresh
///       // 3. Do the work
///       // 4. Race condition check
///       // 5. Mark completed
///     }
///   }
/// }
/// ```

import '../../core/enrichment_queue_item.dart';
import '../../core/enrichment_queue_repository.dart';

/// Interface for enrichment workers.
abstract class EnrichmentWorker {
  /// The type of enrichment step this worker handles.
  /// Example: 'semantic_enrichment', 'categorization'
  String get stepType;

  /// Steps that must be completed before this worker can run.
  /// Example: categorization might require ['semantic_enrichment'] first.
  List<String> get requiredSteps;

  /// Query for items this worker can process.
  ///
  /// Default implementation uses the deps-aware query.
  /// Returns items where:
  /// - pendingSteps contains stepType
  /// - currentStep is null (not being processed)
  /// - completedSteps contains all requiredSteps
  Future<List<EnrichmentQueueItem>> getReadyItems(
    EnrichmentQueueRepository queueRepo,
  ) async {
    return queueRepo.findReadyForStepWithDeps(stepType, requiredSteps);
  }

  /// Process a batch of queue items.
  ///
  /// Worker is responsible for:
  /// 1. Marking items as processing (lock)
  /// 2. Fetching entities fresh (via RepositoryRegistry)
  /// 3. Doing the enrichment work
  /// 4. Race condition check (re-fetch QueueItem before saving)
  /// 5. Marking completed or recording errors
  ///
  /// Items are processed SEQUENTIALLY (N=1) due to HNSW thread-safety.
  Future<void> processBatch(
    List<EnrichmentQueueItem> items,
    EnrichmentQueueRepository queueRepo,
  );
}
