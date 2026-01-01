/// # Media Search Providers
///
/// Riverpod providers for semantic media search functionality.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Media search result
class SearchResult {
  final String mediaItemId;
  final String title;
  final String channelName;
  final double similarity;
  final String format;
  final String? downloadedAt;
  final String? description;
  final int? duration;

  SearchResult({
    required this.mediaItemId,
    required this.title,
    required this.channelName,
    required this.similarity,
    required this.format,
    this.downloadedAt,
    this.description,
    this.duration,
  });

  /// Parse from SearchHandler response
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      mediaItemId: json['mediaItemId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      channelName: json['channelName'] as String? ?? 'Unknown',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
      format: json['format'] as String? ?? '',
      downloadedAt: json['downloadedAt'] as String?,
      description: json['description'] as String?,
      duration: json['duration'] as int?,
    );
  }
}

/// Search state
class SearchState {
  final bool isLoading;
  final List<SearchResult> results;
  final String? error;
  final String? lastQuery;

  SearchState({
    this.isLoading = false,
    this.results = const [],
    this.error,
    this.lastQuery,
  });

  SearchState copyWith({
    bool? isLoading,
    List<SearchResult>? results,
    String? error,
    String? lastQuery,
  }) {
    return SearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error,
      lastQuery: lastQuery ?? this.lastQuery,
    );
  }
}

/// Search state notifier
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(SearchState());

  /// Perform semantic search
  Future<void> search(
    String query, {
    String? format,
    String? channelId,
    int limit = 20,
  }) async {
    if (query.isEmpty) {
      state = state.copyWith(
        results: [],
        error: null,
        lastQuery: query,
        isLoading: false,
      );
      return;
    }

    // Search handler not yet implemented - Phase 2
    state = state.copyWith(
      error: 'Search not available. Media repositories not yet exposed via Riverpod.',
      isLoading: false,
    );
  }

  /// Clear search results
  void clear() {
    state = SearchState();
  }
}

/// Provider for search state
///
/// NOTE: Media repositories are not yet exposed via Riverpod.
/// In Phase 2, integrate with bootstrap's service registry.
final mediaSearchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(); // TODO: Get handler from bootstrap in Phase 2
});
