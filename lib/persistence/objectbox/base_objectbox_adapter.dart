/// # BaseObjectBoxAdapter
///
/// ## What it does
/// Base implementation of PersistenceAdapter for ObjectBox.
/// Handles 90% of adapter logic - transaction boilerplate, context casting,
/// box access, query execution, and cleanup.
///
/// ## What it enables
/// - DRY: Write transaction logic once, not per entity type
/// - New entities are ~5 lines (extend base + provide query conditions)
/// - Consistent patterns across all ObjectBox adapters
///
/// ## How it works
/// Subclasses provide entity-specific query conditions via abstract methods:
/// - uuidEqualsCondition(): Condition for UUID lookups
/// - syncStatusLocalCondition(): Condition for unsynced entities
///
/// Base class handles all the boilerplate:
/// - Context casting (TransactionContext -> ObjectBoxTxContext)
/// - Box access (store.box<T>())
/// - Query execution and cleanup
/// - Touch behavior (controlled via shouldTouchOnSave)
///
/// ## Usage
/// ```dart
/// class NoteObjectBoxAdapter extends BaseObjectBoxAdapter<Note> {
///   NoteObjectBoxAdapter(Store store) : super(store);
///
///   @override
///   Condition<Note> uuidEqualsCondition(String uuid) => Note_.uuid.equals(uuid);
///
///   @override
///   Condition<Note> syncStatusLocalCondition() =>
///       Note_.dbSyncStatus.equals(SyncStatus.local.index);
/// }
/// ```

import 'package:meta/meta.dart';
import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../core/persistence/transaction_context.dart';
import '../../core/persistence/objectbox_tx_context.dart';
import '../../core/exceptions/persistence_exceptions.dart';

