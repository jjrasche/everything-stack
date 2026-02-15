import 'chunk.dart';
import '../../core/base_entity.dart';

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
    if (similarity < 0.0 || similarity > 1.0) {
      throw ArgumentError(
        'similarity must be between 0.0 and 1.0, got $similarity',
      );
    }
  }

  /// Get human-readable similarity percentage
  String get similarityPercent => '${(similarity * 100).toStringAsFixed(1)}%';

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
