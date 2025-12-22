/// # TimerRepository
///
/// ## What it does
/// Repository for Timer entities. Manages countdown timers.
///
/// ## Usage
/// ```dart
/// final adapter = TimerObjectBoxAdapter(store);
/// final repo = TimerRepository(adapter: adapter);
///
/// // Find active timers
/// final active = await repo.findActive();
///
/// // Find expired timers that haven't fired yet
/// final expired = await repo.findExpired();
/// ```

import '../../../core/entity_repository.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../services/embedding_service.dart';
import '../entities/timer.dart';

class TimerRepository extends EntityRepository<Timer> {
  TimerRepository({
    required PersistenceAdapter<Timer> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Timer-specific queries ============

  /// Find all active timers (not fired, still running)
  Future<List<Timer>> findActive() async {
    final all = await findAll();
    return all.where((timer) => timer.isActive).toList()
      ..sort((a, b) => a.endsAt.compareTo(b.endsAt));
  }

  /// Find expired timers that haven't been marked as fired
  Future<List<Timer>> findExpired() async {
    final all = await findAll();
    return all.where((timer) => timer.hasExpired).toList()
      ..sort((a, b) => a.endsAt.compareTo(b.endsAt));
  }

  /// Find fired timers
  Future<List<Timer>> findFired() async {
    final all = await findAll();
    return all.where((timer) => timer.fired).toList()
      ..sort((a, b) => (b.firedAt ?? b.endsAt).compareTo(a.firedAt ?? a.endsAt));
  }

  /// Find timer by label
  Future<Timer?> findByLabel(String label) async {
    final all = await findAll();
    try {
      return all.firstWhere((timer) => timer.label == label && !timer.fired);
    } catch (e) {
      return null;
    }
  }

  /// Find timers created by a specific tool invocation
  Future<List<Timer>> findByCorrelationId(String correlationId) async {
    final all = await findAll();
    return all
        .where((timer) => timer.invocationCorrelationId == correlationId)
        .toList();
  }
}
