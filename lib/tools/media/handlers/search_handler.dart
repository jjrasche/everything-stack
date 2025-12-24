/// # Search Handler
///
/// Tool handler for: media.search
///
/// ## What it does
/// Semantic search across downloaded media.
/// Returns results ranked by semantic similarity to query.
///
/// ## Parameters
/// - query (string): Search query (e.g., "how to use embeddings")
/// - limit (int): Max results to return [default: 10]
/// - format (string): Filter by format (mp4, mp3, etc.) [optional]
/// - channelId (string): Filter by channel UUID [optional]
///
/// ## Returns
/// ```json
/// {
///   "success": true,
///   "query": "...",
///   "results": [
///     {
///       "mediaItemId": "uuid",
///       "title": "...",
///       "channelName": "...",
///       "similarity": 0.92,
///       "format": "mp4",
///       "downloadedAt": "2025-12-23..."
///     }
///   ],
///   "count": 3
/// }
/// ```

import 'package:everything_stack_template/tools/media/repositories/channel_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/media_item_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/patterns/embeddable.dart';

import '../entities/media_item.dart';

class SearchHandler {
  final MediaItemRepository mediaRepo;
  final ChannelRepository channelRepo;

  SearchHandler({
    required this.mediaRepo,
    required this.channelRepo,
  });

  /// Execute the search tool
  Future<Map<String, dynamic>> call(Map<String, dynamic> params) async {
    try {
      // Extract parameters
      final query = params['query'] as String?;
      final limit = params['limit'] as int? ?? 10;
      final format = params['format'] as String?;
      final channelId = params['channelId'] as String?;

      if (query == null || query.isEmpty) {
        return {
          'success': false,
          'error': 'query parameter required',
        };
      }

      // Use semantic search via embeddings to find relevant items
      var results = await mediaRepo.semanticSearch(
        query,
        limit: limit,
      );

      // Filter by format if provided
      if (format != null && format.isNotEmpty) {
        results = results
            .where((item) =>
                item.format.toLowerCase() == format.toLowerCase())
            .toList();
      }

      // Filter by channel if provided
      if (channelId != null && channelId.isNotEmpty) {
        results =
            results.where((item) => item.channelId == channelId).toList();
      }

      final topResults = results;

      // Generate query embedding to calculate similarity scores
      final queryEmbedding = await EmbeddingService.instance.generate(query);

      // Build response with similarity scores
      final formattedResults = <Map<String, dynamic>>[];
      for (final item in topResults) {
        // Calculate similarity score for this item
        double similarity = 0.0;
        if (item is Embeddable && item.embedding != null && item.embedding!.isNotEmpty) {
          similarity = EmbeddingService.cosineSimilarity(
            queryEmbedding,
            item.embedding!,
          );
        }

        // Get channel name if available
        String channelName = 'Unknown';
        if (item.channelId.isNotEmpty) {
          final channel = await channelRepo.findByUuid(item.channelId);
          if (channel != null) {
            channelName = channel.name;
          }
        }

        formattedResults.add({
          'mediaItemId': item.uuid,
          'title': item.title,
          'channelName': channelName,
          'format': item.format,
          'similarity': (similarity * 100).round() / 100, // Round to 2 decimals
          'downloadedAt': item.downloadedAt?.toIso8601String(),
          'description': item.description,
          'duration': item.durationSeconds,
        });
      }

      return {
        'success': true,
        'query': query,
        'results': formattedResults,
        'count': formattedResults.length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

}
