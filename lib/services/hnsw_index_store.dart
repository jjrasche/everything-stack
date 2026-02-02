/// # HNSW Index Store
///
/// Persists the serialized HNSW index to avoid rebuilding on every startup.
///
/// ## What it does
/// - Saves serialized HNSW index bytes to persistent storage
/// - Loads index from storage if available
/// - Validates loaded index integrity
///
/// ## Why it matters
/// Without persistence: App startup rebuilds index from database chunks (O(n log n))
/// - 10K chunks = ~2 minutes
/// - 100K chunks = ~20 minutes
///
/// With persistence: App startup loads pre-built index (O(n) deserialize)
/// - 10K chunks = ~100ms
/// - 100K chunks = ~1 second
///
/// ## Platform support
/// - Native (Android, iOS, macOS, Windows, Linux): File-based storage
/// - Web: Falls back to rebuild (can be optimized with IndexedDB later)
///
/// ## Usage
/// ```dart
/// // In bootstrap (native platforms):
/// final indexStore = HnswIndexStore(basePath: objectBoxDirectory);
/// final cached = await indexStore.loadIndex();
/// if (cached != null) {
///   hnswIndex = cached;
/// } else {
///   await chunkingService.rebuildIndexFromStorage();
///   await indexStore.saveIndex(hnswIndex);
/// }
/// ```

import 'hnsw_index.dart';

/// Metadata about a cached HNSW index
class HnswIndexMetadata {
  final DateTime savedAt;
  final int sizeBytes;
  final int vectorCount;

  HnswIndexMetadata({
    required this.savedAt,
    required this.sizeBytes,
    required this.vectorCount,
  });

  @override
  String toString() =>
      'HnswIndexMetadata(savedAt: $savedAt, size: ${(sizeBytes / 1024 / 1024).toStringAsFixed(1)}MB, vectors: $vectorCount)';
}

/// Result of loading an index
class IndexLoadResult {
  final HnswIndex? index;
  final HnswIndexMetadata? metadata;
  final String? error;

  IndexLoadResult.success(this.index, this.metadata) : error = null;
  IndexLoadResult.notFound() : index = null, metadata = null, error = null;
  IndexLoadResult.failed(this.error) : index = null, metadata = null;

  bool get isLoaded => index != null;
  bool get notFound => index == null && error == null;
  bool get hasFailed => error != null;
}

/// Abstract interface for HNSW index persistence
///
/// Implementations provided by platform-specific files:
/// - hnsw_index_store_native.dart (Android, iOS, macOS, Windows, Linux)
/// - hnsw_index_store_web.dart (Web - stub that returns not found)
abstract class HnswIndexStore {
  /// Save index to persistent storage
  Future<void> saveIndex(HnswIndex index);

  /// Load index from persistent storage
  /// Returns IndexLoadResult with:
  /// - success: index loaded successfully
  /// - notFound: no cached index exists
  /// - failed: error occurred during load
  Future<IndexLoadResult> loadIndex();

  /// Delete the cached index
  Future<void> clear();

  /// Check if cached index exists and get metadata
  Future<HnswIndexMetadata?> getMetadata();
}
