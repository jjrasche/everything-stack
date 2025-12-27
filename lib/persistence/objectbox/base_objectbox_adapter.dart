/// # BaseObjectBoxAdapter (Path C: Anti-Corruption Layer)
///
/// ## What it does
/// Base implementation of PersistenceAdapter for ObjectBox with wrapper support.
/// Generic over BOTH domain entity (T) and ObjectBox wrapper (OB) types.
///
/// ## Path C Pattern
/// Domain entities stay clean (no ObjectBox annotations).
/// ObjectBox wrappers (NoteOB, EdgeOB, etc.) have all annotations.
/// Base adapter handles conversion automatically.
///
/// ## How it works
/// ```dart
/// class NoteObjectBoxAdapter extends BaseObjectBoxAdapter<Note, NoteOB> {
///   NoteObjectBoxAdapter(Store store) : super(store);
///
///   @override
///   NoteOB toOB(Note entity) => NoteOB.fromNote(entity);
///
///   @override
///   Note fromOB(NoteOB ob) => ob.toNote();
///
///   @override
///   Condition<NoteOB> uuidEqualsCondition(String uuid) =>
///       NoteOB_.uuid.equals(uuid);
///
///   @override
///   Condition<NoteOB> syncStatusLocalCondition() =>
///       NoteOB_.dbSyncStatus.equals(SyncStatus.local.index);
/// }
/// ```

import 'package:meta/meta.dart';
import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../core/persistence/transaction_context.dart';
import '../../core/persistence/objectbox_tx_context.dart';
import '../../core/exceptions/persistence_exceptions.dart';

