/// # EnrichmentQueueObjectBoxAdapter
///
/// ObjectBox implementation of EnrichmentQueueAdapter.
/// Provides queries for enrichment worker and runner operations.

import 'package:objectbox/objectbox.dart';
import '../../core/enrichment_queue_item.dart';
import '../../core/enrichment_queue_repository.dart';
import '../../objectbox.g.dart';
import 'wrappers/enrichment_queue_item_ob.dart';

class EnrichmentQueueObjectBoxAdapter implements EnrichmentQueueAdapter {
  final Store _store;
  late final Box<EnrichmentQueueItemOB> _box;

  EnrichmentQueueObjectBoxAdapter(this._store) {
    _box = _store.box<EnrichmentQueueItemOB>();
  }

  // ============ CRUD ============

  @override
  Future<EnrichmentQueueItem?> findByUuid(String uuid) async {
    final query = _box.query(EnrichmentQueueItemOB_.uuid.equals(uuid)).build();
    try {
      final ob = query.findFirst();
      return ob?.toItem();
    } finally {
      query.close();
    }
  }

  @override
  Future<EnrichmentQueueItem?> findByEntityUuid(String entityUuid) async {
    final query = _box
        .query(EnrichmentQueueItemOB_.entityUuid.equals(entityUuid))
        .build();
    try {
      final ob = query.findFirst();
      return ob?.toItem();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EnrichmentQueueItem>> findAll() async {
    final obList = _box.getAll();
    return obList.map((ob) => ob.toItem()).toList();
  }

  @override
  Future<EnrichmentQueueItem> save(EnrichmentQueueItem item) async {
    final ob = EnrichmentQueueItemOB.fromItem(item);
    final id = _box.put(ob);
    item.id = id;
    return item;
  }

  @override
  Future<bool> delete(EnrichmentQueueItem item) async {
    return _box.remove(item.id);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final item = await findByUuid(uuid);
    if (item == null) return false;
    return _box.remove(item.id);
  }

  // ============ Worker Queries ============

  @override
  Future<List<EnrichmentQueueItem>> findReadyForStep(String stepType) async {
    // Find items where:
    // - pendingSteps contains stepType (EXACT match, not substring)
    // - currentStep is null (not being processed)
    //
    // CRITICAL: Cannot use .contains() on comma-separated string - it does substring matching
    // "semantic" would incorrectly match "semantic_enrichment,categorization"
    // Solution: Fetch all candidates, filter in Dart for exact list membership
    final query = _box
        .query(EnrichmentQueueItemOB_.currentStep.isNull())
        .order(EnrichmentQueueItemOB_.enqueuedAt)
        .build();
    try {
      final obList = query.find();
      // Filter in Dart for exact step matching
      return obList
          .map((ob) => ob.toItem())
          .where((item) => item.pendingSteps.contains(stepType))
          .toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EnrichmentQueueItem>> findReadyForStepWithDeps(
    String stepType,
    List<String> requiredSteps,
  ) async {
    // If no required steps, use simpler query
    if (requiredSteps.isEmpty) {
      return findReadyForStep(stepType);
    }

    // Fetch all non-processing items, filter in Dart for exact matching
    // CRITICAL: .contains() does substring matching, not list membership
    final query = _box
        .query(EnrichmentQueueItemOB_.currentStep.isNull())
        .order(EnrichmentQueueItemOB_.enqueuedAt)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => ob.toItem()).where((item) {
        // pendingSteps contains stepType (exact match)
        if (!item.pendingSteps.contains(stepType)) return false;
        // completedSteps contains all required steps (exact match)
        return requiredSteps
            .every((step) => item.completedSteps.contains(step));
      }).toList();
    } finally {
      query.close();
    }
  }

  // ============ Recovery Queries ============

  @override
  Future<List<EnrichmentQueueItem>> findStuckItems() async {
    // Items stuck in processing (currentStep not null)
    final query =
        _box.query(EnrichmentQueueItemOB_.currentStep.notNull()).build();
    try {
      final obList = query.find();
      return obList.map((ob) => ob.toItem()).toList();
    } finally {
      query.close();
    }
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle is managed externally
  }
}
