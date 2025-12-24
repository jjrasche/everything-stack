/// # Media Search Screen
///
/// Simple semantic search interface for media library.
/// Users enter a search query, system returns semantically similar media items.
///
/// Architecture:
/// - UI: Simple prompt (search input)
/// - Tool: Media semantic search (no UI, handles backend indexing)
/// - Event: Query routed through ContextManager to tool registry

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaSearchScreen extends ConsumerStatefulWidget {
  const MediaSearchScreen({super.key});

  @override
  ConsumerState<MediaSearchScreen> createState() => _MediaSearchScreenState();
}

class _MediaSearchScreenState extends ConsumerState<MediaSearchScreen> {
  late TextEditingController _searchController;
  List<String> _results = [];
  bool _isLoading = false;

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

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // TODO: Wire to ContextManager event-driven architecture
      // For now, placeholder showing where semantic search results would appear
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _results = [
          'Result 1: Semantically similar media item',
          'Result 2: Another matching item',
          'Result 3: Related content',
        ];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Media'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search input (the "prompt")
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search media by meaning...',
              onSubmitted: _performSearch,
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _results = []);
                    },
                  ),
              ],
            ),
          ),

          // Search button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => _performSearch(_searchController.text),
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_isLoading ? 'Searching...' : 'Search'),
            ),
          ),

          const SizedBox(height: 16),

          // Results list
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) => ListTile(
                  leading: Icon(Icons.video_library),
                  title: Text(_results[index]),
                  onTap: () {
                    // TODO: Open media details
                  },
                ),
              ),
            )
          else if (!_isLoading && _searchController.text.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enter a search query',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
            )
          else if (_results.isEmpty && !_isLoading)
            Expanded(
              child: Center(
                child: Text(
                  'No results found',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
