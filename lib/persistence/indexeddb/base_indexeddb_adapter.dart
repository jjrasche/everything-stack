/// # BaseIndexedDBAdapter
///
/// ## What it does
/// Base implementation of PersistenceAdapter for IndexedDB.
/// Handles 90% of adapter logic - transaction boilerplate, context casting,
/// object store access, query execution, and serialization.
///
/// ## What it enables
/// - DRY: Write transaction logic once, not per entity type
/// - New entities are ~5 lines (extend base + provide object store name)
/// - Consistent patterns across all IndexedDB adapters
///
/// ## How it works
/// Subclasses provide entity-specific details via abstract methods:
/// - objectStoreName: Name of IndexedDB object store
/// - fromJson(): Deserialize entity from JSON
/// - toJson(): Serialize entity to JSON (inherited from entities)
///
/// Base class handles all the boilerplate:
/// - Context casting (TransactionContext -> IndexedDBTxContext)
/// - Object store access (transaction.objectStore(name))
/// - Query execution and error handling
/// - Touch behavior (controlled via shouldTouchOnSave)
/// - Exception translation (IndexedDB → typed exceptions)
///
/// ## Usage
/// ```dart
/// class NoteIndexedDBAdapter extends BaseIndexedDBAdapter<Note> {
///   NoteIndexedDBAdapter(Database db) : super(db);
///
///   @override
///   String get objectStoreName => 'notes';
///
///   @override
///   Note fromJson(Map<String, dynamic> json) => Note.fromJson(json);
/// }
/// ```

import 'package:idb_shim/idb.dart';
import 'package:meta/meta.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../core/persistence/transaction_context.dart';
import '../../core/persistence/indexeddb_tx_context.dart';
import '../../core/exceptions/persistence_exceptions.dart';

