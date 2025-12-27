/// # TaskRepository
///
/// ## What it does
/// Repository for Task entities. Manages user tasks/todos.
/// Owns adapter selection - uses ObjectBox on native, IndexedDB on web.

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../../core/entity_repository.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../services/embedding_service.dart';
import '../entities/task.dart';
import '../adapters/task_indexeddb_adapter.dart' as indexeddb;
// Conditional import: real ObjectBox adapter on native, stub on web
// This prevents Dart analyzer from analyzing `dart:ffi` code on web platforms
import '../adapters/task_objectbox_adapter.dart'
    if (dart.library.html) '../adapters/task_objectbox_adapter_stub.dart'
    as objectbox;

class TaskRepository extends EntityRepository<Task> {
  TaskRepository({EmbeddingService? embeddingService})
      : super(
          adapter: _createAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  /// Create appropriate adapter based on platform
  static PersistenceAdapter<Task> _createAdapter() {
    if (kIsWeb) {
      // Web: IndexedDB
      return _WebTaskAdapter();
    } else {
      // Native: ObjectBox
      // Store is registered in bootstrap.dart
      final getIt = GetIt.instance;
      // ignore: avoid_dynamic_calls
      final store = getIt(instanceName: 'objectBoxStore');
      // ignore: unsafe_html
      return objectbox.TaskObjectBoxAdapter(store as dynamic);
    }
  }
}

/// Lazy adapter for web - delegates to IndexedDB on first use
class _WebTaskAdapter implements PersistenceAdapter<Task> {
  late PersistenceAdapter<Task> _delegate;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _delegate = await indexeddb.TaskIndexedDBAdapter.create();
      _initialized = true;
    }
  }

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
    return _delegate.findByIntId(id);
  }

  @override
  @deprecated
  Future<Task> getByIntId(int id) async {
    await _ensureInitialized();
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
    return _delegate.deleteByIntId(id);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    await _ensureInitialized();
    return _delegate.deleteAll(uuids);
  }

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

  @override
  Future<List<Task>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    await _ensureInitialized();
    return _delegate.semanticSearch(queryVector,
        limit: limit, minSimilarity: minSimilarity);
  }

  @override
  int get indexSize {
    // Not available before initialization
    return 0;
  }

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) async {
    await _ensureInitialized();
    return _delegate.rebuildIndex(generateEmbedding);
  }

  @override
  Task? findByIdInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  @deprecated
  Task? findByIntIdInTx(TransactionContext ctx, int id) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  List<Task> findAllInTx(TransactionContext ctx) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  Task saveInTx(TransactionContext ctx, Task entity, {bool touch = true}) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  List<Task> saveAllInTx(TransactionContext ctx, List<Task> entities) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    throw UnsupportedError('Transaction methods not supported in web adapter');
  }

  @override
  Future<void> close() async {
    await _ensureInitialized();
    return _delegate.close();
  }
}
