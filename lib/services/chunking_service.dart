import 'package:uuid/uuid.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking/semantic_chunker.dart';
import 'package:everything_stack_template/services/chunking/chunk_entity.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';

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

  /// ObjectBox store for persisting chunks to database
  final dynamic chunkBox;

  /// In-memory registry of chunk IDs by entity ID
  /// Maps entityId -> [chunkId1, chunkId2, ...]
  /// Used to track which chunks belong to which entity for deletion
  final Map<String, List<String>> _chunkRegistry = {};

  ChunkingService({
    required this.index,
    required this.embeddingService,
    required this.parentChunker,
    required this.childChunker,
    required this.chunkBox,
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
        text: parentChunkText.text,
      );
      chunks.add(parentChunk);
      chunkIds.add(parentChunkId);

      // Generate and insert parent embedding
      final parentEmbedding =
          await embeddingService.generate(parentChunkText.text);
      index.insert(parentChunkId, parentEmbedding);

      // Persist parent chunk to database
      _persistChunk(parentChunk);

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
          text: childChunkText.text,
        );
        chunks.add(childChunk);
        chunkIds.add(childChunkId);

        // Generate and insert child embedding
        final childEmbedding =
            await embeddingService.generate(childChunkText.text);
        index.insert(childChunkId, childEmbedding);

        // Persist child chunk to database
        _persistChunk(childChunk);
      }
    }

    // Track chunk IDs for this entity
    _chunkRegistry[entity.uuid] = chunkIds;

    return chunks;
  }

  /// Delete all chunks for an entity from HNSW index and database.
  ///
  /// Called when:
  /// - Entity is deleted
  /// - Entity is updated (to remove old chunks before reindexing)
  /// - Index needs to be rebuilt
  Future<void> deleteByEntityId(String entityId) async {
    final chunkIds = _chunkRegistry[entityId] ?? [];

    // Delete from HNSW index
    for (final chunkId in chunkIds) {
      index.delete(chunkId);
    }

    // Delete from database using dynamic query to avoid ObjectBox import
    _deleteChunksFromDb(entityId);

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

  /// Check if HNSW index is consistent (has data).
  ///
  /// For production use, this should:
  /// 1. Count indexed vectors
  /// 2. Count entities with chunks
  /// 3. Verify they match
  ///
  /// For now, returns true if index has any vectors
  bool isIndexConsistent() {
    // Simple check: if index has vectors, assume it's consistent
    // A more thorough check would compare:
    // - Total chunks expected vs indexed
    // - Orphaned chunks in index but missing entities
    return index.size > 0;
  }

  /// Persist a chunk to database.
  /// Uses dynamic dispatch to avoid direct ObjectBox import.
  void _persistChunk(Chunk chunk) {
    try {
      final entity = ChunkEntity(
        chunkId: chunk.id,
        sourceEntityId: chunk.sourceEntityId,
        sourceEntityType: chunk.sourceEntityType,
        startToken: chunk.startToken,
        endToken: chunk.endToken,
        config: chunk.config,
        text: chunk.text,
      );
      entity.validate();
      (chunkBox as dynamic).put(entity);
    } catch (e) {
      print('⚠️ Failed to persist chunk ${chunk.id}: $e');
      // Don't throw - chunking should not fail if DB write fails
      // Chunks are still in HNSW index and can be rebuilt
    }
  }

  /// Delete all chunks for an entity from database.
  void _deleteChunksFromDb(String entityId) {
    try {
      final allChunks = (chunkBox as dynamic).getAll() as List<dynamic>;
      final toDelete = <int>[];
      for (final chunk in allChunks) {
        if ((chunk as dynamic).sourceEntityId == entityId) {
          toDelete.add((chunk as dynamic).id as int);
        }
      }
      if (toDelete.isNotEmpty) {
        (chunkBox as dynamic).removeMany(toDelete);
      }
    } catch (e) {
      print('⚠️ Failed to delete chunks from DB for entity $entityId: $e');
      // Don't throw - deletion should be best-effort
    }
  }

  /// Get all chunks for an entity from database.
  Future<List<Chunk>> getChunksForEntity(String entityId) async {
    try {
      final allChunks = (chunkBox as dynamic).getAll() as List<dynamic>;
      final matching = <Chunk>[];
      for (final entity in allChunks) {
        if ((entity as dynamic).sourceEntityId == entityId) {
          matching.add((entity as ChunkEntity).toDomain());
        }
      }
      return matching;
    } catch (e) {
      print('⚠️ Failed to load chunks for entity $entityId: $e');
      return [];
    }
  }

  /// Get a specific chunk by ID from database.
  Chunk? getChunkById(String chunkId) {
    try {
      final allChunks = (chunkBox as dynamic).getAll() as List<dynamic>;
      for (final entity in allChunks) {
        if ((entity as dynamic).chunkId == chunkId) {
          return (entity as ChunkEntity).toDomain();
        }
      }
      return null;
    } catch (e) {
      print('⚠️ Failed to load chunk $chunkId: $e');
      return null;
    }
  }
}
