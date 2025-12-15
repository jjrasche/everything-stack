/// # EntityRepository
///
/// ## What it does
/// Base repository providing common data operations for all entities.
/// Handles CRUD, querying, and cross-cutting concerns like sync.
/// Delegates database operations to PersistenceAdapter.
///
/// ## What it enables
/// - Consistent data access patterns
/// - Semantic search when entity is Embeddable
/// - Automatic sync status management
/// - Cross-type identification via uuid
/// - Database-agnostic: ObjectBox, IndexedDB, etc.
///
/// ## Usage
/// ```dart
/// // Create adapter for your platform
/// final adapter = NoteObjectBoxAdapter(store);  // or NoteIndexedDBAdapter
///
/// class NoteRepository extends EntityRepository<Note> {
///   NoteRepository({required super.adapter, super.embeddingService});
/// }
///
/// final repo = NoteRepository(adapter: adapter);
/// await repo.save(note);  // Auto-generates embedding
/// final results = await repo.semanticSearch('query');
/// ```
///
/// ## Testing approach
/// Test through domain repositories. Verify CRUD operations,
/// query correctness, sync status transitions.

import 'dart:convert';
import 'base_entity.dart';
import 'persistence/persistence_adapter.dart';
import 'persistence/transaction_manager.dart';
import 'persistence/transaction_context.dart';
import 'entity_version.dart';
import 'repository_pattern_handler.dart';
import '../patterns/embeddable.dart';
import '../patterns/versionable.dart';
import '../patterns/semantic_indexable.dart';
import '../services/embedding_service.dart';
import '../services/chunking_service.dart';
import '../utils/json_diff.dart';

abstract class EntityRepository<T extends BaseEntity> {
  /// Persistence adapter for database operations.
  /// Handles storage and vector search.
  final PersistenceAdapter<T> adapter;

  /// Embedding service for generating vectors.
  /// REQUIRED - injected at repository construction time.
  /// Used when entity implements Embeddable pattern.
  final EmbeddingService embeddingService;

  /// Chunking service for semantic indexing (optional).
  /// If provided and entity is SemanticIndexable, chunks are auto-created on save
  /// and auto-deleted on entity delete or update.
  /// If null, SemanticIndexable entities are saved without semantic indexing.
  /// Only repositories for SemanticIndexable entities need to provide this.
  final ChunkingService? chunkingService;

  /// Optional VersionRepository for tracking entity changes.
  /// If provided and entity is Versionable, changes are automatically recorded.
  /// If null, Versionable entities are still saved but changes not versioned.
  final dynamic versionRepository;

  /// Transaction manager for atomic multi-entity operations.
  /// If provided, Versionable entity saves are atomic (entity + version together).
  /// If null, saves are not atomic across repositories.
  final TransactionManager? transactionManager;

  /// Pattern handlers orchestrating lifecycle for each pattern.
  /// Ordered list of handlers that integrate patterns into save/delete flow.
  /// Created by domain repository's handler factory.
  final List<RepositoryPatternHandler<T>> handlers;

  EntityRepository({
    required this.adapter,
    required this.embeddingService,
    ChunkingService? chunkingService,
    this.versionRepository,
    this.transactionManager,
    List<RepositoryPatternHandler<T>>? handlers,
  })  : chunkingService = chunkingService,
        handlers = handlers ?? [];

  /// Object stores this repository accesses in transactions.
  /// Used by IndexedDB to declare transaction scope upfront.
  /// ObjectBox ignores this.
  List<String> get transactionStores => [
        _entityStoreName,
        if (versionRepository != null) 'entity_versions',
      ];

  String get _entityStoreName {
    // Convert type to store name: Note -> 'notes'
    final typeName = T.toString().toLowerCase();
    return typeName.endsWith('s') ? typeName : '${typeName}s';
  }

  // ============ CRUD ============

  /// Find entity by internal database ID.
  Future<T?> findById(int id) async {
    return adapter.findById(id);
  }

  /// Find entity by its UUID (the universal identifier).
  /// Delegates to adapter which uses indexed lookup.
  Future<T?> findByUuid(String uuid) async {
    return adapter.findByUuid(uuid);
  }

