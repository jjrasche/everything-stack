/// # Media Search Screen
///
/// Semantic search interface for downloaded media.
/// Users can search by meaning - query "how do computers work" finds videos about computing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/ui/providers/media_search_providers.dart';

class MediaSearchScreen extends ConsumerStatefulWidget {
  const MediaSearchScreen({super.key});

  @override
  ConsumerState<MediaSearchScreen> createState() => _MediaSearchScreenState();
}

class _MediaSearchScreenState extends ConsumerState<MediaSearchScreen> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(mediaSearchProvider);
    final notifier = ref.read(mediaSearchProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Media'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by meaning... e.g., "how does AI work?"',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          notifier.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (query) {
                if (query.isNotEmpty) {
                  notifier.search(query);
                }
              },
            ),
          ),

          // Search button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _searchController.text.isEmpty
                    ? null
                    : () {
                        notifier.search(_searchController.text);
                        // Unfocus keyboard
                        FocusScope.of(context).unfocus();
                      },
                icon: searchState.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(searchState.isLoading ? 'Searching...' : 'Search'),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Results or empty state
          Expanded(
            child: searchState.isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : searchState.error != null
                    ? _ErrorState(error: searchState.error!)
                    : searchState.results.isEmpty
                        ? _EmptyState(query: searchState.lastQuery)
                        : _ResultsList(results: searchState.results),
          ),
        ],
      ),
    );
  }
}

/// Empty state when no search performed or no results
class _EmptyState extends StatelessWidget {
  final String? query;

  const _EmptyState({this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            query == null ? 'Search your media library' : 'No results found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              query == null
                  ? 'Enter a query to find videos by semantic meaning'
                  : 'Try a different search query',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state
class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Search error',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Results list
class _ResultsList extends StatelessWidget {
  final List<SearchResult> results;

  const _ResultsList({required this.results});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: results.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultCard(
          result: result,
          rank: index + 1,
        );
      },
    );
  }
}

/// Individual search result card
class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final int rank;

  const _SearchResultCard({
    required this.result,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rank and title
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getSimilarityColor(result.similarity),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.channelName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Similarity score bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Semantic Match',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '${(result.similarity * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _getSimilarityColor(result.similarity),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: result.similarity,
                    minHeight: 6,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getSimilarityColor(result.similarity),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Metadata
            Row(
              children: [
                if (result.format.isNotEmpty)
                  Chip(
                    label: Text(result.format.toUpperCase()),
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 8),
                if (result.duration != null)
                  Chip(
                    label: Text('${result.duration} min'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),

            // Description if available
            if (result.description != null && result.description!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    result.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Get color based on similarity score
  Color _getSimilarityColor(double similarity) {
    if (similarity >= 0.7) {
      return Colors.green;
    } else if (similarity >= 0.5) {
      return Colors.orange;
    } else if (similarity >= 0.3) {
      return Colors.amber;
    } else {
      return Colors.grey;
    }
  }
}
