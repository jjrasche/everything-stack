/// Lifecycle hooks for domain patterns (Embeddable, Versionable, SemanticIndexable).
///
/// ## Why separate handler from pattern mixin
/// Handlers orchestrate pattern-specific logic at save/delete boundaries without
/// scattering conditional checks throughout EntityRepository. Each pattern is a
/// separate handler composed into a chain.
///
/// ## Why two error semantics exist
/// **Ephemeral patterns** (SemanticIndexable): Can fail in afterSave() because
/// index is rebuildable. **Atomic patterns** (Versionable): Must use
/// beforeSaveInTransaction() because entity without version history is corruption.

import 'base_entity.dart';
import 'persistence/transaction_context.dart';

/// Handler lifecycle interface for domain patterns.
///
/// Handlers integrate pattern-specific logic without scattering throughout
/// EntityRepository. Each handler owns its own lifecycle.
abstract class RepositoryPatternHandler<T extends BaseEntity> {
  /// Called before entity is persisted to database.
  ///
  /// **Fail-fast semantics:** If this throws, save() is aborted.
  /// Entity is NOT persisted.
  ///
  /// Use for:
  /// - Validation that prevents persistence
  /// - Pre-processing that must succeed (e.g., delete old chunks)
  /// - Setup that requires synchronous behavior
  ///
  /// **Do NOT use for:**
  /// - Post-save operations (use afterSave instead)
  /// - Async operations (use beforeSaveInTransaction for transactional async)
  Future<void> beforeSave(T entity) async {}

  /// Called after entity is persisted to database (outside transaction).
  ///
  /// **Best-effort semantics:** If this throws, entity is already persisted.
  /// Error is logged but NOT propagated.
  ///
  /// Use for:
  /// - Index updates (ephemeral, can be rebuilt)
  /// - External notifications
  /// - Cleanup that can fail without corrupting entity
  ///
  /// **Do NOT use for:**
  /// - Operations that must succeed atomically (use beforeSaveInTransaction)
  /// - Pre-persistence operations (use beforeSave instead)
  Future<void> afterSave(T entity) async {}

  /// Called within transaction BEFORE entity is persisted (synchronous).
  ///
  /// **Transactional semantics:** If this throws, transaction rolls back.
  /// Entity is NOT persisted.
  ///
  /// Use for:
  /// - Synchronous operations that must be atomic with entity save
  /// - Version recording
  /// - Edge creation
  /// - Pre-persistence state that must succeed or fail together
  ///
  /// **Important:** This is SYNCHRONOUS. Async operations must use
  /// try-catch internally or this becomes the async bottleneck.
  ///
  /// **Only called if:**
  /// - EntityRepository has TransactionManager
  /// - Handler needs atomicity with entity save
  ///
  /// **Do NOT use for:**
  /// - External async operations (network, file I/O)
  /// - Index operations (use afterSave for those)
  void beforeSaveInTransaction(TransactionContext ctx, T entity) {}

  /// Called within transaction AFTER entity is persisted (synchronous).
  ///
  /// **Transactional semantics:** If this throws, transaction rolls back.
  ///
  /// Use for:
  /// - Synchronous operations that depend on entity having been persisted
  /// - Post-persist state updates
  ///
  /// **Important:** This is SYNCHRONOUS within transaction.
  ///
  /// **Only called if:**
  /// - EntityRepository has TransactionManager
  /// - Handler needs post-persistence atomicity
  void afterSaveInTransaction(TransactionContext ctx, T entity) {}

  /// Called before entity is deleted from database (outside transaction).
  ///
  /// **Fail-fast semantics:** If this throws, delete() is aborted.
  /// Entity is NOT deleted.
  ///
  /// Use for:
  /// - Pre-delete validation
  /// - Cleanup that must succeed before deletion
  ///
  /// **Do NOT use for:**
  /// - Operations that must be atomic (use beforeDeleteInTransaction)
  /// - Post-delete operations (EntityRepository doesn't call afterDelete)
  Future<void> beforeDelete(T entity) async {}

  /// Called within transaction BEFORE entity is deleted (synchronous).
  ///
  /// **Transactional semantics:** If this throws, transaction rolls back.
  /// Entity is NOT deleted.
  ///
  /// Use for:
  /// - Cleanup that must be atomic with entity deletion
  /// - Cascade deletes (edges, chunks)
  /// - Pre-delete state that must succeed or fail together with entity
  ///
  /// **Important:** This is SYNCHRONOUS. Async operations must use
  /// try-catch internally or this becomes the async bottleneck.
  ///
  /// **Only called if:**
  /// - EntityRepository has TransactionManager
  /// - Handler needs atomicity with entity delete
  ///
  /// **Do NOT use for:**
  /// - External async operations (network, file I/O)
  /// - Non-atomic cleanup (use beforeDelete for those)
  void beforeDeleteInTransaction(TransactionContext ctx, T entity) {}

  /// Called within transaction AFTER entity is deleted (synchronous).
  ///
  /// **Transactional semantics:** If this throws, transaction rolls back.
  ///
  /// Use for:
  /// - Synchronous operations that depend on entity having been deleted
  /// - Post-delete state updates
  ///
  /// **Important:** This is SYNCHRONOUS within transaction.
  ///
  /// **Only called if:**
  /// - EntityRepository has TransactionManager
  /// - Handler needs post-delete atomicity
  void afterDeleteInTransaction(TransactionContext ctx, T entity) {}

  /// Called after entity is deleted from database (outside transaction).
  ///
  /// **Note:** EntityRepository only calls beforeDelete, NOT afterDelete.
  /// Handlers should not override this - it exists only for completeness
  /// if EntityRepository implementation changes.
  ///
  /// If you need post-delete cleanup: do it in beforeDelete (before
  /// entity is deleted), not afterDelete.
  Future<void> afterDelete(T entity) async {}
}

/// Factory interface for creating handlers for an entity type.
/// Controls which handlers are wired and in what execution order.
abstract class RepositoryHandlerFactory<T extends BaseEntity> {
  /// Create list of handlers in execution order.
  ///
  /// Order matters:
  /// - SemanticIndexable first: delete old chunks before save
  /// - Embeddable middle: lightweight, can fail in afterSave
  /// - Versionable last: atomic, needs transactional hooks
  List<RepositoryPatternHandler<T>> createHandlers();
}
