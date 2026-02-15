import 'dart:indexed_db' as idb;
import '../../core/enrichment_queue_item.dart';
import '../../core/enrichment_queue_repository.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class EnrichmentQueueIndexedDBAdapter
    extends BaseIndexedDBAdapter<EnrichmentQueueItem>
    implements EnrichmentQueueAdapter {
  EnrichmentQueueIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.enrichmentQueue;

  @override
  EnrichmentQueueItem fromJson(Map<String, dynamic> json) =>
      EnrichmentQueueItem.fromJson(json);

  // ============ EnrichmentQueueAdapter Implementation ============

  @override
  Future<EnrichmentQueueItem?> findByUuid(String uuid) async {
    return await findById(uuid);
  }

  @override
  Future<EnrichmentQueueItem?> findByEntityUuid(String entityUuid) async {
    final allItems = await findAll();
    try {
      return allItems.firstWhere((item) => item.entityUuid == entityUuid);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<EnrichmentQueueItem>> findReadyForStep(String stepType) async {
    final allItems = await findAll();
    return allItems.where((item) {
      // pendingSteps contains stepType AND currentStep is null
      return item.pendingSteps.contains(stepType) && item.currentStep == null;
    }).toList()
      ..sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
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

    final allItems = await findAll();
    return allItems.where((item) {
      // pendingSteps contains stepType
      if (!item.pendingSteps.contains(stepType)) return false;
      // currentStep is null
      if (item.currentStep != null) return false;
      // completedSteps contains all required steps
      return requiredSteps.every((step) => item.completedSteps.contains(step));
    }).toList()
      ..sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
  }

  @override
  Future<List<EnrichmentQueueItem>> findStuckItems() async {
    final allItems = await findAll();
    return allItems.where((item) => item.currentStep != null).toList();
  }

  @override
  Future<bool> delete(EnrichmentQueueItem item) async {
    return await super.delete(item.uuid);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    return await super.delete(uuid);
  }
}