/// Base ObjectBox adapter with Anti-Corruption Layer pattern.
///
/// Generic over domain entity (T) and ObjectBox wrapper (OB) types.
/// Handles all CRUD logic with automatic wrapper conversion.
abstract class BaseObjectBoxAdapter<T extends BaseEntity, OB>
    implements PersistenceAdapter<T> {
  final Store _store;
  late final Box<OB> _box;

  BaseObjectBoxAdapter(this._store) {
    _box = _store.box<OB>();
  }

  /// Access to the ObjectBox wrapper box.
  /// Used by subclass-specific queries.
  @protected
  Box<OB> get box => _box;

  // ============ Abstract Methods (Subclass Must Provide) ============

  /// Convert domain entity to ObjectBox wrapper.
  OB toOB(T entity);

  /// Convert ObjectBox wrapper to domain entity.
  T fromOB(OB ob);

  /// Condition for finding wrapper by UUID.
  /// Example: NoteOB_.uuid.equals(uuid)
  Condition<OB> uuidEqualsCondition(String uuid);

  /// Condition for finding unsynced wrappers.
  /// Example: NoteOB_.dbSyncStatus.equals(SyncStatus.local.index)
  Condition<OB> syncStatusLocalCondition();

  /// Whether to call touch() on entities before saving.
  /// Override to false for immutable entities (e.g., EntityVersion).
  bool get shouldTouchOnSave => true;

  // ============ Helper Methods ============

  /// Get box from transaction context.
  Box<OB> _getBox(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    return obCtx.store.box<OB>();
  }

  /// Execute query and ensure cleanup.
  R _executeQuery<R>(Query<OB> query, R Function(Query<OB>) work) {
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
      throw DuplicateEntityException(
        entityType,
        'unique constraint',
        fieldValue: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is NonUniqueResultException) {
      throw QueryException(
        'Query returned multiple ${entityType}s when expecting one',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is NumericOverflowException) {
      throw QueryException(
        'Numeric overflow in $entityType query',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is StorageException) {
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
      throw PersistenceException(
        'Storage error: $message',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is SchemaException) {
      throw PersistenceException(
        'Schema error for $entityType: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ObjectBoxException) {
      throw PersistenceException(
        'ObjectBox error for $entityType: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }

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

  // ============ CRUD (with automatic wrapper conversion) ============

  @override
  Future<T?> findById(String uuid) async {
    final query = _box.query(uuidEqualsCondition(uuid)).build();
    return _executeQuery(query, (q) {
      final ob = q.findFirst();
      return ob != null ? fromOB(ob) : null;
    });
  }

  @override
  Future<T> getById(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) {
      throw EntityNotFoundException(T.toString(), uuid: uuid);
    }
    return entity;
  }

  @override
  @deprecated
  Future<T?> findByIntId(int id) async {
    final ob = _box.get(id);
    return ob != null ? fromOB(ob) : null;
  }

  @override
  @deprecated
  Future<T> getByIntId(int id) async {
    final entity = await findByIntId(id);
    if (entity == null) {
      throw EntityNotFoundException(T.toString(), id: id);
    }
    return entity;
  }

  @override
  Future<List<T>> findAll() async {
    final obList = _box.getAll();
    return obList.map((ob) => fromOB(ob)).toList();
  }

  @override
  Future<T> save(T entity, {bool touch = true}) async {
    return _executeAsyncWithExceptionHandling(() async {
      if (touch) {
        _touchIfNeeded(entity);
      }
      // If touch=false, skip updatedAt update. Used for background async
      // operations that update entities without user action (e.g., embedding
      // generation). Prevents updatedAt collision on side-effect updates.
      final ob = toOB(entity);
      final id = _box.put(ob);
      entity.id = id;
      return entity;
    });
  }

  @override
  Future<List<T>> saveAll(List<T> entities) async {
    return _executeAsyncWithExceptionHandling(() async {
      for (final entity in entities) {
        _touchIfNeeded(entity);
      }
      final obList = entities.map((e) => toOB(e)).toList();
      final ids = _box.putMany(obList);
      for (var i = 0; i < entities.length; i++) {
        entities[i].id = ids[i];
      }
      return entities;
    });
  }

  @override
  Future<bool> delete(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) return false;
    return _box.remove(entity.id);
  }

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async {
    return _box.remove(id);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    final entities = await Future.wait(uuids.map((uuid) => findById(uuid)));
    final ids = <int>[];
    for (final entity in entities) {
      if (entity != null) {
        ids.add(entity.id);
      }
    }
    if (ids.isNotEmpty) {
      _box.removeMany(ids);
    }
  }

  // ============ Queries ============

  @override
  Future<List<T>> findUnsynced() async {
    final query = _box.query(syncStatusLocalCondition()).build();
    return _executeQuery(query, (q) {
      final obList = q.find();
      return obList.map((ob) => fromOB(ob)).toList();
    });
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  // ============ Semantic Search ============
  // Default: no semantic search (entities without embeddings override this)

  @override
  Future<List<T>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    return [];
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(T entity) generateEmbedding,
  ) async {
    // No-op for entities without embeddings
  }

  // ============ Transaction Operations ============

  @override
  T? findByIdInTx(TransactionContext ctx, String uuid) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      final query = box.query(uuidEqualsCondition(uuid)).build();
      return _executeQuery(query, (q) {
        final ob = q.findFirst();
        return ob != null ? fromOB(ob) : null;
      });
    });
  }

  @override
  @deprecated
  T? findByIntIdInTx(TransactionContext ctx, int id) {
    final box = _getBox(ctx);
    final ob = box.get(id);
    return ob != null ? fromOB(ob) : null;
  }

  @override
  List<T> findAllInTx(TransactionContext ctx) {
    final box = _getBox(ctx);
    final obList = box.getAll();
    return obList.map((ob) => fromOB(ob)).toList();
  }

  @override
  T saveInTx(TransactionContext ctx, T entity, {bool touch = true}) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      if (touch) {
        _touchIfNeeded(entity);
      }
      // If touch=false, skip updatedAt update. Used for background async
      // operations that update entities without user action (e.g., embedding
      // generation). Prevents updatedAt collision on side-effect updates.
      final ob = toOB(entity);
      final id = box.put(ob);
      entity.id = id;
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
      final obList = entities.map((e) => toOB(e)).toList();
      final ids = box.putMany(obList);
      for (var i = 0; i < entities.length; i++) {
        entities[i].id = ids[i];
      }
      return entities;
    });
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      final query = box.query(uuidEqualsCondition(uuid)).build();
      return _executeQuery(query, (q) {
        final ob = q.findFirst();
        if (ob == null) return false;
        // Convert to get entity ID
        final entity = fromOB(ob);
        return box.remove(entity.id);
      });
    });
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    return _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      return box.remove(id);
    });
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    _executeWithExceptionHandling(() {
      final box = _getBox(ctx);
      for (final uuid in uuids) {
        final query = box.query(uuidEqualsCondition(uuid)).build();
        _executeQuery(query, (q) {
          final ob = q.findFirst();
          if (ob != null) {
            final entity = fromOB(ob);
            box.remove(entity.id);
          }
          return null;
        });
      }
    });
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle is managed externally
  }
}
