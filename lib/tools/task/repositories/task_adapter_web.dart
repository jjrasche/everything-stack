/// Web platform Task adapter factory (IndexedDB)
///
/// This file is only imported on web platform. It creates the
/// IndexedDB-based adapter for TaskRepository.
library;

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/task.dart';
import '../adapters/task_indexeddb_adapter.dart';

/// Create the appropriate adapter for web platform (IndexedDB)
///
/// Note: This returns a lazy adapter that initializes on first use
/// because IndexedDB requires async initialization.
PersistenceAdapter<Task> createTaskAdapter() {
  return _LazyIndexedDBAdapter();
}

/// Lazy adapter for web - delegates to IndexedDB on first use
class _LazyIndexedDBAdapter implements PersistenceAdapter<Task> {
  late PersistenceAdapter<Task> _delegate;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _delegate = await TaskIndexedDBAdapter.create();
      _initialized = true;
    }
  }

  // ============ CRUD ============

  @override
  Future<Task?> findById(String uuid) async {
    await _ensureInitialized();
    return _delegate.findById(uuid);
  }

  @override
  Future<Task> getById(String uuid) async {
    await _ensureInitialized();
    return _delegate.getById(uuid);
  }

  @override
  @deprecated
  Future<Task?> findByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.findByIntId(id);
  }

  @override
  @deprecated
  Future<Task> getByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.getByIntId(id);
  }

  @override
  Future<List<Task>> findAll() async {
    await _ensureInitialized();
    return _delegate.findAll();
  }

  @override
  Future<Task> save(Task entity, {bool touch = true}) async {
    await _ensureInitialized();
    return _delegate.save(entity, touch: touch);
  }

  @override
  Future<List<Task>> saveAll(List<Task> entities) async {
    await _ensureInitialized();
    return _delegate.saveAll(entities);
  }

  @override
  Future<bool> delete(String uuid) async {
    await _ensureInitialized();
    return _delegate.delete(uuid);
  }

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.deleteByIntId(id);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    await _ensureInitialized();
    return _delegate.deleteAll(uuids);
  }

  // ============ Queries ============

  @override
  Future<List<Task>> findUnsynced() async {
    await _ensureInitialized();
    return _delegate.findUnsynced();
  }

  @override
  Future<int> count() async {
    await _ensureInitialized();
    return _delegate.count();
  }

  // ============ Semantic Search ============

  @override
  Future<List<Task>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    await _ensureInitialized();
    return _delegate.semanticSearch(
      queryVector,
      limit: limit,
      minSimilarity: minSimilarity,
    );
  }

  @override
  int get indexSize {
    if (!_initialized) return 0;
    return _delegate.indexSize;
  }

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) async {
    await _ensureInitialized();
    return _delegate.rebuildIndex(generateEmbedding);
  }

  // ============ Transaction Operations ============
  // Note: These throw UnsupportedError because the lazy wrapper
  // cannot be used synchronously. Use the async methods instead.

  @override
  Task? findByIdInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError(
      'Synchronous findByIdInTx not supported with lazy adapter. '
      'Use async findById instead.',
    );
  }

  @override
  @deprecated
  Task? findByIntIdInTx(TransactionContext ctx, int id) {
    throw UnsupportedError(
      'Synchronous findByIntIdInTx not supported with lazy adapter. '
      'Use async findById instead.',
    );
  }

  @override
  List<Task> findAllInTx(TransactionContext ctx) {
    throw UnsupportedError(
      'Synchronous findAllInTx not supported with lazy adapter. '
      'Use async findAll instead.',
    );
  }

  @override
  Task saveInTx(TransactionContext ctx, Task entity, {bool touch = true}) {
    throw UnsupportedError(
      'Synchronous saveInTx not supported with lazy adapter. '
      'Use async save instead.',
    );
  }

  @override
  List<Task> saveAllInTx(TransactionContext ctx, List<Task> entities) {
    throw UnsupportedError(
      'Synchronous saveAllInTx not supported with lazy adapter. '
      'Use async saveAll instead.',
    );
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError(
      'Synchronous deleteInTx not supported with lazy adapter. '
      'Use async delete instead.',
    );
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    throw UnsupportedError(
      'Synchronous deleteByIntIdInTx not supported with lazy adapter. '
      'Use async delete instead.',
    );
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    throw UnsupportedError(
      'Synchronous deleteAllInTx not supported with lazy adapter. '
      'Use async deleteAll instead.',
    );
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    if (_initialized) {
      await _delegate.close();
    }
  }
}
