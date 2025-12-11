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

import 'base_entity.dart';
import 'persistence/persistence_adapter.dart';
import '../patterns/embeddable.dart';
import '../patterns/versionable.dart';
import '../services/embedding_service.dart';

abstract class EntityRepository<T extends BaseEntity> {
  /// Persistence adapter for database operations.
  /// Handles storage and vector search.
  final PersistenceAdapter<T> adapter;

  /// Embedding service for generating vectors.
  /// Defaults to global singleton if not provided.
  final EmbeddingService embeddingService;

  /// Optional VersionRepository for tracking entity changes.
  /// If provided and entity is Versionable, changes are automatically recorded.
  /// If null, Versionable entities are still saved but changes not versioned.
  final dynamic versionRepository;

  EntityRepository({
    required this.adapter,
    EmbeddingService? embeddingService,
    this.versionRepository,
  }) : embeddingService = embeddingService ?? EmbeddingService.instance;

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
  /// For Embeddable entities: generates embedding (adapter handles indexing).
  /// For Versionable entities: records change in VersionRepository if available.
  Future<int> save(T entity) async {
    // Record change for Versionable entities
    if (entity is Versionable && versionRepository != null) {
      await _recordVersionChange(entity as Versionable);
    }

    // Generate embedding for Embeddable entities
    if (entity is Embeddable) {
      await _generateEmbedding(entity as Embeddable);
    }

    // Save to database (adapter handles touch() and indexing)
    final saved = await adapter.save(entity);
    return saved.id;
  }

  /// Save multiple entities to database.
  /// For Embeddable entities: generates embeddings (adapter handles indexing).
  /// For Versionable entities: records changes in VersionRepository if available.
  Future<void> saveAll(List<T> entities) async {
    // Record changes for Versionable entities
    if (versionRepository != null) {
      for (final entity in entities) {
        if (entity is Versionable) {
          await _recordVersionChange(entity as Versionable);
        }
      }
    }

    // Generate embeddings for all Embeddable entities
    for (final entity in entities) {
      if (entity is Embeddable) {
        await _generateEmbedding(entity as Embeddable);
      }
    }

    // Save all to database (adapter handles touch() and indexing)
    await adapter.saveAll(entities);
  }

  /// Delete entity from database.
  /// Adapter handles removing from vector index.
  Future<bool> delete(int id) async {
    return adapter.delete(id);
  }

  /// Delete entity by UUID from database.
  /// Adapter handles removing from vector index.
  Future<bool> deleteByUuid(String uuid) async {
    return adapter.deleteByUuid(uuid);
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
      await _generateEmbedding(entity as Embeddable);
      return (entity as Embeddable).embedding;
    });
  }

  /// Number of vectors in the search index.
  int get indexSize => adapter.indexSize;

  /// Generate embedding for an Embeddable entity.
  /// Sets embedding to null if input is empty.
  Future<void> _generateEmbedding(Embeddable entity) async {
    final input = entity.toEmbeddingInput();
    if (input.trim().isEmpty) {
      entity.embedding = null;
      return;
    }
    entity.embedding = await embeddingService.generate(input);
  }

  // ============ Versioning ============

  /// Record a change to a Versionable entity.
  /// Fetches previous state from database and calls versionRepository.recordChange().
  Future<void> _recordVersionChange(Versionable entity) async {
    if (versionRepository == null) return;

    // Fetch previous state if entity exists in database
    final previousEntity = await findByUuid((entity as BaseEntity).uuid);
    final previousJson = (previousEntity is Versionable)
        ? (previousEntity as dynamic).toJson() as Map<String, dynamic>?
        : null;

    // Get current state as JSON
    final currentJson = (entity as dynamic).toJson() as Map<String, dynamic>;

    // Record the change
    await versionRepository.recordChange(
      entityUuid: (entity as BaseEntity).uuid,
      entityType: T.toString(),
      previousJson: previousJson,
      currentJson: currentJson,
      userId: (entity as dynamic).lastModifiedBy as String?,
      snapshotFrequency: entity.snapshotFrequency,
    );
  }

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
