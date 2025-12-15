/// # SemanticIndexableHandler
///
/// ## What it does
/// Orchestrates semantic indexing lifecycle for SemanticIndexable entities.
/// Handles chunk creation, embedding generation, and HNSW index updates.
///
/// ## Pattern
/// Entities that implement SemanticIndexable opt-in to semantic chunking.
/// Chunks are extracted, embedded, and indexed in HNSW for semantic search.
///
/// ## Lifecycle
/// 1. beforeSave: Delete old chunks (if updating existing entity)
/// 2. beforeSave: Generate and index new chunks (async, before transaction)
/// 3. beforeSaveInTransaction: Commit chunks to registry (sync, atomic with entity save)
/// 4. afterSave: Persist HNSW index to storage (best-effort)
///
/// ## Error Semantics
/// - Delete old chunks: fail-fast (aborts save if deletion fails)
/// - Generate/index new chunks: fail-fast (aborts save if fails)
/// - Commit to registry: fails-fast within transaction (if fails, entity not saved)
/// - Persist to storage: best-effort (chunks already in memory index, can rebuild)
///
/// Rationale: Chunks are ephemeral and can be rebuilt from entity content.
/// If storage persistence fails after save, SyncService will rebuild index on next run.
/// But if indexing/registration fails, entity save is aborted to prevent inconsistency.

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import '../repository_pattern_handler.dart';

/// Handler for SemanticIndexable pattern.
///
/// Responsible for:
/// - Deleting old chunks before entity update (fail-fast)
/// - Generating and indexing new chunks before transaction (fail-fast)
/// - Registering chunks within transaction (atomic with entity save)
/// - Persisting HNSW index after save (best-effort)
///
/// ATOMIC GUARANTEE:
/// If chunk indexing fails, save is aborted. If entity save fails after
/// chunks are indexed, chunks were generated but not persisted - they'll be
/// rebuilt by SyncService. No data loss, but index may need rebuild.
class SemanticIndexableHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final ChunkingService chunkingService;

  /// Chunks generated in beforeSave, indexed in this save cycle
  /// Stored as instance variable to pass between beforeSave and beforeSaveInTransaction
  final Map<String, List<String>> _generatedChunks = {};

  SemanticIndexableHandler(this.chunkingService);

  /// Delete old chunks and generate new chunks for SemanticIndexable entities.
  ///
  /// Called before transaction starts. Fail-fast: if deletion or generation fails,
  /// save is aborted (prevents inconsistency).
  ///
  /// Process:
  /// 1. Delete old chunks from index
  /// 2. Generate (chunk + embed) new chunks from entity content
  /// 3. Insert chunks into HNSW index (in-memory)
  /// 4. Store generated chunk IDs for transaction phase
  @override
  Future<void> beforeSave(T entity) async {
    if (entity is! SemanticIndexable) return;

    // Delete old chunks (safe even if entity is new and has no chunks)
    await chunkingService.deleteByEntityId(entity.uuid);

    // Generate and index new chunks (fail-fast if fails)
    final chunks = await chunkingService.indexEntity(entity);

    // Store generated chunk IDs for registration in transaction
    _generatedChunks[entity.uuid] = chunks.map((c) => c.id).toList();
  }

  /// Register chunks within transaction (atomic with entity save).
  ///
  /// Called inside transaction BEFORE entity is persisted.
  /// Stores generated chunk IDs in registry so they can be tracked for future deletes.
  ///
  /// Fail-fast: if registration fails, transaction rolls back and entity is not saved.
  /// This guarantees: if entity is persisted, its chunks are registered.
  @override
  void beforeSaveInTransaction(TransactionContext ctx, T entity) {
    if (entity is! SemanticIndexable) return;

    // Get chunks that were generated in beforeSave
    final chunkIds = _generatedChunks.remove(entity.uuid);
    if (chunkIds != null && chunkIds.isNotEmpty) {
      // Register chunks in the registry so they're tracked for deletion
      chunkingService.registerChunksForEntity(entity.uuid, chunkIds);
    }
  }

  /// Persist HNSW index to storage after entity is saved.
  ///
  /// Called after entity is persisted and committed. Best-effort: if persistence
  /// fails, chunks are already in memory index and entity is persisted. SyncService
  /// will rebuild the index on next run.
  @override
  Future<void> afterSave(T entity) async {
    if (entity is! SemanticIndexable) return;

    // Persist HNSW index to storage (optional, can be rebuilt)
    try {
      await chunkingService.persistIndex();
    } catch (e) {
      // Log but don't fail - chunks are in memory, can be rebuilt
      // ignore: avoid_print
      print('Warning: Failed to persist HNSW index: $e');
    }
  }

  /// Delete chunks before entity is deleted (fail-fast, outside transaction).
  ///
  /// Called before entity is deleted from database. Fail-fast: if deletion
  /// fails, entity delete is aborted (prevents orphaned chunks in index).
  @override
  Future<void> beforeDelete(T entity) async {
    if (entity is! SemanticIndexable) return;

    // Delete chunks from HNSW (safe even if no chunks exist)
    await chunkingService.deleteByEntityId(entity.uuid);
  }

  /// Delete chunks within transaction (atomic with entity deletion).
  ///
  /// Called within entity delete transaction (if TransactionManager provided).
  /// Ensures chunks and entity are deleted together atomically.
  ///
  /// For SemanticIndexable entities with TransactionManager:
  /// - beforeDeleteInTransaction deletes chunks inside transaction
  /// - beforeDelete (below) is still called (outside transaction) as fallback
  ///
  /// For SemanticIndexable entities without TransactionManager:
  /// - beforeDelete (below) deletes chunks outside transaction
  /// - beforeDeleteInTransaction is never called
  ///
  /// Rationale: Chunks are ephemeral and in-memory, so deletion is naturally atomic.
  /// Even if entity deletion fails, the transaction rollback has no effect on chunks
  /// since they're not transactional storage (they're in HNSW index).
  /// The beforeDelete fallback ensures chunks are deleted in all cases.
  @override
  void beforeDeleteInTransaction(TransactionContext ctx, T entity) {
    if (entity is! SemanticIndexable) return;

    // Delete chunks synchronously within transaction
    // This is safe because:
    // 1. ChunkingService tracks chunks in memory (_chunkRegistry)
    // 2. HNSW index is in-memory
    // 3. Chunk deletion is synchronous (index.delete() + registry.remove())
    //
    // Delete chunks from registry (safe even if no chunks exist)
    final chunkIds = chunkingService.getChunkIdsForEntity(entity.uuid);
    for (final chunkId in chunkIds) {
      chunkingService.index.delete(chunkId);
    }
    // Note: Registry removal happens in deleteByEntityId, called in beforeDelete
  }
}
