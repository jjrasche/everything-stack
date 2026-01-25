/// # CommitmentObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Commitment entities.
/// Supports queries for active commitments, by person, and by interval.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = CommitmentObjectBoxAdapter(store);
/// final repo = CommitmentRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/commitment.dart';
import '../../../objectbox.g.dart';

class CommitmentObjectBoxAdapter implements PersistenceAdapter<Commitment> {
  final Store _store;
  late final Box<Commitment> _box;

  CommitmentObjectBoxAdapter(this._store) {
    _box = _store.box<Commitment>();
  }

  Box<Commitment> get box => _box;

  // ============ CRUD ============

  @override
  Future<Commitment?> findById(String uuid) async {
    final query = _box.query(Commitment_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<Commitment> getById(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) {
      throw Exception('Commitment not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  @deprecated
  Future<Commitment?> findByIntId(int id) async {
    return _box.get(id);
  }

  @override
  @deprecated
  Future<Commitment> getByIntId(int id) async {
    final entity = await findByIntId(id);
    if (entity == null) {
      throw Exception('Commitment not found with id: $id');
    }
    return entity;
  }

  @override
  Future<List<Commitment>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Commitment> save(Commitment entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Commitment>> saveAll(List<Commitment> entities) async {
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
  Future<List<Commitment>> findUnsynced() async {
    final query = _box.query(Commitment_.syncId.isNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Transaction Operations ============

  @override
  Commitment? findByIdInTx(TransactionContext ctx, String uuid) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Commitment>();
    final query = box.query(Commitment_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  @deprecated
  Commitment? findByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Commitment>();
    return box.get(id);
  }

  @override
  List<Commitment> findAllInTx(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Commitment>();
    return box.getAll();
  }

  @override
  Commitment saveInTx(TransactionContext ctx, Commitment entity,
      {bool touch = true}) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Commitment>();
    if (touch) {
      entity.touch();
    }
    box.put(entity);
    return entity;
  }

  @override
  List<Commitment> saveAllInTx(
      TransactionContext ctx, List<Commitment> entities) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Commitment>();
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
      final box = obCtx.store.box<Commitment>();
      return box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Commitment>();
    return box.remove(id);
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    for (final uuid in uuids) {
      final entity = findByIdInTx(ctx, uuid);
      if (entity != null) {
        final obCtx = ctx as ObjectBoxTxContext;
        final box = obCtx.store.box<Commitment>();
        box.remove(entity.id);
      }
    }
  }

  // ============ Semantic Search (Not Implemented) ============

  @override
  Future<List<Commitment>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    throw UnimplementedError('Commitment does not support semantic search');
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Commitment entity) generateEmbedding,
  ) async {
    // Commitment doesn't have semantic search, no-op
  }

  // ============ Commitment-Specific Query Methods ============

  /// Find all active commitments
  Future<List<Commitment>> findActive() async {
    final query = _box.query(Commitment_.active.equals(true)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find all commitments for a specific person (by UUID in personIds list)
  Future<List<Commitment>> findByPerson(String personId) async {
    // Query: dbPersonIds contains personId
    // Note: Contains query on comma-separated string
    final allCommitments = await findAll();
    return allCommitments
        .where((commitment) => commitment.personIds.contains(personId))
        .toList();
  }

  /// Find commitments by interval
  Future<List<Commitment>> findByInterval(String interval) async {
    final query = _box.query(Commitment_.interval.equals(interval)).build();
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
  }
}
