import '../../core/enrichment_queue_item.dart';
import '../../core/enrichment_queue_repository.dart';
import 'enrichment_worker.dart';

class EnrichmentRunner {
  /// Queue repository - owned by runner, passed to workers
  final EnrichmentQueueRepository queueRepo;

  /// Registered workers (List, not Map)
  final List<EnrichmentWorker> workers;

  /// Max items to process per batch
  final int batchSize;

  /// Track which workers are currently running (keyed by stepType)
  final Map<String, Future<void>> _activeWorkers = {};

  EnrichmentRunner({
    required this.queueRepo,
    required this.workers,
    this.batchSize = 10,
  });

  // ============ Public API ============

  /// Add entity to enrichment queue, then trigger worker check.
  ///
  /// Called by EntityRepository.save() when entity is Enrichable.
  Future<void> enqueue({
    required String entityUuid,
    required String entityType,
    required List<String> steps,
  }) async {
    final item = EnrichmentQueueItem(
      entityUuid: entityUuid,
      entityType: entityType,
      pendingSteps: List<String>.from(steps), // Copy to avoid mutation
      completedSteps: [],
    );

    await queueRepo.save(item);

    _onQueueAdd();
  }

  /// Cancel enrichment for an entity.
  ///
  /// Called by EntityRepository.save() when entity is updated.
  /// Old queue item is deleted, new one will be created.
  Future<void> cancelForEntity(String entityUuid) async {
    final item = await queueRepo.findByEntityUuid(entityUuid);
    if (item != null) {
      await queueRepo.delete(item);
    }
  }

  /// Initialize runner on app startup.
  ///
  /// Resets stuck items (currentStep not null) and checks for pending work.
  Future<void> initialize() async {
    final stuck = await queueRepo.findStuckItems();
    for (final item in stuck) {
      if (item.currentStep != null) {
        // Re-add the step to pending if it was removed
        if (!item.pendingSteps.contains(item.currentStep!) &&
            !item.completedSteps.contains(item.currentStep!)) {
          item.pendingSteps.add(item.currentStep!);
        }
        item.currentStep = null;
        await queueRepo.save(item);
      }
    }

    _checkAndSpawnWorkers();
  }

  // ============ Internal Methods ============

  /// Called when item added to queue - NO debounce
  void _onQueueAdd() {
    _checkAndSpawnWorkers();
  }

  /// Check each worker type, spawn if not running and has work
  void _checkAndSpawnWorkers() {
    for (final worker in workers) {
      if (!_activeWorkers.containsKey(worker.stepType)) {
        _activeWorkers[worker.stepType] = _spawnWorker(worker);
      }
    }
  }

  /// Worker runs continuously until queue empty, THEN exits
  Future<void> _spawnWorker(EnrichmentWorker worker) async {
    try {
      while (true) {
        // Worker's getReadyItems() handles dependency checking
        final items = await worker.getReadyItems(queueRepo);
        if (items.isEmpty) break; // Queue empty for this worker, exit

        final batch = items.take(batchSize).toList();
        await worker.processBatch(batch, queueRepo);
      }
    } catch (e) {
      // Log error but don't crash - worker will be respawned on next enqueue
      // ignore: avoid_print
      print('EnrichmentRunner: Worker ${worker.stepType} failed: $e');
    } finally {
      _activeWorkers.remove(worker.stepType);
    }
  }

  /// Check if any workers are currently running
  bool get hasActiveWorkers => _activeWorkers.isNotEmpty;

  /// Get list of active worker step types (for debugging)
  List<String> get activeWorkerTypes => _activeWorkers.keys.toList();
}
