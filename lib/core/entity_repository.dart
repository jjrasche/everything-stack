/// Base repository providing common data operations for all entities.
/// Delegates database operations to PersistenceAdapter for platform independence.

import 'base_entity.dart';
import 'persistence/persistence_adapter.dart';
import 'persistence/transaction_manager.dart';
import 'persistence/transaction_context.dart';
import 'repository_pattern_handler.dart';
import '../patterns/embeddable.dart';
import '../patterns/enrichable.dart';
import '../patterns/semantic_indexable.dart';
import '../services/embedding_service.dart';
import '../services/chunking_service.dart';
import '../services/enrichment/enrichment_runner.dart';

class EntityRepository<T extends BaseEntity> {
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

  /// Enrichment runner for async post-save enrichment.
  /// If provided and entity is Enrichable, enrichment is queued after save.
  /// If null, Enrichable entities are saved without async enrichment.
  final EnrichmentRunner? enrichmentRunner;

  EntityRepository({
    required this.adapter,
    required this.embeddingService,
    ChunkingService? chunkingService,
    this.versionRepository,
    this.transactionManager,
    this.enrichmentRunner,
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
    final typeName = T.toString().toLowerCase();
    return typeName.endsWith('s') ? typeName : '${typeName}s';
  }

  // ============ CRUD ============

  /// Find entity by internal database ID (legacy).
  @deprecated
  Future<T?> findById(int id) async {
    return adapter.findByIntId(id);
  }

  /// Find entity by its UUID (the universal identifier).
  /// Delegates to adapter which uses indexed lookup.
  Future<T?> findByUuid(String uuid) async {
    return adapter.findById(uuid);
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
    final isUpdate = entity.id > 0;

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

    // Phase 6: Queue enrichment if entity is Enrichable
    if (enrichmentRunner != null && entity is Enrichable) {
      final enrichable = entity as Enrichable;
      final steps = enrichable.enrichmentSteps;

      if (steps.isNotEmpty) {
        if (isUpdate) {
          await enrichmentRunner!.cancelForEntity(entity.uuid);
        }

        await enrichmentRunner!.enqueue(
          entityUuid: entity.uuid,
          entityType: T.toString(),
          steps: steps,
        );
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

  /// Delete entity from database by ID (legacy).
  /// Adapter handles removing from vector index.
  @deprecated
  Future<bool> delete(int id) async {
    return adapter.deleteByIntId(id);
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
    final entity = await findByUuid(uuid);
    if (entity == null) return false;

    // Prevents worker from processing deleted entity
    if (enrichmentRunner != null && entity is Enrichable) {
      try {
        await enrichmentRunner!.cancelForEntity(entity.uuid);
      } catch (e) {
        // Log but don't fail deletion if cancellation fails
        // ignore: avoid_print
        print('Warning: Enrichment cancellation failed for ${entity.uuid}: $e');
      }
    }

    // Must happen before entity deletion so chunks can be looked up
    if (chunkingService != null && entity is SemanticIndexable) {
      try {
        await chunkingService!.deleteByEntityId(entity.uuid);
      } catch (e) {
        // Log but don't fail deletion if chunk cleanup fails
        // ignore: avoid_print
        print('Warning: Chunk cleanup failed for ${entity.uuid}: $e');
      }
    }

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
      return adapter.delete(entity.uuid);
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
    final deleted = adapter.deleteInTx(ctx, entity.uuid);

    // Phase 4: afterDeleteInTransaction hooks (sync, inside tx)
    for (final handler in handlers) {
      handler.afterDeleteInTransaction(ctx, entity);
    }

    return deleted;
  }

  /// Delete multiple entities from database by UUIDs.
  /// Adapter handles removing from vector index.
  Future<void> deleteAll(List<String> uuids) async {
    await adapter.deleteAll(uuids);
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
    final queryEmbedding = await embeddingService.generate(query);

    return adapter.semanticSearch(
      queryEmbedding,
      limit: limit,
      minSimilarity: minSimilarity,
    );
  }

  /// Search semantically using a pre-generated query embedding.
  ///
  /// Use this when you need both the results AND the embedding for reuse
  /// (e.g., calculating similarity scores in response formatting).
  /// Avoids redundant embedding generation compared to calling semanticSearch(String)
  /// and then generating the embedding again.
  ///
  /// Returns a tuple of (results, queryEmbedding) so you can reuse the embedding.
  Future<(List<T>, List<double>)> semanticSearchWithEmbedding(
    String query, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    final queryEmbedding = await embeddingService.generate(query);

    final results = await adapter.semanticSearch(
      queryEmbedding,
      limit: limit,
      minSimilarity: minSimilarity,
    );

    // Return both results and embedding for reuse
    return (results, queryEmbedding);
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
