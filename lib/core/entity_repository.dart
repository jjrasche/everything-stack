/// # EntityRepository
///
/// ## What it does
/// Base repository providing common data operations for all entities.
/// Handles CRUD, querying, and cross-cutting concerns like sync.
/// Integrates with HNSW index for O(log n) semantic search.
///
/// ## What it enables
/// - Consistent data access patterns
/// - Semantic search when entity is Embeddable (via HNSW index)
/// - Edge traversal when entity is Edgeable
/// - Automatic sync status management
/// - Index rebuild from entities when missing/corrupt
/// - Cross-type identification via uuid
///
/// ## Usage
/// ```dart
/// // Create shared HNSW index (Option A: global index)
/// final hnswIndex = HnswIndex(dimensions: EmbeddingService.dimension);
///
/// class NoteRepository extends EntityRepository<Note> {
///   NoteRepository(super.isar, {super.hnswIndex, super.embeddingService});
///
///   @override
///   IsarCollection<Note> get collection => isar.notes;
/// }
///
/// final repo = NoteRepository(isar, hnswIndex: hnswIndex);
/// await repo.save(note);  // Auto-generates embedding, adds to index by uuid
/// final results = await repo.semanticSearch('query');  // Uses HNSW
/// ```
///
/// ## Testing approach
/// Test through domain repositories. Verify CRUD operations,
/// query correctness, sync status transitions, index integration.

import 'package:isar/isar.dart';
import 'base_entity.dart';
import '../patterns/embeddable.dart';
import '../patterns/versionable.dart';
import '../services/embedding_service.dart';
import '../services/hnsw_index.dart';

abstract class EntityRepository<T extends BaseEntity> {
  final Isar isar;

  /// Optional HNSW index for O(log n) semantic search.
  /// If null, semantic search falls back to O(n) brute force.
  /// Shared across repositories for cross-type search (Option A).
  /// Uses entity uuid as key (not Isar's int id).
  final HnswIndex? hnswIndex;

  /// Embedding service for generating vectors.
  /// Defaults to global singleton if not provided.
  final EmbeddingService embeddingService;

  /// Optional VersionRepository for tracking entity changes.
  /// If provided and entity is Versionable, changes are automatically recorded.
  /// If null, Versionable entities are still saved but changes not versioned.
  final dynamic versionRepository;

  EntityRepository(
    this.isar, {
    this.hnswIndex,
    EmbeddingService? embeddingService,
    this.versionRepository,
  }) : embeddingService = embeddingService ?? EmbeddingService.instance;

  /// Override in subclass to return typed collection
  IsarCollection<T> get collection;

  // ============ CRUD ============

  Future<T?> findById(Id id) async {
    return collection.get(id);
  }

  /// Find entity by its UUID (the universal identifier)
  ///
  /// PERFORMANCE NOTE: This base implementation scans all entities O(n).
  /// Concrete repositories should override this with O(1) indexed lookup
  /// by leveraging the uuid @Index override in their entity class.
  ///
  /// Example override in NoteRepository:
  /// ```dart
  /// @override
  /// Future<Note?> findByUuid(String uuid) async {
  ///   return collection.where().uuidEqualTo(uuid).findFirst();
  /// }
  /// ```
  /// This works because Note overrides the uuid field with @Index(unique: true),
  /// enabling Isar to generate the uuidEqualTo() filter method.
  Future<T?> findByUuid(String uuid) async {
    final all = await collection.where().findAll();
    try {
      return all.firstWhere((e) => e.uuid == uuid);
    } catch (e) {
      return null;
    }
  }

  Future<List<T>> findAll() async {
    return collection.where().findAll();
  }

  /// Save entity to database.
  /// For Embeddable entities: generates embedding and adds to HNSW index by uuid.
  /// For Versionable entities: records change in VersionRepository if available.
  Future<Id> save(T entity) async {
    entity.touch();

    // Record change for Versionable entities
    if (entity is Versionable && versionRepository != null) {
      await _recordVersionChange(entity as Versionable);
    }

    // Generate embedding for Embeddable entities
    if (entity is Embeddable) {
      await _generateEmbedding(entity as Embeddable);
    }

    // Save to database
    final id = await isar.writeTxn(() => collection.put(entity));

    // Update HNSW index using uuid as key
    if (entity is Embeddable && hnswIndex != null) {
      _updateIndex(entity.uuid, entity as Embeddable);
    }

    return id;
  }

