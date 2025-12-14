/// # Semantic Search Service Module
///
/// Complete infrastructure for semantic search across entities:
/// - Chunk: Lightweight text fragments with token positions
/// - SemanticIndexable: Mixin for entities to opt-in to semantic indexing
/// - SemanticSearchService: Query engine for finding chunks by meaning
/// - SearchResult: Results with chunk + entity + similarity score
///
/// ## Quick Start
/// ```dart
/// // 1. Make entity searchable
/// class Note extends BaseEntity with SemanticIndexable {
///   String toChunkableInput() => '$title\n$content';
///   String getChunkingConfig() => 'parent';
/// }
///
/// // 2. Chunks are auto-generated on save (via ChunkingService)
///
/// // 3. Search across all entities
/// final results = await searchService.search('machine learning');
/// // Returns: List<SemanticSearchResult> with chunks + entities + scores
/// ```
///
/// ## Two-Level Indexing
/// - **Parent chunks** (~200 tokens): AI context, fewer results
/// - **Child chunks** (~25 tokens): Human readable, scannable, more results
/// - Both indexed in same HNSW space
/// - Search returns results from both levels

export 'chunk.dart';
export 'search_result.dart';
export 'semantic_search_service.dart';
