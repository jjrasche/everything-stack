import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../tools/regulation/entities/commitment_log.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/commitment_log_ob.dart';

class CommitmentLogObjectBoxAdapter
    extends BaseObjectBoxAdapter<CommitmentLog, CommitmentLogOB>
    implements PersistenceAdapter<CommitmentLog> {
  CommitmentLogObjectBoxAdapter(Store store) : super(store);

  @override
  CommitmentLogOB toOB(CommitmentLog entity) =>
      CommitmentLogOB.fromCommitmentLog(entity);

  @override
  CommitmentLog fromOB(CommitmentLogOB ob) => ob.toCommitmentLog();

  @override
  Condition<CommitmentLogOB> uuidEqualsCondition(String uuid) =>
      CommitmentLogOB_.uuid.equals(uuid);

  @override
  Condition<CommitmentLogOB> syncStatusLocalCondition() =>
      CommitmentLogOB_.syncId.isNull();

  // ============ CommitmentLog-Specific Query Methods ============

  /// Find all logs for a specific commitment
  Future<List<CommitmentLog>> findByCommitment(String commitmentId) async {
    final query = box
        .query(CommitmentLogOB_.commitmentId.equals(commitmentId))
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find log for a commitment on a specific date
  Future<CommitmentLog?> findByCommitmentAndDate(
      String commitmentId, DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final query = box
        .query(CommitmentLogOB_.commitmentId.equals(commitmentId) &
            CommitmentLogOB_.date.betweenDate(start, end))
        .build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  /// Find logs within a date range
  Future<List<CommitmentLog>> findByDateRange(
      DateTime start, DateTime end) async {
    final query = box
        .query(CommitmentLogOB_.date.betweenDate(start, end))
        .order(CommitmentLogOB_.date)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Get completion rate for a commitment (percentage of completed logs)
  Future<double> getCompletionRate(String commitmentId) async {
    final logs = await findByCommitment(commitmentId);
    if (logs.isEmpty) {
      return 0.0;
    }

    final completedCount = logs.where((log) => log.completed).length;
    return (completedCount / logs.length) * 100;
  }
}
