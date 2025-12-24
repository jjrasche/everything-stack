/// # Media Handler Factory
///
/// Creates and registers all media tool handlers with the tool registry.
///
/// Registers these tools:
/// - media.download: Queue a YouTube download
/// - media.convert: Convert downloaded media to different format
/// - media.organize: Link/organize media to channels
/// - media.search: Search downloaded media semantically

import 'package:everything_stack_template/services/tool_registry.dart';
import 'package:everything_stack_template/tools/media/repositories/channel_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/download_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/media_item_repository.dart';

import 'convert_handler.dart';
import 'download_handler.dart';
import 'organize_handler.dart';
import 'search_handler.dart';

class MediaHandlerFactory {
  final MediaItemRepository mediaRepo;
  final DownloadRepository downloadRepo;
  final ChannelRepository channelRepo;

  MediaHandlerFactory({
    required this.mediaRepo,
    required this.downloadRepo,
    required this.channelRepo,
  });

  /// Register all media tools with the registry
  void registerTools(ToolRegistry registry) {
    // Create handlers
    final downloadHandler = DownloadHandler(
      mediaRepo: mediaRepo,
      downloadRepo: downloadRepo,
      channelRepo: channelRepo,
    );

    final convertHandler = ConvertHandler(
      mediaRepo: mediaRepo,
    );

    final organizeHandler = OrganizeHandler(
      mediaRepo: mediaRepo,
      channelRepo: channelRepo,
    );

    final searchHandler = SearchHandler(
      mediaRepo: mediaRepo,
      channelRepo: channelRepo,
    );

    // Register media.download
    registry.register(
      ToolDefinition(
        name: 'media.download',
        namespace: 'media',
        description:
            'Download a video or audio from YouTube. Creates a download job.',
        parameters: {
          'type': 'object',
          'properties': {
            'youtubeUrl': {
              'type': 'string',
              'description':
                  'Full YouTube URL (e.g., https://www.youtube.com/watch?v=...) or video ID',
            },
            'format': {
              'type': 'string',
              'description': 'Output format: mp4 (default), mp3, webm, etc.',
              'enum': ['mp4', 'mp3', 'webm', 'mkv', 'm4a', 'aac', 'wav'],
              'default': 'mp4',
            },
            'quality': {
              'type': 'string',
              'description':
                  'Desired quality: 1080p, 720p, 480p, 360p, audio-only, etc.',
              'default': '720p',
            },
          },
          'required': ['youtubeUrl'],
        },
      ),
      downloadHandler.call,
    );

    // Register media.convert
    registry.register(
      ToolDefinition(
        name: 'media.convert',
        namespace: 'media',
        description:
            'Convert a downloaded media item to a different format or quality.',
        parameters: {
          'type': 'object',
          'properties': {
            'mediaItemId': {
              'type': 'string',
              'description': 'UUID of the MediaItem to convert',
            },
            'targetFormat': {
              'type': 'string',
              'description': 'Target format: mp4, mp3, webm, etc.',
              'enum': ['mp4', 'mp3', 'webm', 'mkv', 'm4a', 'aac', 'wav'],
            },
            'targetQuality': {
              'type': 'string',
              'description': 'Target quality (optional for audio conversions)',
            },
          },
          'required': ['mediaItemId', 'targetFormat'],
        },
      ),
      convertHandler.call,
    );

    // Register media.organize
    registry.register(
      ToolDefinition(
        name: 'media.organize',
        namespace: 'media',
        description:
            'Link/organize media to a YouTube channel for watch-later and notifications.',
        parameters: {
          'type': 'object',
          'properties': {
            'mediaItemId': {
              'type': 'string',
              'description': 'UUID of the MediaItem to organize',
            },
            'channelId': {
              'type': 'string',
              'description': 'UUID of existing Channel (if available)',
            },
            'youtubeChannelId': {
              'type': 'string',
              'description': 'YouTube channel ID to subscribe to',
            },
            'channelName': {
              'type': 'string',
              'description': 'Human-readable channel name',
            },
          },
          'required': ['mediaItemId'],
        },
      ),
      organizeHandler.call,
    );

    // Register media.search
    registry.register(
      ToolDefinition(
        name: 'media.search',
        namespace: 'media',
        description:
            'Search downloaded media by semantic similarity to your query.',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'Search query (e.g., "how to use embeddings", "tutorial on semantic search")',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum results to return',
              'default': 10,
            },
            'format': {
              'type': 'string',
              'description': 'Filter by format (mp4, mp3, etc.)',
            },
            'channelId': {
              'type': 'string',
              'description': 'Filter by channel UUID',
            },
          },
          'required': ['query'],
        },
      ),
      searchHandler.call,
    );
  }
}
