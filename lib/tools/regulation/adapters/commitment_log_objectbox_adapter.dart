/// # CommitmentLogObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for CommitmentLog entities.
/// Supports queries by commitment, date, and date ranges.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = CommitmentLogObjectBoxAdapter(store);
/// final repo = CommitmentLogRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/commitment_log.dart';
import '../../../objectbox.g.dart';

class CommitmentLogObjectBoxAdapter
    implements PersistenceAdapter<CommitmentLog> {
  final Store _store;
  late final Box<CommitmentLog> _box;

  CommitmentLogObjectBoxAdapter(this._store) {
    _box = _store.box<CommitmentLog>();
  }

  Box<CommitmentLog> get box => _box;

  // ============ CRUD ============

  @override
  Future<CommitmentLog?> findById(String uuid) async {
    final query = _box.query(CommitmentLog_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<CommitmentLog> getById(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) {
      throw Exception('CommitmentLog not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  @deprecated
  Future<CommitmentLog?> findByIntId(int id) async {
    return _box.get(id);
  }

  @override
  @deprecated
  Future<CommitmentLog> getByIntId(int id) async {
    final entity = await findByIntId(id);
    if (entity == null) {
      throw Exception('CommitmentLog not found with id: $id');
    }
    return entity;
  }

  @override
  Future<List<CommitmentLog>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<CommitmentLog> save(CommitmentLog entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<CommitmentLog>> saveAll(List<CommitmentLog> entities) async {
    for (final entity in entities) {
      entity.touch();
    }
    _box.putMany(entities);
    return entities;
  }

  @override
  Future<bool> delete(String uuid) async {
    final entity = await findById(uuid);
    if (entity != null) {
      return _box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async {
    return _box.remove(id);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    for (final uuid in uuids) {
      final entity = await findById(uuid);
      if (entity != null) {
        _box.remove(entity.id);
      }
    }
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  @override
  Future<List<CommitmentLog>> findUnsynced() async {
    final query = _box.query(CommitmentLog_.syncId.isNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Transaction Operations ============

  @override
  CommitmentLog? findByIdInTx(TransactionContext ctx, String uuid) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<CommitmentLog>();
    final query = box.query(CommitmentLog_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  @deprecated
  CommitmentLog? findByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<CommitmentLog>();
    return box.get(id);
  }

  @override
  List<CommitmentLog> findAllInTx(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<CommitmentLog>();
    return box.getAll();
  }

  @override
  CommitmentLog saveInTx(TransactionContext ctx, CommitmentLog entity,
      {bool touch = true}) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<CommitmentLog>();
    if (touch) {
      entity.touch();
    }
    box.put(entity);
    return entity;
  }

  @override
  List<CommitmentLog> saveAllInTx(
      TransactionContext ctx, List<CommitmentLog> entities) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<CommitmentLog>();
    for (final entity in entities) {
      entity.touch();
    }
    box.putMany(entities);
    return entities;
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    final entity = findByIdInTx(ctx, uuid);
    if (entity != null) {
      final obCtx = ctx as ObjectBoxTxContext;
      final box = obCtx.store.box<CommitmentLog>();
      return box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<CommitmentLog>();
    return box.remove(id);
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    for (final uuid in uuids) {
      final entity = findByIdInTx(ctx, uuid);
      if (entity != null) {
        final obCtx = ctx as ObjectBoxTxContext;
        final box = obCtx.store.box<CommitmentLog>();
        box.remove(entity.id);
      }
    }
  }

  // ============ Semantic Search (Not Implemented) ============

  @override
  Future<List<CommitmentLog>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    throw UnimplementedError('CommitmentLog does not support semantic search');
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(CommitmentLog entity) generateEmbedding,
  ) async {
    // CommitmentLog doesn't have semantic search, no-op
  }

  // ============ CommitmentLog-Specific Query Methods ============

  /// Find all logs for a specific commitment
  Future<List<CommitmentLog>> findByCommitment(String commitmentId) async {
    final query =
        _box.query(CommitmentLog_.commitmentId.equals(commitmentId)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find log for a commitment on a specific date
  Future<CommitmentLog?> findByCommitmentAndDate(
      String commitmentId, DateTime date) async {
    // Start of day
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final query = _box
        .query(CommitmentLog_.commitmentId.equals(commitmentId) &
            CommitmentLog_.date.betweenDate(start, end))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Find logs within a date range
  Future<List<CommitmentLog>> findByDateRange(
      DateTime start, DateTime end) async {
    final query = _box
        .query(CommitmentLog_.date.betweenDate(start, end))
        .order(CommitmentLog_.date)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Get completion rate for a commitment (percentage of completed logs)
  Future<double> getCompletionRate(String commitmentId) async {
    final logs = await findByCommitment(commitmentId);
    if (logs.isEmpty) {
      return 0.0;
    }

    final completedCount = logs.where((log) => log.completed).length;
    return (completedCount / logs.length) * 100;
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle managed externally
  }
}