  /// Get all entities.
  Future<List<T>> findAll() async {
    return adapter.findAll();
  }

  /// Count total number of entities.
  Future<int> count() async {
    return adapter.count();
  }

  /// Save entity to database.
  ///
  /// Orchestrates domain pattern lifecycle via handlers:
  /// 1. beforeSave hooks (fail-fast)
  /// 2. beforeSaveInTransaction hooks (if TransactionManager provided)
  /// 3. Entity persisted to database
  /// 4. afterSaveInTransaction hooks (if TransactionManager provided)
  /// 5. afterSave hooks (best-effort)
  ///
  /// Handler execution order determines pattern integration.
  /// See RepositoryPatternHandler for semantics of each lifecycle phase.
  Future<int> save(T entity) async {
    // Phase 1: beforeSave hooks (fail-fast, outside transaction)
    for (final handler in handlers) {
      await handler.beforeSave(entity);
    }

    // Phase 2-5: Transactional or non-transactional save
    final savedId = await _doSave(entity);

    // Phase 5: afterSave hooks (best-effort, outside transaction)
    // These run AFTER the transaction commits (or after non-transactional save)
    for (final handler in handlers) {
      try {
        await handler.afterSave(entity);
      } catch (e) {
        // Best-effort: log but don't propagate
        // Entity is already persisted
        // ignore: avoid_print
        print('Warning: Handler afterSave failed: $e');
      }
    }

    return savedId;
  }

  /// Save entity with transactional lifecycle hooks.
  ///
  /// Handles both transactional and non-transactional paths.
  /// Note: afterSave hooks are NOT called here - they're called in save() after transaction.
  Future<int> _doSave(T entity) async {
    if (transactionManager != null) {
      // Transactional save: beforeSaveInTransaction, save, afterSaveInTransaction (all inside tx)
      return await transactionManager!.transaction(
        (ctx) => _saveWithHandlersInTransaction(ctx, entity),
        objectStores: transactionStores,
      );
    } else {
      // Non-transactional save
      final saved = await adapter.save(entity);
      return saved.id;
    }
  }

  /// Save with handler integration within transaction.
  ///
  /// Transactional sequence:
  /// 2. beforeSaveInTransaction hooks (sync, inside tx)
  /// 3. Entity persisted
  /// 4. afterSaveInTransaction hooks (sync, inside tx)
  ///
  /// If ANY step fails, transaction rolls back completely.
  int _saveWithHandlersInTransaction(TransactionContext ctx, T entity) {
    // Phase 2: beforeSaveInTransaction hooks (sync, inside tx)
    for (final handler in handlers) {
      handler.beforeSaveInTransaction(ctx, entity);
    }

    // Phase 3: Persist entity
    final saved = adapter.saveInTx(ctx, entity);

    // Phase 4: afterSaveInTransaction hooks (sync, inside tx)
    for (final handler in handlers) {
      handler.afterSaveInTransaction(ctx, entity);
    }

    // Phase 5: afterSave hooks happen AFTER transaction commits
    // (async, outside transaction, best-effort - not done here)

    return saved.id;
  }


  /// Save multiple entities to database.
  ///
  /// Uses handlers for each entity to manage pattern lifecycle.
  /// For efficiency with bulk operations, this method calls save() for each entity
  /// (which applies handlers) rather than optimizing away handler execution.
  ///
  /// For truly bulk operations without handlers, use adapter.saveAll() directly.
  Future<void> saveAll(List<T> entities) async {
    for (final entity in entities) {
      await save(entity);
    }
  }

  /// Delete entity from database.
  /// Adapter handles removing from vector index.
  Future<bool> delete(int id) async {
    return adapter.delete(id);
  }