/// Base ObjectBox adapter implementation.
///
/// Provides complete implementation of PersistenceAdapter for ObjectBox.
/// Subclasses only need to provide entity-specific query conditions.
abstract class BaseObjectBoxAdapter<T extends BaseEntity>
    implements PersistenceAdapter<T> {
  final Store _store;
  late final Box<T> _box;

  BaseObjectBoxAdapter(this._store) {
    _box = _store.box<T>();
  }

  /// Access to the box for subclass-specific queries.
  /// Used by entity-specific methods like findPinned(), findBySource(), etc.
  @protected
  Box<T> get box => _box;

  // ============ Abstract Methods (Entity-Specific) ============

  /// Condition for finding entity by UUID.
  /// Example: Note_.uuid.equals(uuid)
  Condition<T> uuidEqualsCondition(String uuid);

  /// Condition for finding entities with SyncStatus.local.
  /// Example: Note_.dbSyncStatus.equals(SyncStatus.local.index)
  Condition<T> syncStatusLocalCondition();

  /// Whether to call touch() on entities before saving.
  /// Override to false for immutable entities (e.g., EntityVersion).
  bool get shouldTouchOnSave => true;

  // ============ Helper Methods ============

  /// Get box from transaction context.
  Box<T> _getBox(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    return obCtx.store.box<T>();
  }

  /// Execute query and ensure cleanup.
  R _executeQuery<R>(Query<T> query, R Function(Query<T>) work) {
    try {
      return work(query);
    } finally {
      query.close();
    }
  }

  /// Touch entity if needed.
  void _touchIfNeeded(T entity) {
    if (shouldTouchOnSave) {
      entity.touch();
    }
  }

  /// Translate ObjectBox exceptions to platform-agnostic exceptions.
  Never _translateException(Object error, StackTrace stackTrace) {
    final entityType = T.toString();

    if (error is UniqueViolationException) {
      // Unique constraint violation
      throw DuplicateEntityException(
        entityType,
        'unique constraint',
        fieldValue: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is NonUniqueResultException) {
      // Query returned multiple when expecting one
      throw QueryException(
        'Query returned multiple ${entityType}s when expecting one',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is NumericOverflowException) {
      // Numeric overflow in aggregates
      throw QueryException(
        'Numeric overflow in $entityType query',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is StorageException) {
      // Storage errors - could be quota exceeded
      final message = error.toString();
      if (message.contains('quota') ||
          message.contains('disk') ||
          message.contains('space')) {
        throw StorageLimitException(
          'Storage limit exceeded for $entityType',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      // Other storage errors
      throw PersistenceException(
        'Storage error: $message',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is SchemaException) {
      // Schema errors
      throw PersistenceException(
        'Schema error for $entityType: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ObjectBoxException) {
      // Other ObjectBox exceptions
      throw PersistenceException(
        'ObjectBox error for $entityType: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // Unknown exception - wrap as generic PersistenceException
    throw PersistenceException(
      'Unexpected error with $entityType: $error',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Execute operation with exception translation.
  R _executeWithExceptionHandling<R>(R Function() operation) {
    try {
      return operation();
    } catch (error, stackTrace) {
      _translateException(error, stackTrace);
    }
  }

  /// Execute async operation with exception translation.
  Future<R> _executeAsyncWithExceptionHandling<R>(
    Future<R> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      _translateException(error, stackTrace);
    }
  }

  // ============ CRUD ============

  @override
  Future<T?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<T> getById(int id) async {
    final entity = await findById(id);
    if (entity == null) {
      throw EntityNotFoundException(
        T.toString(),
        id: id,
      );
    }
    return entity;
  }

  @override
  Future<T?> findByUuid(String uuid) async {
    final query = _box.query(uuidEqualsCondition(uuid)).build();
    return _executeQuery(query, (q) => q.findFirst());
  }

  @override
  Future<T> getByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) {
      throw EntityNotFoundException(
        T.toString(),
        uuid: uuid,
      );
    }
    return entity;
  }

  @override
  Future<List<T>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<T> save(T entity) async {
    return _executeAsyncWithExceptionHandling(() async {
      _touchIfNeeded(entity);
      _box.put(entity);
      return entity;
    });
  }

  @override
  Future<List<T>> saveAll(List<T> entities) async {
    return _executeAsyncWithExceptionHandling(() async {
      for (final entity in entities) {
        _touchIfNeeded(entity);
      }
      _box.putMany(entities);
      return entities;
    });
  }

  @override
  Future<bool> delete(int id) async {
    return _box.remove(id);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) return false;
    return _box.remove(entity.id);
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    _box.removeMany(ids);
  }

  // ============ Queries ============

  @override
  Future<List<T>> findUnsynced() async {
    final query = _box.query(syncStatusLocalCondition()).build();
    return _executeQuery(query, (q) => q.find());
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  // ============ Semantic Search ============
  // Default implementation: no semantic search (entities without embeddings)
  // Subclasses with embeddings override these methods

  @override
  Future<List<T>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Default: no semantic search support
    return [];
  }

  @override
  int get indexSize => 0; // Default: no embeddings

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(T entity) generateEmbedding,
  ) async {
    // Default: no-op for entities without embeddings
  }

  // ============ Transaction Operations ============

  @override
  T? findByIdInTx(TransactionContext ctx, int id) {
    final box = _getBox(ctx);
    return box.get(id);
  }

  @override
  T? findByUuidInTx(TransactionContext ctx, String uuid) {
    final box = _getBox(ctx);
    final query = box.query(uuidEqualsCondition(uuid)).build();
    return _executeQuery(query, (q) => q.findFirst());
  }

  @override
  List<T> findAllInTx(TransactionContext ctx) {
    final box = _getBox(ctx);
    return box.getAll();
  }

  @override
  T saveInTx(TransactionContext ctx, T entity) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      _touchIfNeeded(entity);
      box.put(entity);
      return entity;
    });
  }

  @override
  List<T> saveAllInTx(TransactionContext ctx, List<T> entities) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      for (final entity in entities) {
        _touchIfNeeded(entity);
      }
      box.putMany(entities);
      return entities;
    });
  }

  @override
  bool deleteInTx(TransactionContext ctx, int id) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      return box.remove(id);
    });
  }

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      final query = box.query(uuidEqualsCondition(uuid)).build();
      return _executeQuery(query, (q) {
        final entity = q.findFirst();
        if (entity == null) return false;
        return box.remove(entity.id);
      });
    });
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) {
    _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      box.removeMany(ids);
    });
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle is managed externally
    // Don't close the store here - it may be shared
  }
}
