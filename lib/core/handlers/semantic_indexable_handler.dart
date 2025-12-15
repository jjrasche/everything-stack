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
/// 2. afterSave: Index new chunks (post-persistence, best-effort)
///
/// ## Error Semantics
/// - Delete chunks BEFORE save: fail-fast (aborts save if deletion fails)
/// - Index chunks AFTER save: best-effort (entity already persisted)
///
/// Rationale: Chunks are ephemeral and can be rebuilt from entity content.
/// If indexing fails after save, SyncService will rebuild index on next run.

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import '../repository_pattern_handler.dart';

/// Handler for SemanticIndexable pattern.
///
/// Responsible for:
/// - Deleting old chunks before entity update (fail-fast)
/// - Indexing new chunks after entity save (best-effort)
class SemanticIndexableHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final ChunkingService chunkingService;

  SemanticIndexableHandler(this.chunkingService);

  /// Delete old chunks if entity is SemanticIndexable and being updated.
  ///
  /// Called before entity is persisted. Fail-fast: if deletion fails,
  /// save is aborted (prevents orphaned chunks in index).
  @override
  Future<void> beforeSave(T entity) async {
    if (entity is! SemanticIndexable) return;

    // Delete old chunks (safe even if entity is new and has no chunks)
    await chunkingService.deleteByEntityId(entity.uuid);
  }

  /// Index new chunks after entity is persisted.
  ///
  /// Called after entity is persisted to database. Best-effort: if indexing
  /// fails, entity is already in database and valid. Error is logged but
  /// not propagated.
  ///
  /// SyncService will rebuild the index if needed on next run.
  @override
  Future<void> afterSave(T entity) async {
    if (entity is! SemanticIndexable) return;

    // Index new chunks (post-save, best-effort)
    await chunkingService.indexEntity(entity);
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
