/// Configurable parameters for semantic chunking granularity (parent vs child level).
class ChunkingConfig {
  /// Size of sliding window for segmenting text (in tokens)
  ///
  /// Larger windows detect coarser topic boundaries, producing fewer, larger chunks.
  /// Smaller windows detect finer boundaries, producing more, smaller chunks.
  final int windowSize;

  /// Overlap between consecutive windows (in tokens)
  ///
  /// Ensures topic boundaries between windows are not missed. Typically 25-33%
  /// of windowSize.
  final int overlap;

  /// Minimum chunk size (in tokens)
  ///
  /// Chunks smaller than this are merged with adjacent chunks.
  /// Soft limit - overridden by semantic boundaries if needed.
  final int minChunkSize;

  /// Maximum chunk size (in tokens)
  ///
  /// Hard limit - chunks will be split if they exceed this.
  /// Never violated except for single segments smaller than max.
  final int maxChunkSize;

  /// Similarity threshold for detecting topic boundaries
  ///
  /// When embedding similarity between adjacent segments drops below this threshold,
  /// a topic boundary is detected. Range: 0.0-1.0
  /// Higher values (0.7-0.9) = stricter boundaries
  /// Lower values (0.3-0.5) = looser boundaries
  final double similarityThreshold;

  /// Name of this configuration (for logging and debugging)
  final String name;

  ChunkingConfig({
    required this.windowSize,
    required this.overlap,
    required this.minChunkSize,
    required this.maxChunkSize,
    required this.similarityThreshold,
    this.name = 'custom',
  }) {
    if (overlap >= windowSize) {
      throw ArgumentError('Overlap must be less than windowSize');
    }
    if (minChunkSize < 1) {
      throw ArgumentError('minChunkSize must be at least 1');
    }
    if (maxChunkSize < minChunkSize) {
      throw ArgumentError('maxChunkSize must be >= minChunkSize');
    }
    if (similarityThreshold < 0.0 || similarityThreshold > 1.0) {
      throw ArgumentError('similarityThreshold must be between 0.0 and 1.0');
    }
  }

  /// Parent-level configuration for broad topic detection
  ///
  /// Use for document structure and topic transitions.
  /// Produces ~6 chunks from 50 paragraphs (avg 383 tokens).
  factory ChunkingConfig.parent() {
    return ChunkingConfig(
      windowSize: 200,
      overlap: 50,
      minChunkSize: 128,
      maxChunkSize: 400,
      similarityThreshold: 0.5,
      name: 'parent',
    );
  }

  /// Child-level configuration for fine-grained semantic units
  ///
  /// Use for query-level retrieval and precise search results.
  /// Produces ~74 chunks from 6 parent chunks (avg 46 tokens).
  factory ChunkingConfig.child() {
    return ChunkingConfig(
      windowSize: 30,
      overlap: 10,
      minChunkSize: 10,
      maxChunkSize: 60,
      similarityThreshold: 0.5,
      name: 'child',
    );
  }

  /// Invocation-level configuration for whole conversation turns
  ///
  /// Use for VoiceTraits retrieval - complete examples for few-shot learning.
  /// Produces 1 chunk per conversation turn (query + response as a unit).
  /// Settings are designed to rarely split:
  /// - Very large maxChunkSize (2000 tokens)
  /// - Very low similarityThreshold (0.1 = almost never detects boundary)
  factory ChunkingConfig.invocation() {
    return ChunkingConfig(
      windowSize: 1000,
      overlap: 0,
      minChunkSize: 1,
      maxChunkSize: 2000,
      similarityThreshold: 0.1, // Rarely triggers a split
      name: 'invocation',
    );
  }

  @override
  String toString() =>
      'ChunkingConfig($name: window=$windowSize, overlap=$overlap)';
}
