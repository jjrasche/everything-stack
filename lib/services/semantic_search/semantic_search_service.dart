import 'chunk.dart';
import 'search_result.dart';
import '../embedding_service.dart';
import '../hnsw_index.dart';
import '../../core/base_entity.dart';

/// ## Design decisions
/// - Entity loading is async (database queries)
/// - Results ordered by similarity descending
/// - Deleted entities return null but don't crash search
/// - No caching (embeddings are cheap, entities are small)
/// - **Index consistency is enforced (fail-fast if stale)**

class SemanticSearchService {
  /// HNSW index storing chunk embeddings
  final HnswIndex index;

  /// Embedding service for generating query vectors
  final EmbeddingService embeddingService;

  /// Entity loader for reconstructing source entities
  /// Abstracts over multiple repositories
  final EntityLoader entityLoader;

  /// Chunking service for index consistency checks
  /// Optional - if provided, search verifies index consistency before returning results
  final dynamic chunkingService;

  SemanticSearchService({
    required this.index,
    required this.embeddingService,
    required this.entityLoader,
    this.chunkingService,
  });

  /// Search for chunks similar to query.
  ///
  /// Parameters:
  /// - [query]: Text to search for (will be embedded)
  /// - [entityTypes]: Filter to specific entity types (null = all)
  /// - [limit]: Maximum number of results (default: 10)
  ///
  /// Returns: Ranked list of SemanticSearchResult (highest similarity first)
  ///
  /// Throws: StateError if index is stale or inconsistent
  /// Throws: If query embedding generation fails
  ///
  /// CONSISTENCY GUARANTEE:
  /// Before returning results, verifies that HNSW index is consistent with
  /// entity data. If stale, throws StateError rather than returning incomplete
  /// results. This prevents silent data loss.
  Future<List<SemanticSearchResult>> search(
    String query, {
    List<String>? entityTypes,
    int limit = 10,
  }) async {
    // Verify index consistency BEFORE search
    // If stale, fail fast rather than return incomplete results
    if (chunkingService != null) {
      final isConsistent = (chunkingService as dynamic).isIndexConsistent();
      if (!isConsistent) {
        throw StateError('HNSW semantic index is stale or missing. '
            'Search is disabled to prevent incomplete results. '
            'Call rebuildIndex() to repair the index and enable search.');
      }
    }

    final queryEmbedding = await embeddingService.generate(query);

    final hnswResults = index.search(queryEmbedding, k: limit * 2);
    if (hnswResults.isEmpty) {
      return [];
    }

    // Look up chunk metadata from ChunkingService database store
    final chunks = await _reconstructChunks(hnswResults.take(limit).toList());

    final entityMap = <String, BaseEntity?>{};
    for (final chunk in chunks) {
      if (!entityMap.containsKey(chunk.sourceEntityId)) {
        final entity = await entityLoader.getById(
          chunk.sourceEntityId,
          entityType: chunk.sourceEntityType,
        );
        entityMap[chunk.sourceEntityId] = entity;
      }
    }

    var results = <SemanticSearchResult>[];
    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final hnswResult = hnswResults[i];

      final similarity = 1.0 - hnswResult.distance;

      if (entityTypes != null) {
        if (!entityTypes.contains(chunk.sourceEntityType)) {
          continue;
        }
      }

      final entity = entityMap[chunk.sourceEntityId];
      results.add(SemanticSearchResult(
        chunk: chunk,
        sourceEntity: entity,
        similarity: similarity,
      ));
    }

    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    final finalResults = results.take(limit).toList();

    return finalResults;
  }

  /// Reconstruct chunks from HNSW search results.
  /// Looks up chunk metadata from ChunkingService's database store.
  Future<List<Chunk>> _reconstructChunks(List<SearchResult> hnswResults) async {
    final chunks = <Chunk>[];

    for (final result in hnswResults) {
      final chunkId = result.id;

      if (chunkingService != null) {
        final chunk = await (chunkingService as dynamic).getChunkById(chunkId);
        if (chunk != null) {
          chunks.add(chunk);
        }
      }
    }

    return chunks;
  }
}

/// Abstract entity loader for cross-repository lookups.
///
/// Any SemanticIndexable entity can be chunked and indexed.
/// When semantic search returns chunks, this loader resolves
/// the sourceEntityId back to the actual entity.
///
/// Implementations should register repositories for each entity type
/// that participates in semantic indexing.
abstract class EntityLoader {
  /// Load entity by UUID, optionally filtering by type.
  ///
  /// Parameters:
  /// - [uuid]: The entity's unique identifier
  /// - [entityType]: Optional type hint to query the correct repository first.
  ///   If null, searches all registered repositories.
  ///
  /// Returns null if not found in any repository.
  Future<BaseEntity?> getById(String uuid, {String? entityType});
}
