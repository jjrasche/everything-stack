/// # DownloadRepository
///
/// Data access layer for Download entities.
/// Provides queries: by status, pending, failed, by format, etc.

import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

import '../entities/download.dart';

class DownloadRepository extends EntityRepository<Download> {
  DownloadRepository({
    required PersistenceAdapter<Download> adapter,
    EmbeddingService? embeddingService,
  }) : super(
    adapter: adapter,
    embeddingService: embeddingService ?? EmbeddingService.instance,
  );

  /// Get all active downloads (queued, downloading, processing)
  Future<List<Download>> findActive() async {
    final all = await findAll();
    return all.where((download) => download.isActive).toList();
  }

  /// Get all queued downloads
  Future<List<Download>> findQueued() async {
    final all = await findAll();
    return all.where((download) => download.status == 'queued').toList();
  }

  /// Get all currently downloading
  Future<List<Download>> findDownloading() async {
    final all = await findAll();
    return all.where((download) => download.status == 'downloading').toList();
  }

  /// Get all completed downloads
  Future<List<Download>> findCompleted() async {
    final all = await findAll();
    return all.where((download) => download.isComplete).toList();
  }

  /// Get all failed downloads
  Future<List<Download>> findFailed() async {
    final all = await findAll();
    return all.where((download) => download.isFailed).toList();
  }

  /// Get failed downloads that can be retried
  Future<List<Download>> findRetryable() async {
    final all = await findAll();
    return all.where((download) => download.canRetry).toList();
  }

  /// Find by YouTube video ID
  Future<Download?> findByYoutubeId(String videoId) async {
    final all = await findAll();
    final downloads =
        all.where((download) => download.youtubeVideoId == videoId).toList();
    return downloads.isNotEmpty ? downloads.first : null;
  }

  /// Find by YouTube URL
  Future<Download?> findByUrl(String url) async {
    final all = await findAll();
    final downloads =
        all.where((download) => download.youtubeUrl == url).toList();
    return downloads.isNotEmpty ? downloads.first : null;
  }

  /// Get downloads by format (mp4, mp3, etc.)
  Future<List<Download>> findByFormat(String format) async {
    final all = await findAll();
    return all
        .where((download) =>
            download.format.toLowerCase() == format.toLowerCase())
        .toList();
  }

  /// Get recently completed downloads
  Future<List<Download>> findRecentlyCompleted({int hours = 24}) async {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final all = await findAll();
    return all
        .where((download) =>
            download.isComplete &&
            download.finishedAt != null &&
            download.finishedAt!.isAfter(cutoff))
        .toList();
  }

  /// Get download statistics
  Future<Map<String, dynamic>> getStats() async {
    final all = await findAll();
    final active = all.where((d) => d.isActive).length;
    final completed = all.where((d) => d.isComplete).length;
    final failed = all.where((d) => d.isFailed).length;
    final retryable = all.where((d) => d.canRetry).length;

    return {
      'total': all.length,
      'active': active,
      'completed': completed,
      'failed': failed,
      'retryable': retryable,
      'queued': all.where((d) => d.status == 'queued').length,
      'downloading': all.where((d) => d.status == 'downloading').length,
      'processing': all.where((d) => d.status == 'processing').length,
    };
  }

  /// Clean up old failed downloads (keep only recent N failures)
  Future<void> cleanupOldFailed({int keepDays = 7, int maxCount = 100}) async {
    final failed = await findFailed();
    if (failed.length > maxCount) {
      // Sort by finishedAt descending (newest first)
      failed.sort((a, b) =>
          (b.finishedAt ?? DateTime.now())
              .compareTo(a.finishedAt ?? DateTime.now()));

      // Delete oldest ones beyond keepDays
      final cutoff = DateTime.now().subtract(Duration(days: keepDays));
      for (final download in failed) {
        if ((download.finishedAt ?? DateTime.now()).isBefore(cutoff)) {
          await delete(download.id!);
        }
      }
    }
  }
}
