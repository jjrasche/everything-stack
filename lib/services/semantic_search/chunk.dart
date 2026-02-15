/// # Chunk
///
/// ## What it does
/// Represents a semantic chunk of text extracted from an entity.
/// Chunks are lightweight models (not BaseEntity) used for search results.
///
/// ## What it enables
/// - Store text fragments in HNSW index
/// - Reconstruct context from source entity + token positions
/// - Track which entity and chunking strategy produced this chunk
/// - Return search results with precise context
///
/// ## Storage
/// Persisted to database with embedding vector for fast index rebuild.
/// Chunks are:
/// - Generated when entity is saved (ChunkingService)
/// - Stored with their embedding vectors
/// - Deleted when entity is updated
/// - Loaded on startup to rebuild HNSW index (no API calls needed)
///
/// ## Key Design
/// - Full text + embedding stored for fast rebuild
/// - sourceEntityType stored (avoids registry lookup)
/// - UUID id doubles as HNSW index key
/// - Token range enables context reconstruction
///
/// ## Usage
/// ```dart
/// final chunk = Chunk(
///   id: 'uuid-123',
///   sourceEntityId: 'note-456',
///   sourceEntityType: 'Note',
///   startToken: 10,
///   endToken: 110,
///   config: 'parent',
///   text: 'chunk text here',
///   embedding: [0.1, 0.2, ...], // 384-dimensional vector
/// );
/// ```

class Chunk {
  /// Unique identifier for this chunk (UUID).
  /// Also used as key in HNSW index.
  final String id;

  /// UUID of the entity this chunk came from.
  /// e.g., note UUID, article UUID, etc.
  final String sourceEntityId;

  /// Type of source entity.
  /// e.g. "Note", "Article", "Meeting"
  /// Used to determine which repository to query for the entity.
  final String sourceEntityType;

  /// Start position in token range.
  /// Inclusive - this token is part of the chunk.
  final int startToken;

  /// End position in token range.
  /// Exclusive - this token is NOT part of the chunk.
  final int endToken;

  /// Chunking configuration used to create this chunk.
  /// "parent" = large chunks (~200 tokens) for context
  /// "child" = small chunks (~25 tokens) for scanning
  final String config;

  /// Full chunk text (needed for reconstruction after HNSW search)
  final String text;

  /// Embedding vector for this chunk (384 dimensions for Jina).
  /// Persisted to avoid regenerating on app restart.
  final List<double>? embedding;

  Chunk({
    required this.id,
    required this.sourceEntityId,
    required this.sourceEntityType,
    required this.startToken,
    required this.endToken,
    required this.config,
    required this.text,
    this.embedding,
  }) {
    // Validate token range
    if (startToken < 0) {
      throw ArgumentError('startToken must be >= 0');
    }
    if (endToken <= startToken) {
      throw ArgumentError('endToken must be > startToken');
    }
    if (config != 'parent' && config != 'child' && config != 'invocation') {
      throw ArgumentError('config must be "parent", "child", or "invocation"');
    }
    if (text.isEmpty) {
      throw ArgumentError('text cannot be empty');
    }
  }

  /// Number of tokens in this chunk
  int get tokenCount => endToken - startToken;

  @override
  String toString() =>
      'Chunk(id: $id, source: $sourceEntityType/$sourceEntityId, tokens: $startToken-$endToken, config: $config)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chunk &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceEntityId == other.sourceEntityId &&
          sourceEntityType == other.sourceEntityType &&
          startToken == other.startToken &&
          endToken == other.endToken &&
          config == other.config &&
          text == other.text;
  // Note: embedding excluded from equality (too expensive to compare)

  @override
  int get hashCode =>
      id.hashCode ^
      sourceEntityId.hashCode ^
      sourceEntityType.hashCode ^
      startToken.hashCode ^
      endToken.hashCode ^
      config.hashCode ^
      text.hashCode;

  /// Create a copy with embedding added
  Chunk copyWithEmbedding(List<double> embedding) => Chunk(
        id: id,
        sourceEntityId: sourceEntityId,
        sourceEntityType: sourceEntityType,
        startToken: startToken,
        endToken: endToken,
        config: config,
        text: text,
        embedding: embedding,
      );
}
