/// # TimerObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Timer entities.
/// Timer uses direct @Entity annotations (no wrapper needed).
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = TimerObjectBoxAdapter(store);
/// final repo = TimerRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/timer.dart';
import '../../../objectbox.g.dart';

class TimerObjectBoxAdapter implements PersistenceAdapter<Timer> {
  final Store _store;
  late final Box<Timer> _box;

  TimerObjectBoxAdapter(this._store) {
    _box = _store.box<Timer>();
  }

  Box<Timer> get box => _box;

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<Timer?> findById(String uuid) async {
    final query = _box.query(Timer_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<Timer> getById(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) {
      throw Exception('Timer not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  @deprecated
  Future<Timer?> findByIntId(int id) async {
    return _box.get(id);
  }

  @override
  @deprecated
  Future<Timer> getByIntId(int id) async {
    final entity = await findByIntId(id);
    if (entity == null) {
      throw Exception('Timer not found with id: $id');
    }
    return entity;
  }

  @override
  Future<List<Timer>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Timer> save(Timer entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Timer>> saveAll(List<Timer> entities) async {
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
  Future<List<Timer>> findUnsynced() async {
    final query = _box.query(Timer_.syncId.isNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Timer saveInTx(TransactionContext ctx, Timer entity, {bool touch = true}) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Timer>();
    if (touch) {
      entity.touch();
    }
    box.put(entity);
    return entity;
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    final entity = findByIdInTx(ctx, uuid);
    if (entity != null) {
      final obCtx = ctx as ObjectBoxTxContext;
      final box = obCtx.store.box<Timer>();
      return box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Timer>();
    return box.remove(id);
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    for (final uuid in uuids) {
      final entity = findByIdInTx(ctx, uuid);
      if (entity != null) {
        final obCtx = ctx as ObjectBoxTxContext;
        final box = obCtx.store.box<Timer>();
        box.remove(entity.id);
      }
    }
  }

  @override
  Timer? findByIdInTx(TransactionContext ctx, String uuid) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Timer>();
    final query = box.query(Timer_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  @deprecated
  Timer? findByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Timer>();
    return box.get(id);
  }

  @override
  List<Timer> findAllInTx(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Timer>();
    return box.getAll();
  }

  @override
  List<Timer> saveAllInTx(TransactionContext ctx, List<Timer> entities) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Timer>();
    for (final entity in entities) {
      entity.touch();
    }
    box.putMany(entities);
    return entities;
  }

  // ============ Semantic Search (Not Implemented for Timer) ============

  @override
  Future<List<Timer>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    throw UnimplementedError('Timer does not support semantic search');
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Timer entity) generateEmbedding,
  ) async {
    // Timer doesn't have semantic search, no-op
  }

  // ============ Timer-Specific Query Methods ============

  /// Find active timers (not fired, still running)
  Future<List<Timer>> findActive() async {
    final now = DateTime.now();
    final query = _box
        .query(
          Timer_.fired.equals(false) &
              Timer_.endsAt.greaterThan(now.millisecondsSinceEpoch),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find expired timers (past endsAt but not marked as fired)
  Future<List<Timer>> findExpired() async {
    final now = DateTime.now();
    final query = _box
        .query(
          Timer_.fired.equals(false) &
              Timer_.endsAt.lessOrEqual(now.millisecondsSinceEpoch),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find fired timers
  Future<List<Timer>> findFired() async {
    final query = _box.query(Timer_.fired.equals(true)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find timer by label
  Future<Timer?> findByLabel(String label) async {
    final query = _box
        .query(
          Timer_.label.equals(label) & Timer_.fired.equals(false),
        )
        .build();
    try {
      return query.findFirst();
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
