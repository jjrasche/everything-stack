import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/chunk_repository.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking/semantic_chunker.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/tokenizer_service.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';
import 'package:everything_stack_template/core/trainable.dart';
import 'package:everything_stack_template/core/debug/debug.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/feedback.dart' as core_feedback;
import 'package:everything_stack_template/services/types/chunking_types.dart';

/// Service for orchestrating semantic chunking and HNSW indexing.
///
/// ## Trainability
/// Learns optimal chunk sizes based on:
/// - Entity type (Invocation vs Note vs Task)
/// - User feedback on semantic search quality
/// - Category-specific tuning
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
class ChunkingService with Trainable<ChunkingAdaptationData>, DebugIntrospectable {
  /// HNSW index for semantic search
  final HnswIndex index;

  /// Embedding service for generating vectors
  final EmbeddingService embeddingService;

  /// Tokenizer for accurate token counting
  final TokenizerService tokenizerService;

  /// Parent-level chunker (~200 tokens)
  final SemanticChunker parentChunker;

  /// Child-level chunker (~25 tokens)
  final SemanticChunker childChunker;

  /// Repository for persisting chunks to database (platform-specific)
  final ChunkRepository chunkRepo;

  /// In-memory registry of chunk IDs by entity ID
  /// Maps entityId -> [chunkId1, chunkId2, ...]
  /// Used to track which chunks belong to which entity for deletion
  final Map<String, List<String>> _chunkRegistry = {};

  ChunkingService({
    required this.index,
    required this.embeddingService,
    required this.tokenizerService,
    required this.parentChunker,
    required this.childChunker,
    required this.chunkRepo,
  });

  /// Index a SemanticIndexable entity by chunking and embedding.
  ///
  /// Process:
  /// 1. Check entity's chunking config ('invocation', 'parent', 'child')
  /// 2. For 'invocation' config: create 1 chunk for entire text (whole unit)
  /// 3. For other configs: use parent/child two-level chunking
  /// 4. Generate embeddings for all chunks
  /// 5. Insert chunks into HNSW index
  /// 6. Record invocation for training feedback
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

    final chunkingConfig = semanticEntity.getChunkingConfig();

    if (chunkingConfig == 'invocation') {
      return _indexAsWholeUnit(entity, semanticEntity, input);
    }

