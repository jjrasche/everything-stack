/// # Organize Handler
///
/// Tool handler for: media.organize
///
/// ## What it does
/// Organizes/links media to channels. Sets up channel subscriptions for
/// watch-later organization and notifications.
///
/// ## Parameters
/// - mediaItemId (string): UUID of MediaItem to organize
/// - channelId (string): UUID of Channel to link to [optional, auto-detect from YouTube]
/// - youtubChannelId (string): YouTube channel ID to subscribe to [optional]
/// - channelName (string): Human name for the channel [optional]
///
/// ## Returns
/// ```json
/// {
///   "success": true,
///   "mediaItemId": "uuid",
///   "channelId": "uuid",
///   "channelName": "...",
///   "organizationStatus": "linked"
/// }
/// ```

import 'package:everything_stack_template/tools/media/repositories/channel_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/media_item_repository.dart';

import '../entities/channel.dart';
import '../entities/media_item.dart';

class OrganizeHandler {
  final MediaItemRepository mediaRepo;
  final ChannelRepository channelRepo;

  OrganizeHandler({
    required this.mediaRepo,
    required this.channelRepo,
  });

  /// Execute the organize tool
  Future<Map<String, dynamic>> call(Map<String, dynamic> params) async {
    try {
      // Extract parameters
      final mediaItemId = params['mediaItemId'] as String?;
      final channelId = params['channelId'] as String?;
      final youtubeChannelId = params['youtubeChannelId'] as String?;
      final channelName = params['channelName'] as String?;

      if (mediaItemId == null || mediaItemId.isEmpty) {
        return {
          'success': false,
          'error': 'mediaItemId parameter required',
        };
      }

      // Get the media item
      final mediaItem = await mediaRepo.findByUuid(mediaItemId);
      if (mediaItem == null) {
        return {
          'success': false,
          'error': 'Media item not found: $mediaItemId',
        };
      }

      // Determine which channel to use
      Channel? channel;

      if (channelId != null && channelId.isNotEmpty) {
        // Use provided channel ID
        channel = await channelRepo.findByUuid(channelId);
        if (channel == null) {
          return {
            'success': false,
            'error': 'Channel not found: $channelId',
          };
        }
      } else if (youtubeChannelId != null && youtubeChannelId.isNotEmpty) {
        // Find or create channel by YouTube ID
        channel = await channelRepo.findByYoutubeId(youtubeChannelId);

        if (channel == null) {
          // Create new channel
          final name = channelName ?? 'Channel $youtubeChannelId';
          channel = Channel(
            name: name,
            youtubeChannelId: youtubeChannelId,
            youtubeUrl: 'https://www.youtube.com/channel/$youtubeChannelId',
          );
          await channelRepo.save(channel);
        }
      } else {
        // Try to auto-detect from existing channels (matching patterns)
        // This is a heuristic - would need real YouTube metadata API for accuracy
        if (mediaItem.channelId.isEmpty) {
          return {
            'success': false,
            'error':
                'Cannot determine channel. Provide channelId, youtubeChannelId, or ensure mediaItem has channelId.',
          };
        }
        channel = await channelRepo.getByUuid(mediaItem.channelId);
      }

      if (channel == null) {
        return {
          'success': false,
          'error': 'Could not find or create channel',
        };
      }

      // Link media to channel
      mediaItem.channelId = channel.uuid;
      await mediaRepo.save(mediaItem);

      // Ensure channel is subscribed
      if (!channel.isSubscribed) {
        channel.subscribe();
        await channelRepo.save(channel);
      }

      return {
        'success': true,
        'mediaItemId': mediaItemId,
        'channelId': channel.uuid,
        'channelName': channel.name,
        'organizationStatus': 'linked',
        'message':
            'Media linked to channel "${channel.name}". Channel subscription active.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
