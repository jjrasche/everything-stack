/// # EntityRepository
/// 
/// ## What it does
/// Base repository providing common data operations for all entities.
/// Handles CRUD, querying, and cross-cutting concerns like sync.
/// 
/// ## What it enables
/// - Consistent data access patterns
/// - Semantic search when entity is Embeddable
/// - Edge traversal when entity is Edgeable
/// - Automatic sync status management
/// 
/// ## Usage
/// ```dart
/// class ToolRepository extends EntityRepository<Tool> {
///   ToolRepository(super.isar);
///   
///   Future<List<Tool>> findAvailable() {
///     return collection.filter().statusEqualTo('available').findAll();
///   }
/// }
/// ```
/// 
/// ## Testing approach
/// Test through domain repositories. Verify CRUD operations, 
/// query correctness, sync status transitions.

import 'package:isar/isar.dart';
import 'base_entity.dart';
import '../patterns/embeddable.dart';
import '../services/embedding_service.dart';

abstract class EntityRepository<T extends BaseEntity> {
  final Isar isar;
  
  EntityRepository(this.isar);
  
  /// Override in subclass to return typed collection
  IsarCollection<T> get collection;
  
  // ============ CRUD ============
  
  Future<T?> findById(Id id) async {
    return collection.get(id);
  }
  
  Future<List<T>> findAll() async {
    return collection.where().findAll();
  }
  
  Future<Id> save(T entity) async {
    entity.touch();
    return isar.writeTxn(() => collection.put(entity));
  }
  
  Future<void> saveAll(List<T> entities) async {
    for (final e in entities) {
      e.touch();
    }
    await isar.writeTxn(() => collection.putAll(entities));
  }
  
  Future<bool> delete(Id id) async {
    return isar.writeTxn(() => collection.delete(id));
  }
  
  Future<void> deleteAll(List<Id> ids) async {
    await isar.writeTxn(() => collection.deleteAll(ids));
  }
  
  // ============ Semantic Search ============
  
  /// Search by semantic similarity. Only works for Embeddable entities.
  /// Returns entities sorted by similarity to query.
  Future<List<T>> semanticSearch(
    String query, {
    int limit = 10,
    double minSimilarity = 0.5,
  }) async {
    // Generate query embedding
    final queryEmbedding = await EmbeddingService.generate(query);
    
    // Get all entities with embeddings
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
