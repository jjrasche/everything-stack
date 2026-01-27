/// # TrialObjectBoxAdapter
///
/// ObjectBox adapter for Trial entity.
/// Implements TrialRepository interface for native platforms.

import 'package:objectbox/objectbox.dart';
import '../../core/trial_repository.dart';
import '../../core/trial.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/trial_ob.dart';

class TrialObjectBoxAdapter extends BaseObjectBoxAdapter<Trial, TrialOB>
    implements TrialRepository {
  TrialObjectBoxAdapter(Store store) : super(store);

  @override
  TrialOB toOB(Trial entity) => TrialOB.fromTrial(entity);

  @override
  Trial fromOB(TrialOB ob) => ob.toTrial();

  @override
  Condition<TrialOB> uuidEqualsCondition(String uuid) =>
      TrialOB_.uuid.equals(uuid);

  @override
  Condition<TrialOB> syncStatusLocalCondition() => TrialOB_.syncId.notNull();

  // ============ TrialRepository Implementation ============

  @override
  Future<List<Trial>> getRecent({
    required String componentType,
    String? userId,
    int limit = 100,
  }) async {
    var condition = TrialOB_.componentType.equals(componentType);

    if (userId != null) {
      condition = condition.and(TrialOB_.userId.equals(userId));
    }

    final query = box
        .query(condition)
        .order(TrialOB_.createdAt, flags: Order.descending)
        .build()
      ..limit = limit;

    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Trial>> findByComponent({
    required String componentType,
    String? userId,
  }) async {
    var condition = TrialOB_.componentType.equals(componentType);

    if (userId != null) {
      condition = condition.and(TrialOB_.userId.equals(userId));
    }

    final query = box.query(condition).build();

    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> deleteOldTrials({
    required String componentType,
    int keepLatest = 100,
    String? userId,
  }) async {
    // Get all trials for component
    final trials = await getRecent(
      componentType: componentType,
      userId: userId,
      limit: 999999, // Get all
    );

    if (trials.length <= keepLatest) {
      return 0; // Nothing to delete
    }

    // Delete trials beyond keepLatest
    final trialsToDelete = trials.skip(keepLatest).toList();
    int deleteCount = 0;

    for (final trial in trialsToDelete) {
      final deleted = await delete(trial.uuid);
      if (deleted) deleteCount++;
    }

    return deleteCount;
  }

  @override
  Future<int> deleteByComponent({
    required String componentType,
    String? userId,
  }) async {
    var condition = TrialOB_.componentType.equals(componentType);

    if (userId != null) {
      condition = condition.and(TrialOB_.userId.equals(userId));
    }

    final query = box.query(condition).build();

    try {
      return query.remove();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> count({
    required String componentType,
    String? userId,
  }) async {
    var condition = TrialOB_.componentType.equals(componentType);

    if (userId != null) {
      condition = condition.and(TrialOB_.userId.equals(userId));
    }

    final query = box.query(condition).build();

    try {
      return query.count();
    } finally {
      query.close();
    }
  }
}
