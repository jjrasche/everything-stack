/// # ChannelRepository
///
/// Data access layer for Channel entities.
/// Provides queries: subscribed channels, by name, needs checking, etc.

import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

import '../entities/channel.dart';

class ChannelRepository extends EntityRepository<Channel> {
  ChannelRepository({
    required PersistenceAdapter<Channel> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  /// Get all subscribed channels
  Future<List<Channel>> findSubscribed() async {
    final all = await findAll();
    return all.where((channel) => channel.isSubscribed).toList();
  }

  /// Get channels that need checking for new videos
  Future<List<Channel>> findNeedingCheck() async {
    final all = await findAll();
    return all.where((channel) => channel.shouldCheckForNew).toList();
  }

  /// Find by YouTube channel ID
  Future<Channel?> findByYoutubeId(String channelId) async {
    final all = await findAll();
    final channels =
        all.where((channel) => channel.youtubeChannelId == channelId).toList();
    return channels.isNotEmpty ? channels.first : null;
  }

  /// Find by name (case-insensitive)
  Future<List<Channel>> findByName(String name) async {
    final all = await findAll();
    return all
        .where((channel) =>
            channel.name.toLowerCase().contains(name.toLowerCase()))
        .toList();
  }

  /// Get recently subscribed channels
  Future<List<Channel>> findRecentlySubscribed({int days = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final all = await findAll();
    return all
        .where((channel) =>
            channel.subscribedAt != null &&
            channel.subscribedAt!.isAfter(cutoff) &&
            channel.isSubscribed)
        .toList();
  }

  /// Mark all subscribed channels as needing check
  Future<void> markAllForCheck() async {
    final subscribed = await findSubscribed();
    for (final channel in subscribed) {
      channel.lastCheckedAt = null;
      await save(channel);
    }
  }

  /// Get subscription statistics
  Future<Map<String, dynamic>> getStats() async {
    final all = await findAll();
    final subscribed = all.where((c) => c.isSubscribed).length;
    final unsubscribed = all.where((c) => !c.isSubscribed).length;
    final needsCheck = all.where((c) => c.shouldCheckForNew).length;
    final lastWeek = all
        .where((c) =>
            c.subscribedAt != null &&
            c.subscribedAt!.isAfter(DateTime.now().subtract(Duration(days: 7))))
        .length;

    return {
      'total': all.length,
      'subscribed': subscribed,
      'unsubscribed': unsubscribed,
      'needsCheck': needsCheck,
      'addedLastWeek': lastWeek,
    };
  }
}
