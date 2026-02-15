import 'dart:indexed_db' as idb;
import '../../core/trial_repository.dart';
import '../../core/trial.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class TrialIndexedDBAdapter extends BaseIndexedDBAdapter<Trial>
    implements TrialRepository {
  TrialIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.trials;

  @override
  Trial fromJson(Map<String, dynamic> json) => Trial.fromJson(json);

  // ============ TrialRepository Implementation ============

  @override
  Future<List<Trial>> getRecent({
    required String componentType,
    String? userId,
    int limit = 100,
  }) async {
    final allTrials = await findAll();

    var filtered = allTrials.where((t) => t.componentType == componentType);

    if (userId != null) {
      filtered = filtered.where((t) => t.userId == userId);
    }

    final sorted = filtered.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Limit results
    return sorted.take(limit).toList();
  }

  @override
  Future<List<Trial>> findByComponent({
    required String componentType,
    String? userId,
  }) async {
    final allTrials = await findAll();

    var filtered = allTrials.where((t) => t.componentType == componentType);

    if (userId != null) {
      filtered = filtered.where((t) => t.userId == userId);
    }

    return filtered.toList();
  }

  @override
  Future<int> deleteOldTrials({
    required String componentType,
    int keepLatest = 100,
    String? userId,
  }) async {
    final trials = await getRecent(
      componentType: componentType,
      userId: userId,
      limit: 999999, // Get all
    );

    if (trials.length <= keepLatest) {
      return 0;
    }

    final trialsToDelete = trials.skip(keepLatest).toList();
    int deleteCount = 0;

    for (final trial in trialsToDelete) {
      if (await delete(trial.uuid)) {
        deleteCount++;
      }
    }

    return deleteCount;
  }

  @override
  Future<int> deleteByComponent({
    required String componentType,
    String? userId,
  }) async {
    final trials = await findByComponent(
      componentType: componentType,
      userId: userId,
    );

    int deleteCount = 0;
    for (final trial in trials) {
      if (await delete(trial.uuid)) {
        deleteCount++;
      }
    }

    return deleteCount;
  }

  @override
  Future<int> count({
    required String componentType,
    String? userId,
  }) async {
    final trials = await findByComponent(
      componentType: componentType,
      userId: userId,
    );

    return trials.length;
  }
}
