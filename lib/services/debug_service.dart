import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DebugService {
  static final DebugService instance = DebugService._();
  DebugService._();

  final List<Map<String, dynamic>> _recentSearches = [];
  final List<String> _recentErrors = [];
  Map<String, dynamic> _chunkStats = {};
  List<String> _entityLoaderRegistry = [];

  /// Capture a search result for debugging
  void captureSearchResult({
    required String query,
    required List<Map<String, dynamic>> results,
    required int totalChunksInIndex,
    required Duration searchDuration,
  }) {
    _recentSearches.insert(0, {
      'timestamp': DateTime.now().toIso8601String(),
      'query': query,
      'resultCount': results.length,
      'searchDurationMs': searchDuration.inMilliseconds,
      'results': results.take(10).toList(), // First 10 for debugging
    });

    // Keep only last 5 searches
    if (_recentSearches.length > 5) {
      _recentSearches.removeRange(5, _recentSearches.length);
    }

    _writeDebugState();
  }

  /// Capture chunk statistics
  void captureChunkStats({
    required int totalChunks,
    required int uniqueChunkIds,
    required int chunksWithEmbeddings,
    required int chunksWithoutEmbeddings,
    required Map<String, int> chunksByEntityType,
    required Map<String, int> chunksBySourceEntity,
  }) {
    _chunkStats = {
      'timestamp': DateTime.now().toIso8601String(),
      'totalChunks': totalChunks,
      'uniqueChunkIds': uniqueChunkIds,
      'duplicateCount': totalChunks - uniqueChunkIds,
      'chunksWithEmbeddings': chunksWithEmbeddings,
      'chunksWithoutEmbeddings': chunksWithoutEmbeddings,
      'byEntityType': chunksByEntityType,
      'topSourceEntities': _topN(chunksBySourceEntity, 10),
    };

    _writeDebugState();
  }

  /// Capture entity loader registry state
  void captureEntityLoaderState(List<String> registeredTypes) {
    _entityLoaderRegistry = registeredTypes;
    _writeDebugState();
  }

  /// Capture an error for debugging
  void captureError(String context, dynamic error, [StackTrace? stack]) {
    _recentErrors.insert(0, {
      'timestamp': DateTime.now().toIso8601String(),
      'context': context,
      'error': error.toString(),
      'stack': stack?.toString().split('\n').take(10).join('\n'),
    }.toString());

    // Keep only last 10 errors
    if (_recentErrors.length > 10) {
      _recentErrors.removeRange(10, _recentErrors.length);
    }

    _writeDebugState();
  }

  /// Write current debug state to file
  Future<void> _writeDebugState() async {
    try {
      final state = {
        'lastUpdated': DateTime.now().toIso8601String(),
        'entityLoaderRegistry': _entityLoaderRegistry,
        'chunkStats': _chunkStats,
        'recentSearches': _recentSearches,
        'recentErrors': _recentErrors,
      };

      final file = File('logs/debug-state.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(state),
      );
    } catch (e) {
      // Don't let debug logging break the app
      print('⚠️ DebugService: Failed to write state: $e');
    }
  }

  /// Get top N entries from a map by value
  Map<String, int> _topN(Map<String, int> map, int n) {
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries.take(n));
  }
}
