/// Configuration for semantic chunking behavior
///
/// Allows flexible tuning of the chunking algorithm without changing the core logic.
/// Supports multiple chunking levels (parent/child) with different parameters.
///
/// **Example usage:**
/// ```dart
/// // Parent level: Large chunks, broad semantic boundaries
/// final parentConfig = ChunkingConfig.parent(
///   windowSize: 200,
///   overlap: 50,
///   minChunkSize: 128,
///   maxChunkSize: 400,
/// );
///
/// // Child level: Small chunks, granular semantic boundaries
/// final childConfig = ChunkingConfig.child(
///   windowSize: 30,
///   overlap: 10,
///   minChunkSize: 10,
///   maxChunkSize: 60,
/// );
/// ```
class ChunkingConfig {
  /// Window size for sliding windows (tokens)
  ///
  /// For unpunctuated text, determines the size of each segment
  /// that gets embedded for similarity comparison.
  ///
  /// Typical range: 30-200 tokens
  /// - Smaller windows (30-50): Granular topic detection, more chunks
  /// - Larger windows (150-200): Coarse topic detection, fewer chunks
  final int windowSize;

  /// Overlap between consecutive sliding windows (tokens)
  ///
  /// Ensures continuity in topic detection across window boundaries.
  ///
  /// Typical range: 10% to 25% of window size
  /// - `windowSize=200, overlap=50` (25% overlap)
  /// - `windowSize=30, overlap=10` (33% overlap)
  final int overlap;

  /// Minimum chunk size in tokens
  ///
  /// Chunks smaller than this are merged with adjacent chunks.
  /// This ensures chunks have sufficient context for meaningful retrieval.
  ///
  /// Recommended: 10-50% of windowSize
  final int minChunkSize;

  /// Maximum chunk size in tokens (hard limit)
  ///
  /// Chunks larger than this are split further, even at semantic boundaries.
  /// This prevents chunks from becoming too large and diluting relevance.
  ///
  /// Recommended: 50-100% of windowSize, but at least 2x minChunkSize
  final int maxChunkSize;

  /// Similarity threshold for detecting semantic boundaries (0.0 to 1.0)
  ///
  /// If cosine similarity between adjacent segments drops below this,
  /// consider it a topic boundary and split there.
  ///
  /// Typical range: 0.3-0.7
  /// - Lower (0.3-0.4): Stricter boundaries, more chunks
  /// - Higher (0.6-0.7): Looser boundaries, fewer chunks
  /// - Standard (0.5): Balanced
  final double similarityThreshold;

  /// Name for logging and debugging (e.g., "parent", "child")
  final String name;

  ChunkingConfig({
    required this.windowSize,
    required this.overlap,
    required this.minChunkSize,
    required this.maxChunkSize,
    required this.similarityThreshold,
    this.name = 'default',
  }) {
    _validate();
  }

  /// Parent-level configuration
  ///
  /// Optimized for detecting broad topic boundaries in unstructured content.
  /// Produces larger chunks suitable for first-pass semantic search.
  ///
  /// Parameters:
  /// - 200-token windows for coarse topic detection
  /// - 128-400 token chunks for broad semantic grouping
  /// - 0.5 similarity threshold (balanced)
  factory ChunkingConfig.parent({
    int windowSize = 200,
    int overlap = 50,
    int minChunkSize = 128,
    int maxChunkSize = 400,
    double similarityThreshold = 0.5,
  }) {
    return ChunkingConfig(
      windowSize: windowSize,
      overlap: overlap,
      minChunkSize: minChunkSize,
      maxChunkSize: maxChunkSize,
      similarityThreshold: similarityThreshold,
      name: 'parent',
    );
  }

  /// Child-level configuration
  ///
  /// Optimized for granular semantic chunking within parent chunks.
  /// Produces small, focused chunks for precise retrieval.
  ///
  /// Parameters:
  /// - 30-token windows for fine-grained topic detection
  /// - 10-60 token chunks for precise semantic units
  /// - 0.5 similarity threshold (balanced, but can be increased for stricter boundaries)
  factory ChunkingConfig.child({
    int windowSize = 30,
    int overlap = 10,
    int minChunkSize = 10,
    int maxChunkSize = 60,
    double similarityThreshold = 0.5,
  }) {
    return ChunkingConfig(
      windowSize: windowSize,
      overlap: overlap,
      minChunkSize: minChunkSize,
      maxChunkSize: maxChunkSize,
      similarityThreshold: similarityThreshold,
      name: 'child',
    );
  }

  /// Validate configuration constraints
  void _validate() {
    if (windowSize <= 0) {
      throw ArgumentError('windowSize must be positive');
    }
    if (overlap < 0 || overlap >= windowSize) {
      throw ArgumentError('overlap must be between 0 and windowSize-1');
    }
    if (minChunkSize <= 0) {
      throw ArgumentError('minChunkSize must be positive');
    }
    if (maxChunkSize <= minChunkSize) {
      throw ArgumentError('maxChunkSize must be greater than minChunkSize');
    }
    if (similarityThreshold < 0 || similarityThreshold > 1) {
      throw ArgumentError('similarityThreshold must be between 0 and 1');
    }
  }

  /// Create a copy with updated properties
  ChunkingConfig copyWith({
    int? windowSize,
    int? overlap,
    int? minChunkSize,
    int? maxChunkSize,
    double? similarityThreshold,
    String? name,
  }) {
    return ChunkingConfig(
      windowSize: windowSize ?? this.windowSize,
      overlap: overlap ?? this.overlap,
      minChunkSize: minChunkSize ?? this.minChunkSize,
      maxChunkSize: maxChunkSize ?? this.maxChunkSize,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      name: name ?? this.name,
    );
  }

  @override
  String toString() {
    return 'ChunkingConfig($name: window=$windowSize, overlap=$overlap, '
        'chunks=$minChunkSize-$maxChunkSize, threshold=$similarityThreshold)';
  }
}