/// Base IndexedDB adapter implementation.
///
/// Provides complete implementation of PersistenceAdapter for IndexedDB.
/// Subclasses only need to provide object store name and fromJson method.
abstract class BaseIndexedDBAdapter<T extends BaseEntity>
    implements PersistenceAdapter<T> {
  @protected
  final Database db; // Protected for subclass access
  int _nextId = 1; // Auto-increment counter for IDs

  BaseIndexedDBAdapter(this.db);

  // ============ Abstract Methods (Entity-Specific) ============

  /// Name of the IndexedDB object store for this entity type.
  /// Example: 'notes', 'edges', 'entity_versions'
  String get objectStoreName;

  /// Deserialize entity from JSON.
  /// Example: Note.fromJson(json)
  T fromJson(Map<String, dynamic> json);

  /// Whether to call touch() on entities before saving.
  /// Override to false for immutable entities (e.g., EntityVersion).
  bool get shouldTouchOnSave => true;

  // ============ Helper Methods ============

  /// Get object store from database (for non-transactional operations).
  ObjectStore _getStore({String mode = idbModeReadWrite}) {
    final txn = db.transaction(objectStoreName, mode);
    return txn.objectStore(objectStoreName);
  }

  /// Get object store from transaction context.
  ObjectStore _getStoreInTx(TransactionContext ctx) {
    final idbCtx = ctx as IndexedDBTxContext;
    return idbCtx.objectStore(objectStoreName);
  }

  /// Touch entity if needed.
  void _touchIfNeeded(T entity) {
    if (shouldTouchOnSave) {
      entity.touch();
    }
  }

  /// Translate IndexedDB exceptions to platform-agnostic exceptions.
  Never _translateException(Object error, StackTrace stackTrace) {
    final entityType = T.toString();
    final errorString = error.toString();

    // Constraint errors (unique violations)
    if (errorString.contains('ConstraintError') ||
        errorString.contains('constraint')) {
      throw DuplicateEntityException(
        entityType,
        'unique constraint',
        fieldValue: errorString,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // Quota exceeded errors
    if (errorString.contains('QuotaExceededError') ||
        errorString.contains('quota') ||
        errorString.contains('storage')) {
      throw StorageLimitException(
        'Storage limit exceeded for $entityType',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // Data errors (invalid data)
    if (errorString.contains('DataError')) {
      throw PersistenceException(
        'Invalid data for $entityType: $errorString',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // Transaction inactive errors
    if (errorString.contains('TransactionInactiveError')) {
      throw PersistenceException(
        'Transaction inactive for $entityType',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // Read-only errors
    if (errorString.contains('ReadOnlyError')) {
      throw PersistenceException(
        'Attempted write in read-only transaction for $entityType',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // Not found errors
    if (errorString.contains('NotFoundError')) {
      throw PersistenceException(
        'Object store or index not found for $entityType',
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

  /// Execute sync operation with exception translation.
  R _executeWithExceptionHandling<R>(R Function() operation) {
    try {
      return operation();
    } catch (error, stackTrace) {
      _translateException(error, stackTrace);
    }
  }

  // ============ CRUD ============

  @override
  Future<T?> findById(int id) async {
    // Use id index for efficient lookup
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);
    final index = store.index('id');

    final value = await index.get(id);
    if (value == null) return null;

    return fromJson(value as Map<String, dynamic>);
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
    final store = _getStore(mode: idbModeReadOnly);
    final value = await store.getObject(uuid);
    if (value == null) return null;
    return fromJson(value as Map<String, dynamic>);
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
    final store = _getStore(mode: idbModeReadOnly);
    final results = <T>[];
    final cursor = store.openCursor(autoAdvance: true);

    await for (final record in cursor) {
      final json = record.value as Map<String, dynamic>;
      results.add(fromJson(json));
    }

    return results;
  }

  @override
  Future<T> save(T entity) async {
    return _executeAsyncWithExceptionHandling(() async {
      // Assign ID if new entity
      if (entity.id == 0) {
        entity.id = _nextId++;
      }

      _touchIfNeeded(entity);
      final store = _getStore();
      final json = (entity as dynamic).toJson() as Map<String, dynamic>;
      // IndexedDB uses in-line keys (keyPath: 'uuid')
      // Don't pass key parameter - it's extracted from json['uuid']
      await store.put(json);
      return entity;
    });
  }

  @override
  Future<List<T>> saveAll(List<T> entities) async {
    return _executeAsyncWithExceptionHandling(() async {
      final store = _getStore();
      for (final entity in entities) {
        // Assign ID if new entity
        if (entity.id == 0) {
          entity.id = _nextId++;
        }

        _touchIfNeeded(entity);
        final json = (entity as dynamic).toJson() as Map<String, dynamic>;
        await store.put(json);
      }
      return entities;
    });
  }

  @override
  Future<bool> delete(int id) async {
    // Less efficient - need to find uuid first
    final entity = await findById(id);
    if (entity == null) return false;
    final store = _getStore();
    await store.delete(entity.uuid);
    return true;
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final store = _getStore();
    await store.delete(uuid);
    return true;
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    // Need to find uuids for all ids first
    final entities = await Future.wait(ids.map((id) => findById(id)));
    final store = _getStore();
    for (final entity in entities) {
      if (entity != null) {
        await store.delete(entity.uuid);
      }
    }
  }

  // ============ Queries ============

  @override
  Future<List<T>> findUnsynced() async {
    // Scan all records and filter by syncStatus
    final store = _getStore(mode: idbModeReadOnly);
    final results = <T>[];
    final cursor = store.openCursor(autoAdvance: true);

    await for (final record in cursor) {
      final json = record.value as Map<String, dynamic>;
      // Check if dbSyncStatus == 0 (SyncStatus.local)
      if (json['dbSyncStatus'] == 0) {
        results.add(fromJson(json));
      }
    }

    return results;
  }

  @override
  Future<int> count() async {
    final store = _getStore(mode: idbModeReadOnly);
    return await store.count();
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
    // IndexedDB doesn't have native vector search like ObjectBox HNSW
    // Subclasses would need to implement custom similarity calculation
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
    // IndexedDB transactions are async - can't do sync lookups
    // This is a limitation of IndexedDB vs ObjectBox
    throw UnsupportedError(
      'Synchronous findByIdInTx not supported in IndexedDB. '
      'Use async methods instead.',
    );
  }

  @override
  T? findByUuidInTx(TransactionContext ctx, String uuid) {
    // IndexedDB transactions are async - can't do sync lookups
    throw UnsupportedError(
      'Synchronous findByUuidInTx not supported in IndexedDB. '
      'Use async methods instead.',
    );
  }

  @override
  List<T> findAllInTx(TransactionContext ctx) {
    // IndexedDB transactions are async - can't do sync lookups
    throw UnsupportedError(
      'Synchronous findAllInTx not supported in IndexedDB. '
      'Use async methods instead.',
    );
  }

  @override
  T saveInTx(TransactionContext ctx, T entity) {
    return _executeWithExceptionHandling(() {
      final store = _getStoreInTx(ctx);
      _touchIfNeeded(entity);
      final json = (entity as dynamic).toJson() as Map<String, dynamic>;
      // Note: put() is async in IndexedDB, but we return synchronously
      // The transaction will wait for all promises to complete
      // Don't pass key - extracted from json['uuid']
      store.put(json);
      return entity;
    });
  }

  @override
  List<T> saveAllInTx(TransactionContext ctx, List<T> entities) {
    return _executeWithExceptionHandling(() {
      final store = _getStoreInTx(ctx);
      for (final entity in entities) {
        _touchIfNeeded(entity);
        final json = (entity as dynamic).toJson() as Map<String, dynamic>;
        store.put(json);
      }
      return entities;
    });
  }

  @override
  bool deleteInTx(TransactionContext ctx, int id) {
    // Can't do sync lookup in IndexedDB
    throw UnsupportedError(
      'deleteInTx by id not supported in IndexedDB. '
      'Use deleteByUuidInTx instead.',
    );
  }

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) {
    return _executeWithExceptionHandling(() {
      final store = _getStoreInTx(ctx);
      store.delete(uuid);
      return true;
    });
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) {
    throw UnsupportedError(
      'deleteAllInTx by ids not supported in IndexedDB. '
      'Use deleteByUuidInTx for each entity instead.',
    );
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Database lifecycle is managed externally
    // Don't close the database here - it may be shared
  }
}
