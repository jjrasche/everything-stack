/// ## Relationship to Embeddable
/// - **Embeddable:** Single embedding for whole entity (semantic matching)
/// - **SemanticIndexable:** Multiple chunks + embeddings per entity (text search)
/// - Can be used together or separately
/// - Both use same EmbeddingService and HNSW index
///
/// ## Usage
/// ```dart
/// class Note extends BaseEntity with SemanticIndexable {
///   String title;
///   String content;
///
///   @override
///   String toChunkableInput() => '$title\n$content';
///
///   @override
///   String getChunkingConfig() => 'parent';  // or 'child'
/// }
///
/// // On save: ChunkingService automatically chunks and indexes
/// await noteRepository.save(note);
///
/// // On search
/// final results = await semanticSearchService.search('budget planning');
/// // Returns notes with matching chunks
/// ```
///
/// ## Chunking Strategy
/// Entities choose their chunking preset:
/// - **'parent'** (default): ~200 tokens per chunk
///   - Use for: AI context, summarization, broad retrieval
/// - **'child'**: ~25 tokens per chunk
///   - Use for: Human scanning, precise snippets
/// - Both are indexed in the same HNSW space
/// - Search returns results from both levels mixed
///
/// ## Integration Points
/// - ChunkingService detects SemanticIndexable on entity save
/// - Chunks are generated, embedded, and indexed automatically
/// - Repository lifecycle hooks trigger chunking
/// - SemanticSearchService uses HNSW to find chunks

mixin SemanticIndexable {
  /// Define what text represents this entity for chunking.
  /// This is what gets divided into chunks.
  ///
  /// Examples:
  /// - Note: title + content
  /// - Article: headline + body
  /// - Meeting: transcript
  /// - Email: subject + body
  ///
  /// Consider: What would someone search for to find this?
  String toChunkableInput();

  /// Return the chunking configuration for this entity.
  /// Returns 'parent' or 'child' (or custom config name in future).
  ///
  /// Decision factors:
  /// - **'parent'** (~200 tokens): Better for AI, more context, fewer chunks
  /// - **'child'** (~25 tokens): Better for humans, scannable, more chunks
  /// - Can vary per entity: urgent notes use child, archives use parent
  ///
  /// Default: 'parent' (most entities should use this)
  String getChunkingConfig();

  /// Check if entity needs re-chunking.
  /// Override if you track content changes.
  /// Default: always rechunk on save (safe but may be expensive).
  bool get needsReChunking => true;
}
