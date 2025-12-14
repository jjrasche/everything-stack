import 'chunk.dart';

/// Strategy interface for text chunking algorithms
///
/// Implementations define how to split text into semantically coherent chunks.
/// Different strategies optimize for different use cases:
///
/// - **Semantic chunking**: Groups text by semantic similarity (best for unstructured content)
/// - **Recursive splitting**: Splits by delimiters with fallback (simple, deterministic)
/// - **Fixed-size**: Equal-sized chunks with overlap (fast, no NLP needed)
///
/// Everything Stack uses semantic chunking as the primary strategy because:
/// 1. Use case alignment: Unstructured content (voice transcriptions, rambling notes)
/// 2. Research-backed: 70% retrieval improvement over recursive for unstructured text
/// 3. Marginal complexity: Reuses existing embedding infrastructure
abstract class ChunkingStrategy {
  /// Split text into chunks
  ///
  /// Returns a list of [Chunk] objects representing semantic segments of the text.
  /// Chunks should:
  /// - Maintain semantic coherence (related content stays together)
  /// - Target optimal size for retrieval (128-200 tokens for Everything Stack)
  /// - Respect guardrails (minimum and maximum sizes)
  ///
  /// Implementations may generate embeddings for chunks if needed for similarity
  /// calculation during chunking. Whether embeddings are stored in the returned
  /// chunks depends on the strategy.
  Future<List<Chunk>> chunk(String text);

  /// Name of this chunking strategy for logging and debugging
  String get name;
}
