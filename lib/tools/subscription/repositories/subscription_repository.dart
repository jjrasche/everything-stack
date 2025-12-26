/// # SubscriptionRepository
///
/// ## What it does
/// Repository for Subscription entities. Manages media source subscriptions.
///
/// ## Usage
/// ```dart
/// final adapter = SubscriptionObjectBoxAdapter(store);
/// final repo = SubscriptionRepository(adapter: adapter);
///
/// // Find active subscriptions
/// final active = await repo.findActive();
///
/// // Find subscriptions by source type
/// final youtube = await repo.findBySourceType('youtube_channel');
/// ```

import '../../../core/entity_repository.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../services/embedding_service.dart';
import '../entities/subscription.dart';

class SubscriptionRepository extends EntityRepository<Subscription> {
  SubscriptionRepository({
    required PersistenceAdapter<Subscription> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Subscription-specific queries ============

  /// Find all active subscriptions
  Future<List<Subscription>> findActive() async {
    final all = await findAll();
    return all.where((sub) => sub.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find all inactive subscriptions
  Future<List<Subscription>> findInactive() async {
    final all = await findAll();
    return all.where((sub) => !sub.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find subscription by source URL
  Future<Subscription?> findBySourceUrl(String sourceUrl) async {
    final all = await findAll();
    try {
      return all.firstWhere((sub) => sub.sourceUrl == sourceUrl);
    } catch (e) {
      return null;
    }
  }

  /// Find subscriptions by source type
  Future<List<Subscription>> findBySourceType(String sourceType) async {
    final all = await findAll();
    return all.where((sub) => sub.sourceType == sourceType).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find subscriptions that need polling (haven't been checked recently)
  Future<List<Subscription>> findNeedingPolling(
      {Duration staleness = const Duration(hours: 1)}) async {
    final all = await findActive();
    final threshold = DateTime.now().subtract(staleness);

    return all
        .where((sub) =>
            sub.lastCheckedAt == null || sub.lastCheckedAt!.isBefore(threshold))
        .toList();
  }

  /// Find subscriptions created by a specific tool invocation
  /// Note: invocationCorrelationId not yet implemented on Subscription entity
  Future<List<Subscription>> findByCorrelationId(String correlationId) async {
    // TODO: Implement invocationCorrelationId tracking
    return [];
  }

  /// Find subscriptions by name (partial match)
  Future<List<Subscription>> findByName(String name) async {
    final all = await findAll();
    final lowerName = name.toLowerCase();
    return all
        .where((sub) => sub.name.toLowerCase().contains(lowerName))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}
