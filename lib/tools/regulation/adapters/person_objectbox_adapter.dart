/// # PersonObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Person entities.
/// Person uses direct @Entity annotations (no wrapper needed).
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = PersonObjectBoxAdapter(store);
/// final repo = PersonRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/person.dart';
import '../../../objectbox.g.dart';

class PersonObjectBoxAdapter implements PersistenceAdapter<Person> {
  final Store _store;
  late final Box<Person> _box;

  PersonObjectBoxAdapter(this._store) {
    _box = _store.box<Person>();
  }

  Box<Person> get box => _box;

  // ============ CRUD ============

  @override
  Future<Person?> findById(String uuid) async {
    final query = _box.query(Person_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<Person> getById(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) {
      throw Exception('Person not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  @deprecated
  Future<Person?> findByIntId(int id) async {
    return _box.get(id);
  }

  @override
  @deprecated
  Future<Person> getByIntId(int id) async {
    final entity = await findByIntId(id);
    if (entity == null) {
      throw Exception('Person not found with id: $id');
    }
    return entity;
  }

  @override
  Future<List<Person>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Person> save(Person entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Person>> saveAll(List<Person> entities) async {
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
  Future<List<Person>> findUnsynced() async {
    final query = _box.query(Person_.syncId.isNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Transaction Operations ============

  @override
  Person? findByIdInTx(TransactionContext ctx, String uuid) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Person>();
    final query = box.query(Person_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  @deprecated
  Person? findByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Person>();
    return box.get(id);
  }

  @override
  List<Person> findAllInTx(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Person>();
    return box.getAll();
  }

  @override
  Person saveInTx(TransactionContext ctx, Person entity, {bool touch = true}) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Person>();
    if (touch) {
      entity.touch();
    }
    box.put(entity);
    return entity;
  }

  @override
  List<Person> saveAllInTx(TransactionContext ctx, List<Person> entities) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Person>();
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
      final box = obCtx.store.box<Person>();
      return box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<Person>();
    return box.remove(id);
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    for (final uuid in uuids) {
      final entity = findByIdInTx(ctx, uuid);
      if (entity != null) {
        final obCtx = ctx as ObjectBoxTxContext;
        final box = obCtx.store.box<Person>();
        box.remove(entity.id);
      }
    }
  }

  // ============ Semantic Search (Not Implemented for Person) ============

  @override
  Future<List<Person>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    throw UnimplementedError('Person does not support semantic search');
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Person entity) generateEmbedding,
  ) async {
    // Person doesn't have semantic search, no-op
  }

  // ============ Person-Specific Query Methods ============

  /// Find person by name (case-insensitive)
  Future<Person?> findByName(String name) async {
    final query = _box
        .query(Person_.name.equals(name, caseSensitive: false))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Find all people with a specific role
  Future<List<Person>> findByRole(String role) async {
    final query = _box.query(Person_.role.equals(role)).build();
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
