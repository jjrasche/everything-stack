/// # Download Handler
///
/// Tool handler for: media.download
///
/// ## What it does
/// Queues a YouTube video for download.
/// Creates Download and MediaItem records, triggers actual download.
///
/// ## Parameters
/// - youtubeUrl (string): Full YouTube URL or video ID
/// - format (string): Output format (mp4, mp3, webm, etc.)
/// - quality (string): Desired quality (1080p, 720p, 480p, audio-only, etc.)
///
/// ## Returns
/// ```json
/// {
///   "downloadId": "uuid",
///   "mediaItemId": "uuid",
///   "status": "queued",
///   "youtubeUrl": "...",
///   "format": "mp4",
///   "quality": "720p"
/// }
/// ```

import 'package:everything_stack_template/tools/media/repositories/channel_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/download_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/media_item_repository.dart';

import '../entities/channel.dart';
import '../entities/download.dart';
import '../entities/media_item.dart';

class DownloadHandler {
  final MediaItemRepository mediaRepo;
  final DownloadRepository downloadRepo;
  final ChannelRepository channelRepo;

  DownloadHandler({
    required this.mediaRepo,
    required this.downloadRepo,
    required this.channelRepo,
  });

  /// Execute the download tool
  Future<Map<String, dynamic>> call(Map<String, dynamic> params) async {
    try {
      // Extract parameters
      final youtubeUrl = params['youtubeUrl'] as String?;
      final format = params['format'] as String? ?? 'mp4';
      final quality = params['quality'] as String? ?? '720p';

      if (youtubeUrl == null || youtubeUrl.isEmpty) {
        return {
          'success': false,
          'error': 'youtubeUrl parameter required',
        };
      }

      // Extract video ID from URL
      final videoId = _extractVideoId(youtubeUrl);
      if (videoId == null) {
        return {
          'success': false,
          'error': 'Invalid YouTube URL',
        };
      }

      // Check if already downloading/downloaded
      final existing = await downloadRepo.findByYoutubeId(videoId);
      if (existing != null) {
        return {
          'success': false,
          'error': 'Download already in progress or completed',
          'downloadId': existing.uuid,
          'status': existing.status,
        };
      }

      // Create MediaItem placeholder first
      // TODO: Extract metadata from YouTube (title, duration, etc.)
      final mediaItem = MediaItem(
        title: 'Video $videoId', // Placeholder - will be updated with real metadata
        youtubeUrl: youtubeUrl,
        youtubeVideoId: videoId,
        channelId: '', // Will be filled once we fetch metadata
        format: format.toLowerCase(),
      );
      await mediaRepo.save(mediaItem);

      // Create Download record and link it to the MediaItem
      final download = Download(
        youtubeUrl: youtubeUrl,
        youtubeVideoId: videoId,
        format: format.toLowerCase(),
        quality: quality,
        mediaItemId: mediaItem.uuid, // Link to the MediaItem
      );
      await downloadRepo.save(download);

      // TODO: Trigger actual YouTube DL process (background task/service)
      // For now, just queue it

      return {
        'success': true,
        'downloadId': download.uuid,
        'mediaItemId': mediaItem.uuid,
        'status': download.status,
        'youtubeUrl': youtubeUrl,
        'format': format,
        'quality': quality,
        'message':
            'Download queued. Will start processing shortly.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Extract YouTube video ID from URL or return as-is if already just ID
  String? _extractVideoId(String input) {
    // If it's already just the ID (11 chars of alphanumeric)
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(input)) {
      return input;
    }

    // Extract from various YouTube URL formats
    final patterns = [
      // youtu.be/xxxxx
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      // youtube.com/watch?v=xxxxx
      RegExp(r'(?:youtube\.com/watch\?.*v=)([a-zA-Z0-9_-]{11})'),
      // youtube.com/embed/xxxxx
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      // youtube.com/v/xxxxx
      RegExp(r'youtube\.com/v/([a-zA-Z0-9_-]{11})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }
}
