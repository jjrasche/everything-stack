/// # RepositoryPatternHandler
///
/// ## What it does
/// Abstract interface for entities that implement domain patterns (Embeddable,
/// Versionable, SemanticIndexable) to provide lifecycle hooks for save/delete.
///
/// Handlers orchestrate pattern-specific logic without scattering conditional
/// checks throughout EntityRepository. Each pattern is a separate handler that
/// can be composed into a chain.
///
/// ## Pattern Design
/// - **Composition over inheritance:** Patterns are optional mixins on entities
/// - **Lifecycle hooks:** Handlers integrate at save/delete boundaries
/// - **Transactional safety:** Handlers declare their atomicity requirements
/// - **Error semantics:** Pre-save fails fast, post-save is best-effort
///
/// ## Handler Execution Order (per EntityRepository contract)
/// 1. beforeSave (pre-entity-persistence, fail-fast)
/// 2. beforeSaveInTransaction (only if TransactionManager provided, sync)
/// 3. [Entity persisted to database]
/// 4. afterSaveInTransaction (only if TransactionManager provided, sync)
/// 5. afterSave (post-entity-persistence, best-effort)
///
/// ## Atomicity Semantics
///
/// **Ephemeral patterns** (SemanticIndexable):
/// - Chunks exist in database but index is ephemeral
/// - If indexing fails after save: entity is persisted, chunks are deleted
/// - Recovery: SyncService will rebuild index on next run
/// - Handler: Can fail safely in afterSave()
///
/// **Atomic patterns** (Versionable):
/// - Version record must exist with entity
/// - If version fails after save: CORRUPTION (entity without version history)
/// - Solution: Use beforeSaveInTransaction() to record version inside entity save transaction
/// - Handler: Must use transactional hooks, NOT afterSave()
///
/// ## Example: MultiPattern Entity
///
/// ```dart
/// class Note extends BaseEntity with Embeddable, SemanticIndexable, Versionable {
///   // ...
/// }
///
/// // Repository creates handlers in order:
/// List<RepositoryPatternHandler<Note>> handlers = [
///   SemanticIndexableHandler(chunkingService),  // Ephemeral, can fail
///   EmbeddableHandler(embeddingService),        // Lightweight, best-effort
///   VersionableHandler(versionRepo),            // Atomic, transactional
/// ];
///
/// // Save flow:
/// // 1. SemanticIndexableHandler.beforeSave() - delete old chunks
/// // 2. EmbeddableHandler.beforeSave() - (no-op)
/// // 3. VersionableHandler.beforeSave() - (no-op)
/// // 4. Transaction starts (if TransactionManager)
/// // 5. VersionableHandler.beforeSaveInTransaction() - record version inside tx
/// // 6. Entity.save()
/// // 7. VersionableHandler.afterSaveInTransaction() - (no-op)
/// // 8. Transaction commits
/// // 9. EmbeddableHandler.afterSave() - (no-op)
/// // 10. SemanticIndexableHandler.afterSave() - index chunks
/// ```
///
/// ## Usage
///
/// Create handler for your pattern:
///
/// ```dart
/// class YourPatternHandler<T extends BaseEntity> extends RepositoryPatternHandler<T> {
///   final YourService service;
///
///   YourPatternHandler({required this.service});
///
///   @override
///   Future<void> beforeSave(T entity) async {
///     // Pre-persistence logic - fail-fast
///     if (entity is YourPattern) {
///       await service.validate(entity);  // Can throw
///     }
///   }
///
///   @override
///   Future<void> afterSave(T entity) async {
///     // Post-persistence logic - best-effort
///     if (entity is YourPattern) {
///       try {
///         await service.process(entity);  // Best-effort, log failures
///       } catch (e) {
///         logger.warning('Failed to process pattern', e);
///         // Entity is persisted and valid - don't throw
///       }
///     }
///   }
/// }
/// ```
///
/// Wire in repository factory:
///
/// ```dart
/// class NoteHandlerFactory {
///   List<RepositoryPatternHandler<Note>> createHandlers({
///     required EmbeddingService embeddingService,
///     required ChunkingService chunkingService,
///     required VersionRepository versionRepository,
///   }) {
///     return [
///       SemanticIndexableHandler(chunkingService),
///       EmbeddableHandler(embeddingService),
///       VersionableHandler(versionRepository),
///     ];
///   }
/// }
/// ```

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
  /// - Post-delete operations (EntityRepository doesn't call afterDelete)
  Future<void> beforeDelete(T entity) async {}

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
///
/// Repositories implement this to control which handlers are wired and
/// in what order they execute.
///
/// ## Wiring Strategy
///
/// Each repository's factory decides:
/// 1. Which patterns this entity implements
/// 2. Which handlers to instantiate
/// 3. Handler execution order
/// 4. Service dependencies for each handler
///
/// ## Example
///
/// ```dart
/// class NoteHandlerFactory {
///   final EmbeddingService? embeddingService;
///   final ChunkingService? chunkingService;
///   final VersionRepository? versionRepository;
///
///   NoteHandlerFactory({
///     this.embeddingService,
///     this.chunkingService,
///     this.versionRepository,
///   });
///
///   List<RepositoryPatternHandler<Note>> createHandlers() {
///     return [
///       if (chunkingService != null)
///         SemanticIndexableHandler(chunkingService!),
///       if (embeddingService != null)
///         EmbeddableHandler(embeddingService!),
///       if (versionRepository != null)
///         VersionableHandler(versionRepository!),
///     ];
///   }
/// }
/// ```
///
/// Wire in repository:
///
/// ```dart
/// class NoteRepository extends EntityRepository<Note> {
///   NoteRepository({
///     required PersistenceAdapter<Note> adapter,
///     EmbeddingService? embeddingService,
///     ChunkingService? chunkingService,
///     VersionRepository? versionRepository,
///   }) : super(
///     adapter: adapter,
///     handlers: NoteHandlerFactory(
///       embeddingService: embeddingService,
///       chunkingService: chunkingService,
///       versionRepository: versionRepository,
///     ).createHandlers(),
///   );
/// }
/// ```
abstract class RepositoryHandlerFactory<T extends BaseEntity> {
  /// Create list of handlers in execution order.
  ///
  /// Order matters:
  /// - SemanticIndexable first: delete old chunks before save
  /// - Embeddable middle: lightweight, can fail in afterSave
  /// - Versionable last: atomic, needs transactional hooks
  List<RepositoryPatternHandler<T>> createHandlers();
}
