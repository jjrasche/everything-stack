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

      // Get downloaded media items
      var results = await mediaRepo.findDownloaded();

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

      // TODO: Use semantic search via embeddings service
      // For now, do simple keyword matching as placeholder
      final searchLower = query.toLowerCase();
      final scored = results.map((item) {
        final titleScore = _computeSimilarity(item.title, searchLower);
        final descScore = _computeSimilarity(
          item.description ?? '',
          searchLower,
        );
        final maxScore = (titleScore + descScore) / 2;
        return {
          'item': item,
          'score': maxScore,
        };
      }).toList();

      // Sort by score descending
      scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      // Take top N
      final topResults = scored
          .take(limit)
          .where((r) => (r['score'] as double) > 0)
          .toList();

      // Build response
      final formattedResults = <Map<String, dynamic>>[];
      for (final result in topResults) {
        final item = result['item'] as MediaItem;
        final score = result['score'] as double;

        // Get channel name if available
        String channelName = 'Unknown';
        if (item.channelId.isNotEmpty) {
          final channel = await channelRepo.getByUuid(item.channelId);
          if (channel != null) {
            channelName = channel.name;
          }
        }

        formattedResults.add({
          'mediaItemId': item.uuid,
          'title': item.title,
          'channelName': channelName,
          'format': item.format,
          'similarity': (score * 100).round() / 100, // Round to 2 decimals
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
        'note':
            'Results ranked by keyword similarity. Semantic search coming soon.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Simple similarity score based on keyword overlap (0-1)
  double _computeSimilarity(String text, String query) {
    if (text.isEmpty || query.isEmpty) return 0;

    final textLower = text.toLowerCase();
    final queryWords = query.split(' ');

    int matches = 0;
    for (final word in queryWords) {
      if (word.isNotEmpty && textLower.contains(word)) {
        matches++;
      }
    }

    return matches / queryWords.length;
  }
}
