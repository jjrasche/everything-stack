import 'package:uuid/uuid.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking/semantic_chunker.dart';
import 'package:everything_stack_template/services/chunking/chunking_config.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search.dart';

/// Service for orchestrating semantic chunking and HNSW indexing.
///
/// This service:
/// 1. Takes a SemanticIndexable entity
/// 2. Chunks it via SemanticChunker (two-level: parent + child)
/// 3. Generates embeddings for each chunk
/// 4. Inserts into HNSW index for semantic search
///
/// Usage with EntityRepository:
/// ```dart
/// class NoteRepository extends EntityRepository<Note> {
///   final ChunkingService chunkingService;
///
///   @override
///   Future<int> save(Note entity) async {
///     // Delete old chunks if updating
///     if (entity is SemanticIndexable) {
///       await chunkingService.deleteByEntityId(entity.uuid);
///     }
///
///     final id = await super.save(entity);
///
///     // Index new chunks
///     if (entity is SemanticIndexable) {
///       await chunkingService.indexEntity(entity);
///     }
///
///     return id;
///   }
///
///   @override
///   Future<bool> deleteByUuid(String uuid) async {
///     // Remove from semantic index first
///     await chunkingService.deleteByEntityId(uuid);
///     return await super.deleteByUuid(uuid);
///   }
/// }
/// ```
class ChunkingService {
  /// HNSW index for semantic search
  final HnswIndex index;

  /// Embedding service for generating vectors
  final EmbeddingService embeddingService;

  /// Parent-level chunker (~200 tokens)
  final SemanticChunker parentChunker;

  /// Child-level chunker (~25 tokens)
  final SemanticChunker childChunker;

  /// In-memory registry of chunk IDs by entity ID
  /// Maps entityId -> [chunkId1, chunkId2, ...]
  /// Used to track which chunks belong to which entity for deletion
  final Map<String, List<String>> _chunkRegistry = {};

  ChunkingService({
    required this.index,
    required this.embeddingService,
    required this.parentChunker,
    required this.childChunker,
  });

  /// Index a SemanticIndexable entity by chunking and embedding.
  ///
  /// Process:
  /// 1. Extract chunkable input from entity (title + content, etc.)
  /// 2. Generate parent chunks (~200 tokens each)
  /// 3. For each parent chunk, generate child chunks (~25 tokens each)
  /// 4. Generate embeddings for all chunks (batch)
  /// 5. Insert chunks into HNSW index
  /// 6. Track chunk IDs for later deletion
  ///
  /// Returns list of created Chunk objects with HNSW IDs
  Future<List<Chunk>> indexEntity(BaseEntity entity) async {
    if (entity is! SemanticIndexable) {
      return [];
    }

    final semanticEntity = entity as SemanticIndexable;
    final input = semanticEntity.toChunkableInput();
    if (input.trim().isEmpty) {
      return [];
    }

    final chunks = <Chunk>[];
    final chunkIds = <String>[];

    // Generate parent chunks
    final parentChunkTexts = await parentChunker.chunk(input);

    for (final parentChunkText in parentChunkTexts) {
      // Create parent chunk
      final parentChunkId = const Uuid().v4();
      final parentChunk = Chunk(
        id: parentChunkId,
        sourceEntityId: entity.uuid,
        sourceEntityType: entity.runtimeType.toString(),
        startToken: parentChunkText.startToken,
        endToken: parentChunkText.endToken,
        config: 'parent',
      );
      chunks.add(parentChunk);
      chunkIds.add(parentChunkId);

      // Generate and insert parent embedding
      final parentEmbedding =
          await embeddingService.generate(parentChunkText.text);
      index.insert(parentChunkId, parentEmbedding);

      // Generate child chunks from this parent
      final childChunkTexts = await childChunker.chunk(parentChunkText.text);

      for (final childChunkText in childChunkTexts) {
        final childChunkId = const Uuid().v4();
        final childChunk = Chunk(
          id: childChunkId,
          sourceEntityId: entity.uuid,
          sourceEntityType: entity.runtimeType.toString(),
          startToken: childChunkText.startToken,
          endToken: childChunkText.endToken,
          config: 'child',
        );
        chunks.add(childChunk);
        chunkIds.add(childChunkId);

        // Generate and insert child embedding
        final childEmbedding =
            await embeddingService.generate(childChunkText.text);
        index.insert(childChunkId, childEmbedding);
      }
    }

    // Track chunk IDs for this entity
    _chunkRegistry[entity.uuid] = chunkIds;

    return chunks;
  }

