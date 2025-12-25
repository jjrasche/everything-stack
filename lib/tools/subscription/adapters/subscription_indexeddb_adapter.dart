/// # SubscriptionIndexedDBAdapter
///
/// IndexedDB implementation of PersistenceAdapter for Subscription entities.
/// Used on web platform for client-side persistence.

import 'package:idb/idb.dart' as idb;
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/subscription.dart';

class SubscriptionIndexedDBAdapter implements PersistenceAdapter<Subscription> {
  late final idb.Database _db;
  final String _storeName = 'subscriptions';

  SubscriptionIndexedDBAdapter._(this._db);

  static Future<SubscriptionIndexedDBAdapter> create() async {
    final idbFactory = idb.idbFactory;
    final db = await idbFactory.open('everything_stack',
        version: 1, onUpgradeNeeded: (idb.VersionChangeEvent event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('subscriptions')) {
        final store = db.createObjectStore('subscriptions', keyPath: 'id');
        store.createIndex('uuid', 'uuid');
        store.createIndex('sourceUrl', 'sourceUrl');
        store.createIndex('sourceType', 'sourceType');
        store.createIndex('isActive', 'isActive');
      }
    });

    return SubscriptionIndexedDBAdapter._(db);
  }

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<Subscription?> findById(int id) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final result = await store.getObject(id);
    return result != null ? Subscription.fromJson(result) : null;
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
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('uuid');
    final results = await index.getAll(uuid);

    if (results.isEmpty) return null;
    return Subscription.fromJson(results.first);
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
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final results = await store.getAll();
    return results.map((item) => Subscription.fromJson(item)).toList();
  }

  @override
  Future<Subscription> save(Subscription entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }

    final transaction = _db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.put(entity.toJson());
    return entity;
  }

  @override
  Future<List<Subscription>> saveAll(List<Subscription> entities) async {
    for (final entity in entities) {
      entity.touch();
    }

    final transaction = _db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    for (final entity in entities) {
      await store.put(entity.toJson());
    }
    return entities;
  }

  @override
  Future<bool> delete(int id) async {
    final transaction = _db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    final exists = await store.getObject(id) != null;
    if (exists) {
      await store.delete(id);
    }
    return exists;
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity != null) {
      return delete(entity.id);
    }
    return false;
  }

  @override
  Future<void> deleteAll() async {
    final transaction = _db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.clear();
  }

  // ============ Transaction Support ============

  @override
  Future<T> transaction<T>(Future<T> Function(TransactionContext tx) callback) async {
    throw UnimplementedError('IndexedDB transactions not yet implemented');
  }

  // ============ Subscription-specific Queries ============

  Future<List<Subscription>> findActive() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('isActive');
    final results = await index.getAll(true);
    return results.map((item) => Subscription.fromJson(item)).toList();
  }

  Future<List<Subscription>> findInactive() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('isActive');
    final results = await index.getAll(false);
    return results.map((item) => Subscription.fromJson(item)).toList();
  }

  Future<Subscription?> findBySourceUrl(String sourceUrl) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('sourceUrl');
    final results = await index.getAll(sourceUrl);
    return results.isEmpty ? null : Subscription.fromJson(results.first);
  }

  Future<List<Subscription>> findBySourceType(String sourceType) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('sourceType');
    final results = await index.getAll(sourceType);
    return results.map((item) => Subscription.fromJson(item)).toList();
  }

  Future<List<Subscription>> findNeedingPolling() async {
    final active = await findActive();
    return active;
  }

  Future<Subscription?> findByName(String name) async {
    final all = await findAll();
    try {
      return all.firstWhere((s) => s.name == name);
    } catch (e) {
      return null;
    }
  }
}
