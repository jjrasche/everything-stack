/// # SubscriptionObjectBoxAdapter
///
/// ObjectBox implementation of PersistenceAdapter for Subscription entities.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = SubscriptionObjectBoxAdapter(store);
/// final repo = SubscriptionRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/subscription.dart';
import '../../../objectbox.g.dart';

class SubscriptionObjectBoxAdapter implements PersistenceAdapter<Subscription> {
  final Store _store;
  late final Box<Subscription> _box;

  SubscriptionObjectBoxAdapter(this._store) {
    _box = _store.box<Subscription>();
  }

  Box<Subscription> get box => _box;

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<Subscription?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<Subscription> getById(int id) async {
    final entity = await findById(id);
    if (entity == null) {
      throw Exception('Subscription not found with id: $id');
    }
    return entity;
  }

  @override
  Future<Subscription?> findByUuid(String uuid) async {
    final query = _box.query(Subscription_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<Subscription> getByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) {
      throw Exception('Subscription not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  Future<List<Subscription>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Subscription> save(Subscription entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Subscription>> saveAll(List<Subscription> entities) async {
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
  Future<void> deleteAll() async {
    _box.removeAll();
  }

  // ============ Transaction Support ============

  @override
  Future<T> transaction<T>(Future<T> Function(TransactionContext tx) callback) async {
    return _store.runAsync((store) async {
      final tx = ObjectBoxTransactionContext(store);
      return callback(tx);
    }) as Future<T>;
  }

  // ============ Subscription-specific Queries ============

  Future<List<Subscription>> findActive() async {
    final query = _box.query(Subscription_.isActive.equals(true)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<Subscription>> findInactive() async {
    final query = _box.query(Subscription_.isActive.equals(false)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<Subscription?> findBySourceUrl(String sourceUrl) async {
    final query =
        _box.query(Subscription_.sourceUrl.equals(sourceUrl)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<List<Subscription>> findBySourceType(String sourceType) async {
    final query =
        _box.query(Subscription_.sourceType.equals(sourceType)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<Subscription>> findNeedingPolling() async {
    final query = _box
        .query(Subscription_.isActive.equals(true))
        .order(Subscription_.lastCheckedAt)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<Subscription?> findByName(String name) async {
    final query = _box.query(Subscription_.name.equals(name)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }
}