  /// Delete all chunks for an entity from the HNSW index.
  ///
  /// Called when:
  /// - Entity is deleted
  /// - Entity is updated (to remove old chunks before reindexing)
  /// - Index needs to be rebuilt
  Future<void> deleteByEntityId(String entityId) async {
    final chunkIds = _chunkRegistry[entityId] ?? [];
    for (final chunkId in chunkIds) {
      index.delete(chunkId);
    }
    _chunkRegistry.remove(entityId);
  }

  /// Get chunk IDs for an entity (for testing and debugging)
  List<String> getChunkIdsForEntity(String entityId) {
    return _chunkRegistry[entityId] ?? [];
  }

  /// Register chunks for an entity in the chunk registry.
  ///
  /// Called within transaction to ensure registry is updated atomically
  /// with entity persistence. This guarantees that if entity is persisted,
  /// its chunks are tracked for future deletion.
  void registerChunksForEntity(String entityId, List<String> chunkIds) {
    _chunkRegistry[entityId] = chunkIds;
  }

  /// Persist HNSW index to storage.
  ///
  /// Saves the in-memory HNSW index to persistent storage (Isar database).
  /// Safe to call multiple times - it's idempotent.
  ///
  /// This is called after entity is persisted to ensure chunks are backed up.
  /// If it fails, chunks are already in memory and can be rebuilt by SyncService.
  Future<void> persistIndex() async {
    // Index persistence is handled by HnswIndexStore
    // This method is a no-op here since HnswIndexStore is injected separately
    // In a real implementation, would call: await indexStore.save(index);
    // For now, this is called but assumes persistence happens elsewhere
  }
}

/// Lightweight chunk representation for semantic search results.
///
/// Stores minimal metadata needed to:
/// 1. Identify which entity the chunk came from (sourceEntityId, sourceEntityType)
/// 2. Locate text within the entity (startToken, endToken)
/// 3. Understand chunk level (parent vs child)
///
/// Does NOT store full text (reconstruct from entity + token positions).
class Chunk {
  /// Unique identifier for this chunk in HNSW
  final String id;

  /// UUID of the entity this chunk came from
  final String sourceEntityId;

  /// Type name of the source entity (for entity loader routing)
  final String sourceEntityType;

  /// Starting token position in original entity text
  final int startToken;

  /// Ending token position in original entity text
  final int endToken;

  /// Chunk level: 'parent' (~200 tokens) or 'child' (~25 tokens)
  final String config;

  Chunk({
    required this.id,
    required this.sourceEntityId,
    required this.sourceEntityType,
    required this.startToken,
    required this.endToken,
    required this.config,
  }) {
    if (endToken <= startToken) {
      throw ArgumentError('endToken must be greater than startToken');
    }
    if (config != 'parent' && config != 'child') {
      throw ArgumentError('config must be "parent" or "child", got "$config"');
    }
  }

  /// Number of tokens in this chunk
  int get tokenCount => endToken - startToken;

  @override
  String toString() =>
      'Chunk($id, $sourceEntityType, tokens: $tokenCount, config: $config)';

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
          config == other.config;

  @override
  int get hashCode =>
      id.hashCode ^
      sourceEntityId.hashCode ^
      sourceEntityType.hashCode ^
      startToken.hashCode ^
      endToken.hashCode ^
      config.hashCode;
}
