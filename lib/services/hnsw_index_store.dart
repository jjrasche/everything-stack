/// ## Why persist the index?
/// Without persistence, startup rebuilds from database chunks (O(n log n)):
/// 10K chunks = ~2 minutes. With persistence, deserialization is O(n):
/// 10K chunks = ~100ms.
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
