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
  late final PersistenceAdapter<Task> _adapter;

  TaskRepository({EmbeddingService? embeddingService})
      : super(
          adapter: _PlatformAdapterProxy(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  static PersistenceAdapter<Task> createAdapter() {
    if (kIsWeb) {
      return _WebTaskAdapter();
    } else {
      // ObjectBox adapter will be created when store becomes available
      // For now, use lazy proxy
      return _ObjectBoxLazyProxy();
    }
  }
}

/// Platform-agnostic proxy that delegates to the right adapter
class _PlatformAdapterProxy implements PersistenceAdapter<Task> {
  late PersistenceAdapter<Task> _delegate;

  _PlatformAdapterProxy() {
    if (kIsWeb) {
      _delegate = _WebTaskAdapter();
    } else {
      _delegate = _ObjectBoxLazyProxy();
    }
  }

  @override
  Future<Task?> findById(int id) => _delegate.findById(id);

  @override
  Future<Task> getById(int id) => _delegate.getById(id);

  @override
  Future<Task?> findByUuid(String uuid) => _delegate.findByUuid(uuid);

  @override
  Future<List<Task>> findAll() => _delegate.findAll();

  @override
  Future<Task> save(Task task) => _delegate.save(task);

  @override
  Future<List<Task>> saveAll(List<Task> items) => _delegate.saveAll(items);

  @override
  Future<bool> delete(Task task) => _delegate.delete(task);

  @override
  Future<int> deleteAll(List<Task> items) => _delegate.deleteAll(items);

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<List<Task>> query(
      {required int offset,
      required int limit,
      String? sortBy,
      bool descending = false}) =>
      _delegate.query(
          offset: offset,
          limit: limit,
          sortBy: sortBy,
          descending: descending);
}

/// Lazy proxy for ObjectBox that defers store access
class _ObjectBoxLazyProxy implements PersistenceAdapter<Task> {
  PersistenceAdapter<Task>? _delegate;

  Future<PersistenceAdapter<Task>> _getDelegate() async {
    if (_delegate != null) return _delegate!;

    // Try to get store from GetIt
    try {
      final getIt = GetIt.instance;
      // Note: actual type will be Store when bootstrap registers it
      final store = getIt.get(instanceName: 'objectBoxStore');
      _delegate = objectbox.TaskObjectBoxAdapter(store as dynamic);
    } catch (e) {
      throw StateError(
        'ObjectBox store not found in GetIt. Call initializeEverythingStack() first.',
      );
    }
    return _delegate!;
  }

  @override
  Future<Task?> findById(int id) async {
    final delegate = await _getDelegate();
    return delegate.findById(id);
  }

  @override
  Future<Task> getById(int id) async {
    final delegate = await _getDelegate();
    return delegate.getById(id);
  }

  @override
  Future<Task?> findByUuid(String uuid) async {
    final delegate = await _getDelegate();
    return delegate.findByUuid(uuid);
  }

  @override
  Future<List<Task>> findAll() async {
    final delegate = await _getDelegate();
    return delegate.findAll();
  }

  @override
  Future<Task> save(Task task) async {
    final delegate = await _getDelegate();
    return delegate.save(task);
  }

  @override
  Future<List<Task>> saveAll(List<Task> items) async {
    final delegate = await _getDelegate();
    return delegate.saveAll(items);
  }

  @override
  Future<bool> delete(Task task) async {
    final delegate = await _getDelegate();
    return delegate.delete(task);
  }

  @override
  Future<int> deleteAll(List<Task> items) async {
    final delegate = await _getDelegate();
    return delegate.deleteAll(items);
  }

  @override
  Future<void> clear() async {
    final delegate = await _getDelegate();
    return delegate.clear();
  }

  @override
  Future<List<Task>> query(
      {required int offset,
      required int limit,
      String? sortBy,
      bool descending = false}) async {
    final delegate = await _getDelegate();
    return delegate.query(
        offset: offset,
        limit: limit,
        sortBy: sortBy,
        descending: descending);
  }
}

/// Stub adapter for web - delegates to IndexedDB on first use
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
  Future<Task?> findById(int id) async {
    await _ensureInitialized();
    return _delegate.findById(id);
  }

  @override
  Future<Task> getById(int id) async {
    await _ensureInitialized();
    return _delegate.getById(id);
  }

  @override
  Future<Task?> findByUuid(String uuid) async {
    await _ensureInitialized();
    return _delegate.findByUuid(uuid);
  }

  @override
  Future<Task> getByUuid(String uuid) async {
    await _ensureInitialized();
    return _delegate.getByUuid(uuid);
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
  Future<bool> delete(int id) async {
    await _ensureInitialized();
    return _delegate.delete(id);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    await _ensureInitialized();
    return _delegate.deleteByUuid(uuid);
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    await _ensureInitialized();
    return _delegate.deleteAll(ids);
  }

  @override
  Future<void> close() async {
    await _ensureInitialized();
    return _delegate.close();
  }

  @override
  Future<int> count() async {
    await _ensureInitialized();
    return _delegate.count();
  }

  @override
  Future<List<Task>> findUnsynced() async {
    await _ensureInitialized();
    return _delegate.findUnsynced();
  }

  @override
  int get indexSize {
    // We can't ensure initialized in a getter, so return 0
    // The caller should have called an async method first
    return _delegate.indexSize;
  }

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) async {
    await _ensureInitialized();
    return _delegate.rebuildIndex(generateEmbedding);
  }

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
  Task? findByIdInTx(TransactionContext ctx, int id) {
    // Can't lazily initialize in sync method
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  Task? findByUuidInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  List<Task> findAllInTx(TransactionContext ctx) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  Task saveInTx(TransactionContext ctx, Task entity, {bool touch = true}) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  List<Task> saveAllInTx(TransactionContext ctx, List<Task> entities) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  bool deleteInTx(TransactionContext ctx, int id) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) {
    throw UnsupportedError(
      'Transactions not supported in lazy-initialized web adapter. '
      'Initialize the adapter first with an async call.',
    );
  }
}

