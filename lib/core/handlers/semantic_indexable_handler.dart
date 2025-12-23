/// # SemanticIndexableHandler
///
/// ## What it does
/// Orchestrates semantic chunking and indexing for SemanticIndexable entities.
/// Chunks text into segments and creates embeddings for semantic search.
///
/// ## Pattern
/// Entities that implement SemanticIndexable opt-in to semantic indexing.
/// Chunks are generated, embedded, and indexed automatically on save.
///
/// ## Lifecycle
/// beforeSave: Delete old chunks (if entity already persisted)
/// afterSave: Create new chunks and index them (best-effort, fail-safe)
///
/// ## Error Semantics
/// Ephemeral: If chunking/indexing fails after save, entity is persisted.
/// Chunks exist in database but index may be incomplete.
/// Recovery: SyncService will rebuild index on next run.

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import '../repository_pattern_handler.dart';

/// Handler for SemanticIndexable pattern.
///
/// Responsible for:
/// - Deleting old chunks before entity update (cleanup)
/// - Creating and indexing new chunks after entity save (best-effort)
class SemanticIndexableHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final ChunkingService chunkingService;

  SemanticIndexableHandler(this.chunkingService);

  /// Delete old chunks before saving updated entity.
  ///
  /// Called before entity is persisted. Safe to fail - if chunk deletion
  /// fails, we still proceed with save. New chunks will be created in afterSave.
  @override
  Future<void> beforeSave(T entity) async {
    if (entity is! SemanticIndexable) return;
    if (entity.id == null) return; // New entity, no old chunks to delete

    // Delete old chunks for this entity
    await chunkingService.deleteByEntityId(entity.uuid);
  }

  /// Create and index new chunks after entity is persisted.
  ///
  /// Called after entity is persisted. Best-effort: failures are logged
  /// but don't affect entity persistence. Entity is already in database.
  ///
  /// Failures here are recoverable - SyncService can rebuild index.
  @override
  Future<void> afterSave(T entity) async {
    if (entity is! SemanticIndexable) return;

    try {
      // Create chunks from entity content and index them
      await chunkingService.indexEntity(entity);
    } catch (e) {
      // Log but don't rethrow - entity is persisted and valid
      // Index can be rebuilt later by SyncService
      print('Warning: Failed to chunk entity ${entity.uuid}: $e');
    }
  }

  /// Delete chunks when entity is deleted.
  ///
  /// Called before entity is deleted. Safe to fail - if chunk deletion
  /// fails, we still proceed with entity deletion.
  @override
  Future<void> beforeDelete(T entity) async {
    if (entity is! SemanticIndexable) return;

    try {
      await chunkingService.deleteByEntityId(entity.uuid);
    } catch (e) {
      // Log but don't rethrow - entity deletion should proceed
      print('Warning: Failed to delete chunks for ${entity.uuid}: $e');
    }
  }
}
