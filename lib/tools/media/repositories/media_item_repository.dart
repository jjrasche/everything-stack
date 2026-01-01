/// # MediaItemRepository
///
/// Data access layer for MediaItem entities.
/// Provides queries: by channel, by status, by format, semantic search.

import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

import '../entities/media_item.dart';

class MediaItemRepository extends EntityRepository<MediaItem> {
  MediaItemRepository({
    required PersistenceAdapter<MediaItem> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  /// Get all media items in a channel
  Future<List<MediaItem>> findByChannel(String channelId) async {
    final all = await findAll();
    return all.where((item) => item.channelId == channelId).toList();
  }

  /// Get all downloaded media items
  Future<List<MediaItem>> findDownloaded() async {
    final all = await findAll();
    return all
        .where(
            (item) => item.downloadStatus == 'completed' && item.blobId != null)
        .toList();
  }

  /// Get media items waiting for download
  Future<List<MediaItem>> findPending() async {
    final all = await findAll();
    return all.where((item) => item.downloadStatus == 'pending').toList();
  }

  /// Get all audio files
  Future<List<MediaItem>> findAudio() async {
    final all = await findAll();
    return all.where((item) => item.isAudio).toList();
  }

  /// Get all video files
  Future<List<MediaItem>> findVideo() async {
    final all = await findAll();
    return all.where((item) => item.isVideo).toList();
  }

  /// Find by YouTube video ID
  Future<MediaItem?> findByYoutubeId(String videoId) async {
    final all = await findAll();
    final items = all.where((item) => item.youtubeVideoId == videoId).toList();
    return items.isNotEmpty ? items.first : null;
  }

  /// Find by YouTube URL
  Future<MediaItem?> findByUrl(String url) async {
    final all = await findAll();
    final items = all.where((item) => item.youtubeUrl == url).toList();
    return items.isNotEmpty ? items.first : null;
  }

  /// Get recently downloaded (last N days)
  Future<List<MediaItem>> findRecentlyDownloaded({int days = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final all = await findAll();
    return all
        .where((item) =>
            item.downloadedAt != null &&
            item.downloadedAt!.isAfter(cutoff) &&
            item.downloadStatus == 'completed')
        .toList();
  }

  /// Get by format (mp4, mp3, etc.)
  Future<List<MediaItem>> findByFormat(String format) async {
    final all = await findAll();
    return all
        .where((item) => item.format.toLowerCase() == format.toLowerCase())
        .toList();
  }

  /// Count total size of downloaded media
  Future<int> getTotalDownloadedSize() async {
    final downloaded = await findDownloaded();
    return downloaded.fold<int>(
      0,
      (sum, item) => sum + item.fileSizeBytes,
    );
  }

  /// Get statistics
  Future<Map<String, dynamic>> getStats() async {
    final all = await findAll();
    final downloaded = all.where((i) => i.isDownloaded).length;
    final audio = all.where((i) => i.isAudio).length;
    final video = all.where((i) => i.isVideo).length;
    final totalSize = all.fold<int>(0, (sum, i) => sum + i.fileSizeBytes);

    return {
      'total': all.length,
      'downloaded': downloaded,
      'pending': all.where((i) => i.downloadStatus == 'pending').length,
      'downloading': all.where((i) => i.downloadStatus == 'downloading').length,
      'failed': all.where((i) => i.downloadStatus == 'failed').length,
      'audioCount': audio,
      'videoCount': video,
      'totalSizeBytes': totalSize,
      'totalSizeMB': totalSize / (1024 * 1024),
    };
  }
}