extension TaskRepositoryQueries on TaskRepository {
  // ============ Task-specific queries ============

  /// Find all incomplete tasks, ordered by due date
  Future<List<Task>> findIncomplete() async {
    final all = await findAll();
    final incomplete = all.where((task) => task.isIncomplete).toList();
    incomplete.sort((a, b) {
      // High priority first
      if (a.isHighPriority != b.isHighPriority) {
        return a.isHighPriority ? -1 : 1;
      }
      // Then by due date (nulls last)
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return incomplete;
  }

  /// Find completed tasks
  Future<List<Task>> findCompleted() async {
    final all = await findAll();
    return all.where((task) => task.completed).toList()
      ..sort((a, b) => (b.completedAt ?? b.updatedAt)
          .compareTo(a.completedAt ?? a.updatedAt));
  }

  /// Find overdue tasks
  Future<List<Task>> findOverdue() async {
    final all = await findAll();
    return all.where((task) => task.isOverdue).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  /// Find tasks due today
  Future<List<Task>> findDueToday() async {
    final all = await findAll();
    return all.where((task) => task.isDueToday).toList();
  }

  /// Find tasks due soon (within 24 hours)
  Future<List<Task>> findDueSoon() async {
    final all = await findAll();
    return all.where((task) => task.isDueSoon).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  /// Find high priority tasks
  Future<List<Task>> findHighPriority() async {
    final all = await findAll();
    return all
        .where((task) => task.isHighPriority && task.isIncomplete)
        .toList();
  }

  /// Find tasks by priority
  Future<List<Task>> findByPriority(String priority) async {
    final all = await findAll();
    return all
        .where((task) => task.priority == priority && task.isIncomplete)
        .toList();
  }

  /// Find tasks owned by a user
  Future<List<Task>> findByOwner(String userId) async {
    final all = await findAll();
    return all.where((task) => task.ownerId == userId).toList();
  }

  /// Find tasks accessible to a user (owned or shared)
  Future<List<Task>> findAccessibleBy(String userId) async {
    final all = await findAll();
    return all.where((task) => task.isAccessibleBy(userId)).toList();
  }

  /// Find tasks created by a specific tool invocation
  Future<List<Task>> findByCorrelationId(String correlationId) async {
    final all = await findAll();
    return all
        .where((task) => task.invocationCorrelationId == correlationId)
        .toList();
  }
}
