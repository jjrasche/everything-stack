
import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../entities/commitment_log_stub.dart'
    if (dart.library.io) '../entities/commitment_log.dart';

// Platform-specific adapter factory
import 'commitment_log_adapter_web.dart'
    if (dart.library.io) 'commitment_log_adapter_native.dart';

class CommitmentLogRepository extends EntityRepository<CommitmentLog> {
  CommitmentLogRepository({EmbeddingService? embeddingService})
      : super(
          adapter: createCommitmentLogAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ CommitmentLog-specific queries ============

  /// Find all logs for a specific commitment
  Future<List<CommitmentLog>> findByCommitment(String commitmentId) async {
    final all = await findAll();
    return all.where((log) => log.commitmentId == commitmentId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Find log for a commitment on a specific date
  Future<CommitmentLog?> findByCommitmentAndDate(
      String commitmentId, DateTime date) async {
    // Start of day
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final all = await findAll();
    try {
      return all.firstWhere(
        (log) =>
            log.commitmentId == commitmentId &&
            log.date.isAfter(start) &&
            log.date.isBefore(end),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find logs within a date range
  Future<List<CommitmentLog>> findByDateRange(
      DateTime start, DateTime end) async {
    final all = await findAll();
    return all.where((log) {
      return log.date.isAfter(start) && log.date.isBefore(end);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
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