  /// Save multiple entities to database.
  /// For Embeddable entities: generates embeddings and adds to HNSW index.
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
      entity.touch();
      if (entity is Embeddable) {
        await _generateEmbedding(entity as Embeddable);
      }
    }

    // Save all to database
    await isar.writeTxn(() => collection.putAll(entities));

    // Update HNSW index for all Embeddable entities using uuid
    if (hnswIndex != null) {
      for (final entity in entities) {
        if (entity is Embeddable) {
          _updateIndex(entity.uuid, entity as Embeddable);
        }
      }
    }
  }

  /// Delete entity from database and HNSW index.
  Future<bool> delete(Id id) async {
    // Get entity first to get its uuid for index removal
    final entity = await findById(id);
    if (entity != null) {
      hnswIndex?.delete(entity.uuid);
    }

    return isar.writeTxn(() => collection.delete(id));
  }

  /// Delete entity by UUID from database and HNSW index.
  Future<bool> deleteByUuid(String uuid) async {
    // Remove from HNSW index first
    hnswIndex?.delete(uuid);

    final entity = await findByUuid(uuid);
    if (entity == null) return false;

    return isar.writeTxn(() => collection.delete(entity.id));
  }

  /// Delete multiple entities from database and HNSW index.
  Future<void> deleteAll(List<Id> ids) async {
    // Get entities first to get their uuids for index removal
    if (hnswIndex != null) {
      for (final id in ids) {
        final entity = await findById(id);
        if (entity != null) {
          hnswIndex!.delete(entity.uuid);
        }
      }
    }

    await isar.writeTxn(() => collection.deleteAll(ids));
  }

  // ============ Semantic Search ============

  /// Search by semantic similarity. Only works for Embeddable entities.
  /// Returns entities sorted by similarity to query.
  ///
  /// Uses HNSW index for O(log n) search if available,
  /// falls back to O(n) brute force otherwise.
  Future<List<T>> semanticSearch(
    String query, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Generate query embedding
    final queryEmbedding = await embeddingService.generate(query);

    // Use HNSW index if available
    if (hnswIndex != null && hnswIndex!.size > 0) {
      return _hnswSearch(queryEmbedding, limit: limit, minSimilarity: minSimilarity);
    }

    // Fallback to brute force
    return _bruteForceSearch(queryEmbedding, limit: limit, minSimilarity: minSimilarity);
  }

  /// HNSW-based search - O(log n)
  /// Returns entities from THIS collection that match the search results.
  Future<List<T>> _hnswSearch(
    List<double> queryEmbedding, {
    required int limit,
    required double minSimilarity,
  }) async {
    // Search index for candidate UUIDs
    // Request more than limit to filter by minSimilarity and type
    final searchResults = hnswIndex!.search(queryEmbedding, k: limit * 2);

    // Load entities by uuid and filter to this collection's type
    final results = <T>[];
    for (final result in searchResults) {
      // Convert distance to similarity (cosine distance = 1 - similarity)
      final similarity = 1.0 - result.distance;
      if (similarity < minSimilarity) continue;

      // Look up entity by uuid in this collection
      final entity = await findByUuid(result.id);
      if (entity != null) {
        results.add(entity);
        if (results.length >= limit) break;
      }
    }

    return results;
  }

  /// Brute force search - O(n), used when no index available
  Future<List<T>> _bruteForceSearch(
    List<double> queryEmbedding, {
    required int limit,
    required double minSimilarity,
  }) async {
    final candidates = await collection.where().findAll();

    // Score and rank
    final scored = <_ScoredEntity<T>>[];
    for (final entity in candidates) {
      if (entity is Embeddable && (entity as Embeddable).embedding != null) {
        final similarity = EmbeddingService.cosineSimilarity(
          queryEmbedding,
          (entity as Embeddable).embedding!,
        );
        if (similarity >= minSimilarity) {
          scored.add(_ScoredEntity(entity, similarity));
        }
      }
    }

    // Sort by similarity descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.take(limit).map((s) => s.entity).toList();
  }

  // ============ Index Management ============

  /// Rebuild HNSW index from all entities in this collection.
  /// Use when index is missing, corrupt, or out of sync.
  ///
  /// For Embeddable entities without embeddings, regenerates them.
  Future<void> rebuildIndex() async {
    if (hnswIndex == null) return;

    final entities = await collection.where().findAll();

    for (final entity in entities) {
      if (entity is! Embeddable) continue;
      final embeddable = entity as Embeddable;

      // Generate embedding if missing
      if (embeddable.embedding == null) {
        await _generateEmbedding(embeddable);

        // Save the generated embedding back to database
        if (embeddable.embedding != null) {
          await isar.writeTxn(() => collection.put(entity));
        }
      }

      // Add to index if has valid embedding, using uuid as key
      if (embeddable.embedding != null) {
        _addToIndex(entity.uuid, embeddable.embedding!);
      }
    }
  }

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

  /// Update entity in HNSW index (handles add/update).
  /// Uses uuid as the key for cross-type uniqueness.
  void _updateIndex(String uuid, Embeddable entity) {
    if (hnswIndex == null) return;

    // Remove existing entry if present (for updates)
    if (hnswIndex!.contains(uuid)) {
      hnswIndex!.delete(uuid);
    }

    // Add new entry if has embedding
    if (entity.embedding != null) {
      _addToIndex(uuid, entity.embedding!);
    }
  }

  /// Add vector to HNSW index using uuid as key.
  void _addToIndex(String uuid, List<double> embedding) {
    if (hnswIndex == null) return;

    try {
      hnswIndex!.insert(uuid, embedding);
    } catch (e) {
      // Log but don't fail - index can be rebuilt
      // In production, use proper logging
      print('Warning: Failed to add $uuid to HNSW index: $e');
    }
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
  /// Override in concrete repository to use generated filter methods.
  /// Example:
  /// ```dart
  /// @override
  /// Future<List<Tool>> findUnsynced() async {
  ///   return collection.filter().syncStatusEqualTo(SyncStatus.local).findAll();
  /// }
  /// ```
  Future<List<T>> findUnsynced() async {
    // Generic implementation - filter in memory
    final all = await collection.where().findAll();
    return all.where((e) => e.syncStatus == SyncStatus.local).toList();
  }

  Future<void> markSynced(Id id, String syncId) async {
    final entity = await findById(id);
    if (entity != null) {
      entity.syncId = syncId;
      entity.syncStatus = SyncStatus.synced;
      await save(entity);
    }
  }
}

class _ScoredEntity<T> {
  final T entity;
  final double score;
  _ScoredEntity(this.entity, this.score);
}
