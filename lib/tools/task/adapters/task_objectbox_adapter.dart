/// # TaskObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Task entities.
/// Task uses direct @Entity annotations (no wrapper needed).
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = TaskObjectBoxAdapter(store);
/// final repo = TaskRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/base_entity.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../../../core/exceptions/persistence_exceptions.dart';
import '../entities/task.dart';
import '../../../objectbox.g.dart';

class TaskObjectBoxAdapter implements PersistenceAdapter<Task> {
  final Store _store;
  late final Box<Task> _box;

  TaskObjectBoxAdapter(this._store) {
    _box = _store.box<Task>();
  }

  Box<Task> get box => _box;

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<Task?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<Task> getById(int id) async {
    final entity = await findById(id);
    if (entity == null) {
      throw Exception('Task not found with id: $id');
    }
    return entity;
  }

  @override
  Future<Task?> findByUuid(String uuid) async {
    final query = _box.query(Task_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<Task> getByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) {
      throw Exception('Task not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  Future<List<Task>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Task> save(Task entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Task>> saveAll(List<Task> entities) async {
    for (final entity in entities) {
      entity.touch();
    }
    _box.putMany(entities);
    return entities;
  }

  @override
  Future<bool> delete(int id) async {
    return _box.remove(id);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity != null) {
      return _box.remove(entity.id);
    }
    return false;
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    _box.removeMany(ids);
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  @override
  Future<List<Task>> findUnsynced() async {
    final query = _box.query(Task_.syncId.isNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }


  @override
  Task saveInTx(TransactionContext ctx, Task entity, {bool touch = true}) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    if (touch) {
      entity.touch();
    }
    box.put(entity);
    return entity;
  }

  @override
  bool deleteInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    return box.remove(id);
  }

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) {
    final entity = findByUuidInTx(ctx, uuid);
    if (entity != null) {
      final obCtx = ctx as ObjectBoxTxContext;
      final box = obCtx.store.box<Task>();
      return box.remove(entity.id);
    }
    return false;
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    box.removeMany(ids);
  }

  @override
  Task? findByUuidInTx(TransactionContext ctx, String uuid) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    final query = box.query(Task_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Task? findByIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    return box.get(id);
  }

  @override
  List<Task> findAllInTx(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    return box.getAll();
  }

  @override
  List<Task> saveAllInTx(TransactionContext ctx, List<Task> entities) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Task>();
    for (final entity in entities) {
      entity.touch();
    }
    box.putMany(entities);
    return entities;
  }

  // ============ Semantic Search (Not Implemented for Task) ============

  @override
  Future<List<Task>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    throw UnimplementedError('Task does not support semantic search');
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) async {
    // Task doesn't have semantic search, no-op
  }

  // ============ Task-Specific Query Methods ============

  /// Find incomplete tasks
  Future<List<Task>> findIncomplete() async {
    final query = _box.query(Task_.completed.equals(false)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find completed tasks
  Future<List<Task>> findCompleted() async {
    final query = _box.query(Task_.completed.equals(true)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find overdue tasks
  Future<List<Task>> findOverdue() async {
    final now = DateTime.now();
    final query = _box
        .query(
          Task_.completed.equals(false) &
          Task_.dueDate.notNull() &
          Task_.dueDate.lessThan(now.millisecondsSinceEpoch),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find tasks by priority
  Future<List<Task>> findByPriority(String priority) async {
    final query = _box
        .query(
          Task_.priority.equals(priority) & Task_.completed.equals(false),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find tasks by owner
  Future<List<Task>> findByOwner(String userId) async {
    final query = _box.query(Task_.ownerId.equals(userId)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle managed externally
    // Don't close the store here
  }
}
