import 'chunk.dart';
import '../../core/base_entity.dart';

/// # SemanticSearchResult
///
/// ## What it does
/// Represents a single result from semantic search.
/// Contains the matched chunk, source entity, and similarity score.
/// (Renamed from SearchResult to avoid collision with HNSW SearchResult)
///
/// ## What it enables
/// - Return matched text fragments (chunks) to user
/// - Show which entity the chunk came from
/// - Display confidence (similarity score)
/// - Reconstruct context from token positions
///
/// ## Usage
/// ```dart
/// final results = await semanticSearchService.search('AI models');
///
/// for (final result in results) {
///   print('Match: ${result.chunk.config} chunk');
///   print('Score: ${(result.similarity * 100).toStringAsFixed(1)}%');
///   print('Source: ${result.sourceEntity.title}');
///   print('Context: ${result.chunk.startToken}-${result.chunk.endToken}');
/// }
/// ```
///
/// ## Similarity Score
/// Range: [0.0, 1.0]
/// - 1.0 = identical to query
/// - 0.5 = moderately similar
/// - 0.0 = completely different
///
/// Calculated from HNSW cosine distance:
/// similarity = 1.0 - distance (since HNSW returns distance, not similarity)

class SemanticSearchResult {
  /// The matched chunk with token positions
  final Chunk chunk;

  /// The source entity this chunk came from
  /// Can be null if entity was deleted (should rarely happen)
  final BaseEntity? sourceEntity;

  /// Similarity score between query and this chunk
  /// Range: [0.0, 1.0]
  /// 1.0 = identical, 0.0 = completely different
  final double similarity;

  SemanticSearchResult({
    required this.chunk,
    required this.sourceEntity,
    required this.similarity,
  }) {
    // Validate similarity is in valid range
    if (similarity < 0.0 || similarity > 1.0) {
      throw ArgumentError(
        'similarity must be between 0.0 and 1.0, got $similarity',
      );
    }
  }

  /// Get human-readable similarity percentage
  String get similarityPercent =>
      '${(similarity * 100).toStringAsFixed(1)}%';

  @override
  String toString() =>
      'SearchResult(${chunk.config} chunk from ${sourceEntity?.uuid ?? "unknown"}, similarity: $similarity)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemanticSearchResult &&
          runtimeType == other.runtimeType &&
          chunk == other.chunk &&
          sourceEntity?.uuid == other.sourceEntity?.uuid &&
          similarity == other.similarity;

  @override
  int get hashCode =>
      chunk.hashCode ^ (sourceEntity?.uuid.hashCode ?? 0) ^ similarity.hashCode;
}