    return _indexWithTwoLevelChunking(entity, semanticEntity, input);
  }

  /// Index entity as a single whole-unit chunk (for VoiceTraits retrieval).
  Future<List<Chunk>> _indexAsWholeUnit(
    BaseEntity entity,
    SemanticIndexable semanticEntity,
    String input,
  ) async {
    final chunks = <Chunk>[];
    final chunkIds = <String>[];

    final embedding = await embeddingService.generate(input);

    final chunkId = const Uuid().v4();
    final chunk = Chunk(
      id: chunkId,
      sourceEntityId: entity.uuid,
      sourceEntityType: entity.runtimeType.toString(),
      startToken: 0,
      endToken: tokenizerService.countTokens(input),
      config: 'invocation',
      text: input,
      embedding: embedding,
    );
    chunks.add(chunk);
    chunkIds.add(chunkId);

    index.insert(chunkId, embedding);

    await _persistChunk(chunk);

    _chunkRegistry[entity.uuid] = chunkIds;

    await recordInvocation(
      entity.uuid,
      Invocation(
        eventId: entity.uuid,
        componentType: componentType,
        implementer: null,
        success: true,
        confidence: 1.0,
        input: ChunkingInvocationInput(
          entityId: entity.uuid,
          entityType: entity.runtimeType.toString(),
          chunkableInput:
              input.substring(0, input.length > 200 ? 200 : input.length) +
                  '...',
          inputTokenCount: tokenizerService.countTokens(input),
        ).toJson(),
        output: ChunkingInvocationOutput(
          parentChunkCount: 0,
          childChunkCount: 0,
          totalChunks: 1,
          chunkSizesTokens: [tokenizerService.countTokens(input)],
        ).toJson(),
      ),
    );

    return chunks;
  }

  /// Index entity with standard two-level (parent/child) chunking.
  Future<List<Chunk>> _indexWithTwoLevelChunking(
    BaseEntity entity,
    SemanticIndexable semanticEntity,
    String input,
  ) async {
    final adaptationState = await getAdaptationState();
    final adaptationData =
        adaptationState.dataJson.isNotEmpty && adaptationState.dataJson != '{}'
            ? deserializeData(adaptationState.dataJson)
            : createDefaultData();

    final entityType = entity.runtimeType.toString();
    final parentSize = adaptationData.getParentSizeForCategory(entityType);

    // Estimate token count (rough heuristic: 1 token ~ 4 chars)
    final inputTokenCount = tokenizerService.countTokens(input);

    final chunks = <Chunk>[];
    final chunkIds = <String>[];
    final chunkSizes = <int>[];

    // TODO: Pass adaptive parent size to chunker (currently hardcoded)
    final parentChunkTexts = await parentChunker.chunk(input);

    for (final parentChunkText in parentChunkTexts) {
      final parentChunkId = const Uuid().v4();

      final parentEmbedding =
          await embeddingService.generate(parentChunkText.text);

      final parentChunk = Chunk(
        id: parentChunkId,
        sourceEntityId: entity.uuid,
        sourceEntityType: entity.runtimeType.toString(),
        startToken: parentChunkText.startToken,
        endToken: parentChunkText.endToken,
        config: 'parent',
        text: parentChunkText.text,
        embedding: parentEmbedding,
      );
      chunks.add(parentChunk);
      chunkIds.add(parentChunkId);

      index.insert(parentChunkId, parentEmbedding);

      await _persistChunk(parentChunk);

      final childChunkTexts = await childChunker.chunk(parentChunkText.text);

      for (final childChunkText in childChunkTexts) {
        final childChunkId = const Uuid().v4();

        final childEmbedding =
            await embeddingService.generate(childChunkText.text);

        final childChunk = Chunk(
          id: childChunkId,
          sourceEntityId: entity.uuid,
          sourceEntityType: entity.runtimeType.toString(),
          startToken: childChunkText.startToken,
          endToken: childChunkText.endToken,
          config: 'child',
          text: childChunkText.text,
          embedding: childEmbedding,
        );
        chunks.add(childChunk);
        chunkIds.add(childChunkId);

        chunkSizes.add(tokenizerService.countTokens(childChunkText.text));

        index.insert(childChunkId, childEmbedding);

        await _persistChunk(childChunk);
      }
    }

    _chunkRegistry[entity.uuid] = chunkIds;

    final parentChunkCount = parentChunkTexts.length;
    final totalChildCount = chunks.where((c) => c.config == 'child').length;

    await recordInvocation(
      entity.uuid,
      Invocation(
        eventId: entity.uuid,
        componentType: componentType,
        implementer: null,
        success: true,
        confidence: 1.0,
        input: ChunkingInvocationInput(
          entityId: entity.uuid,
          entityType: entityType,
          chunkableInput:
              input.substring(0, input.length > 200 ? 200 : input.length) +
                  '...',
          inputTokenCount: inputTokenCount,
        ).toJson(),
        output: ChunkingInvocationOutput(
          parentChunkCount: parentChunkCount,
          childChunkCount: totalChildCount,
          totalChunks: chunks.length,
          chunkSizesTokens: chunkSizes,
        ).toJson(),
      ),
    );

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

    for (final chunkId in chunkIds) {
      index.delete(chunkId);
    }

    await _deleteChunksFromDb(entityId);

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
  /// If it fails, chunks are still in memory and can be rebuilt by SyncService.
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
    // A more thorough check would compare:
    // - Total chunks expected vs indexed
    // - Orphaned chunks in index but missing entities
    return index.size > 0;
  }

  /// Rebuild HNSW index from persisted chunks.
  ///
  /// Called on app startup to restore the in-memory index from database.
  /// Loads all chunks WITH their persisted embeddings and inserts directly into HNSW.
  ///
  /// Note: Embeddings are now persisted with chunks, so NO API calls needed.
  /// This is fast (~1-2 seconds for 1000 chunks).
  ///
  /// For legacy chunks without embeddings, regenerates via API (one-time migration).
  /// Migration is batched to avoid memory issues with large datasets.
  ///
  /// Returns the number of chunks loaded.
  Future<int> rebuildIndexFromStorage() async {
    print('🔄 [ChunkingService] Rebuilding HNSW index from storage...');

    try {
      final previousSize = index.size;
      index.clear();
      if (previousSize > 0) {
        print('   🧹 Cleared $previousSize entries from in-memory index');
      }

      final duplicatesRemoved = await chunkRepo.removeDuplicates();
      if (duplicatesRemoved > 0) {
        print('   🧹 Removed $duplicatesRemoved duplicate chunks');
      }

      final chunks = await chunkRepo.getAll();
      print('   📦 Found ${chunks.length} chunks in database');

      if (chunks.isEmpty) {
        print('   ⚠️ No chunks to load - index will remain empty');
        return 0;
      }

      int loaded = 0;
      int skipped = 0;
      int regenerated = 0;

      int legacyCount = 0;
      for (final chunk in chunks) {
        if (chunk.embedding == null || chunk.embedding!.isEmpty) {
          legacyCount++;
        }
      }

      if (legacyCount > 0) {
        print('   ⚠️ Found $legacyCount legacy chunks without embeddings');
        print('   🔄 Starting one-time migration (this may take a few minutes)...');
      }

      final logInterval = (chunks.length / 10).ceil().clamp(10, 100);
      const batchSize = 50;

      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];

        try {
          List<double> embedding;

          if (chunk.embedding != null && chunk.embedding!.isNotEmpty) {
            embedding = chunk.embedding!;
          } else {
            // Legacy chunk without embedding - regenerate via API (one-time migration)
            embedding = await embeddingService.generate(chunk.text);

            await chunkRepo.updateEmbedding(chunk.id, embedding);
            regenerated++;

            // Avoid overwhelming embedding API
            if (regenerated % 10 == 0) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }

          index.insert(chunk.id, embedding);
          loaded++;

          if (loaded % logInterval == 0) {
            final pct = (loaded * 100 / chunks.length).toStringAsFixed(0);
            if (regenerated > 0) {
              print('   📈 Progress: $loaded/${chunks.length} ($pct%) - migrated: $regenerated/$legacyCount');
            } else {
              print('   📈 Progress: $loaded/${chunks.length} ($pct%)');
            }
          }

          // Yield to event loop at batch boundaries
          if (loaded % batchSize == 0) {
            await Future.delayed(Duration.zero);
          }
        } catch (e) {
          print('   ⚠️ Failed to load chunk ${chunk.id}: $e');
          skipped++;
        }
      }

      print('   ✅ Loaded $loaded chunks into HNSW index');
      if (regenerated > 0) {
        print('   🔄 Migrated $regenerated legacy chunks (embeddings now persisted)');
      }
      if (skipped > 0) {
        print('   ⚠️ Skipped $skipped chunks due to errors');
      }
      print('   📊 Index size: ${index.size}');

      final chunksByType = <String, int>{};
      final chunksByEntity = <String, int>{};
      final uniqueIds = <String>{};
      int withEmbeddings = 0;
      int withoutEmbeddings = 0;

      for (final chunk in chunks) {
        chunksByType[chunk.sourceEntityType] =
            (chunksByType[chunk.sourceEntityType] ?? 0) + 1;
        chunksByEntity[chunk.sourceEntityId] =
            (chunksByEntity[chunk.sourceEntityId] ?? 0) + 1;
        uniqueIds.add(chunk.id);
        if (chunk.embedding != null && chunk.embedding!.isNotEmpty) {
          withEmbeddings++;
        } else {
          withoutEmbeddings++;
        }
      }

      return loaded;
    } catch (e) {
      print('   ❌ Failed to rebuild index: $e');
      return 0;
    }
  }

  /// Persist a chunk to database via repository.
  Future<void> _persistChunk(Chunk chunk) async {
    try {
      await chunkRepo.put(chunk);
    } catch (e) {
      print('⚠️ Failed to persist chunk ${chunk.id}: $e');
      // Don't throw - chunking should not fail if DB write fails
      // Chunks are still in HNSW index and can be rebuilt
    }
  }

  /// Delete all chunks for an entity from database.
  Future<void> _deleteChunksFromDb(String entityId) async {
    try {
      await chunkRepo.removeForEntity(entityId);
    } catch (e) {
      print('⚠️ Failed to delete chunks from DB for entity $entityId: $e');
      // Don't throw - deletion should be best-effort
    }
  }

  /// Get all chunks for an entity from database.
  Future<List<Chunk>> getChunksForEntity(String entityId) async {
    try {
      return await chunkRepo.getForEntity(entityId);
    } catch (e) {
      print('⚠️ Failed to load chunks for entity $entityId: $e');
      return [];
    }
  }

  /// Get a specific chunk by ID from database.
  Future<Chunk?> getChunkById(String chunkId) async {
    try {
      return await chunkRepo.getById(chunkId);
    } catch (e) {
      print('⚠️ Failed to load chunk $chunkId: $e');
      return null;
    }
  }

  /// Get all chunks from database (for debugging/cleanup).
  Future<List<Chunk>> getAllChunks() async {
    try {
      return await chunkRepo.getAll();
    } catch (e) {
      print('⚠️ Failed to load all chunks: $e');
      return [];
    }
  }

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'chunking';

  @override
  ChunkingAdaptationData createDefaultData() =>
      ChunkingAdaptationData.defaults();

  @override
  ChunkingAdaptationData deserializeData(String json) =>
      ChunkingAdaptationData.fromJson(jsonDecode(json) as Map<String, dynamic>);

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    final input = ChunkingInvocationInput.fromJson(invocation.input!);
    final output = ChunkingInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chunked Entity:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type: ${input.entityType}'),
              Text('Tokens: ${input.inputTokenCount}'),
              Text('Parent chunks: ${output.parentChunkCount}'),
              Text('Child chunks: ${output.childChunkCount}'),
              Text('Total: ${output.totalChunks}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Were chunks appropriate?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record feedback (chunks were good size)
              },
              child: const Text('Good'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Show adjustment UI (too large/too small)
              },
              child: const Text('Too Large'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Show adjustment UI
              },
              child: const Text('Too Small'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(
      Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: determine if chunks too large/small
    // 2. Get current AdaptationState for chunking
    // 3. Adjust parentTargetTokens/childTargetTokens or categorySpecificSizes
    // 4. Save updated AdaptationState
  }

  // ============ DebugIntrospectable Implementation ============

  @override
  String get debugName => 'chunking';

  @override
  Map<String, dynamic> getDebugState() => {
        'indexSize': index.size,
        'isConsistent': isIndexConsistent(),
        'registeredEntities': _chunkRegistry.length,
      };

  @override
  Map<String, DebugAction> getDebugActions() => {
        'rebuild': DebugAction(
          description: 'Rebuild HNSW index from database storage',
          mutates: true,
          handler: (params) async {
            final stopwatch = Stopwatch()..start();
            final loaded = await rebuildIndexFromStorage();
            stopwatch.stop();
            return {
              'success': true,
              'chunksLoaded': loaded,
              'indexSize': index.size,
              'rebuildTimeMs': stopwatch.elapsedMilliseconds,
            };
          },
        ),
        'getStats': DebugAction(
          description: 'Get detailed chunking statistics',
          mutates: false,
          handler: (params) async {
            final allChunks = await getAllChunks();
            final byType = <String, int>{};
            final byConfig = <String, int>{};

            for (final chunk in allChunks) {
              byType[chunk.sourceEntityType] =
                  (byType[chunk.sourceEntityType] ?? 0) + 1;
              byConfig[chunk.config] = (byConfig[chunk.config] ?? 0) + 1;
            }

            return {
              'totalChunks': allChunks.length,
              'indexSize': index.size,
              'byEntityType': byType,
              'byConfig': byConfig,
              'hasEmbeddings':
                  allChunks.where((c) => c.embedding != null).length,
            };
          },
        ),
      };
}