  /// Delete entity by UUID from database.
  ///
  /// Orchestrates domain pattern lifecycle via handlers:
  /// 1. beforeDelete hooks (fail-fast, outside transaction)
  /// 2. beforeDeleteInTransaction hooks (if TransactionManager provided)
  /// 3. Entity deleted from database
  /// 4. afterDeleteInTransaction hooks (if TransactionManager provided)
  ///
  /// Handler execution order determines pattern integration.
  /// See RepositoryPatternHandler for semantics.
  Future<bool> deleteByUuid(String uuid) async {
    // Load entity to pass to handlers
    final entity = await findByUuid(uuid);
    if (entity == null) return false;

    // Phase 1: beforeDelete hooks (fail-fast, outside transaction)
    for (final handler in handlers) {
      await handler.beforeDelete(entity);
    }

    // Phase 2-4: Transactional or non-transactional delete
    return await _doDelete(entity);
  }

  /// Delete entity with transactional lifecycle hooks.
  ///
  /// Handles both transactional and non-transactional paths.
  Future<bool> _doDelete(T entity) async {
    if (transactionManager != null) {
      // Transactional delete: beforeDeleteInTransaction, delete, afterDeleteInTransaction (all inside tx)
      return await transactionManager!.transaction(
        (ctx) => _deleteWithHandlersInTransaction(ctx, entity),
        objectStores: transactionStores,
      );
    } else {
      // Non-transactional delete
      return adapter.deleteByUuid(entity.uuid);
    }
  }

  /// Delete with handler integration within transaction.
  ///
  /// Transactional sequence:
  /// 2. beforeDeleteInTransaction hooks (sync, inside tx)
  /// 3. Entity deleted
  /// 4. afterDeleteInTransaction hooks (sync, inside tx)
  ///
  /// If ANY step fails, transaction rolls back completely.
  bool _deleteWithHandlersInTransaction(TransactionContext ctx, T entity) {
    // Phase 2: beforeDeleteInTransaction hooks (sync, inside tx)
    for (final handler in handlers) {
      handler.beforeDeleteInTransaction(ctx, entity);
    }

    // Phase 3: Delete entity
    final deleted = adapter.deleteByUuidInTx(ctx, entity.uuid);

    // Phase 4: afterDeleteInTransaction hooks (sync, inside tx)
    for (final handler in handlers) {
      handler.afterDeleteInTransaction(ctx, entity);
    }

    return deleted;
  }

  /// Delete multiple entities from database.
  /// Adapter handles removing from vector index.
  Future<void> deleteAll(List<int> ids) async {
    await adapter.deleteAll(ids);
  }

  // ============ Semantic Search ============

  /// Search by semantic similarity. Only works for Embeddable entities.
  /// Returns entities sorted by similarity to query.
  ///
  /// Delegates to adapter which handles the search implementation
  /// (ObjectBox uses native HNSW, IndexedDB uses local_hnsw).
  Future<List<T>> semanticSearch(
    String query, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Generate query embedding
    final queryEmbedding = await embeddingService.generate(query);

    // Delegate search to adapter
    return adapter.semanticSearch(
      queryEmbedding,
      limit: limit,
      minSimilarity: minSimilarity,
    );
  }

  // ============ Index Management ============

  /// Rebuild vector index from all entities.
  /// Use when index is missing, corrupt, or out of sync.
  ///
  /// For Embeddable entities without embeddings, regenerates them.
  Future<void> rebuildIndex() async {
    await adapter.rebuildIndex((entity) async {
      if (entity is! Embeddable) return null;
      final embeddable = entity as Embeddable;
      final input = embeddable.toEmbeddingInput();
      if (input.trim().isEmpty) {
        embeddable.embedding = null;
        return null;
      }
      embeddable.embedding = await embeddingService.generate(input);
      return embeddable.embedding;
    });
  }

  /// Number of vectors in the search index.
  int get indexSize => adapter.indexSize;

  // ============ Sync Helpers ============

  /// Find entities that need to be synced.
  /// Delegates to adapter for optimized query.
  Future<List<T>> findUnsynced() async {
    return adapter.findUnsynced();
  }

  /// Mark entity as synced with remote ID.
  Future<void> markSynced(int id, String syncId) async {
    final entity = await findById(id);
    if (entity != null) {
      entity.syncId = syncId;
      entity.syncStatus = SyncStatus.synced;
      await save(entity);
    }
  }

  /// Close the adapter and release resources.
  Future<void> close() async {
    await adapter.close();
  }
}
