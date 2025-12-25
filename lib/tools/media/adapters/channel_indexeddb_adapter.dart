/// # ChannelIndexedDBAdapter
///
/// IndexedDB implementation of PersistenceAdapter for Channel entities.
/// Used on web platform for client-side persistence.

import 'package:idb/idb.dart' as idb;
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/channel.dart';

class ChannelIndexedDBAdapter implements PersistenceAdapter<Channel> {
  late final idb.Database _db;
  final String _storeName = 'channels';

  ChannelIndexedDBAdapter._(this._db);

  static Future<ChannelIndexedDBAdapter> create() async {
    final idbFactory = idb.idbFactory;
    final db = await idbFactory.open('everything_stack',
        version: 1, onUpgradeNeeded: (idb.VersionChangeEvent event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('channels')) {
        final store = db.createObjectStore('channels', keyPath: 'id');
        store.createIndex('uuid', 'uuid');
        store.createIndex('youtubeChannelId', 'youtubeChannelId');
        store.createIndex('isSubscribed', 'isSubscribed');
      }
    });

    return ChannelIndexedDBAdapter._(db);
  }

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<Channel?> findById(int id) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final result = await store.getObject(id);
    return result != null ? Channel.fromJson(result) : null;
  }

  @override
  Future<Channel> getById(int id) async {
    final entity = await findById(id);
    if (entity == null) {
      throw Exception('Channel not found with id: $id');
    }
    return entity;
  }

  @override
  Future<Channel?> findByUuid(String uuid) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('uuid');
    final results = await index.getAll(uuid);

    if (results.isEmpty) return null;
    return Channel.fromJson(results.first);
  }

  @override
  Future<Channel> getByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) {
      throw Exception('Channel not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  Future<List<Channel>> findAll() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final results = await store.getAll();
    return results.map((item) => Channel.fromJson(item)).toList();
  }

  @override
  Future<Channel> save(Channel entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }

    final transaction = _db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.put(entity.toJson());
    return entity;
  }

  @override
  Future<List<Channel>> saveAll(List<Channel> entities) async {
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

  // ============ Channel-specific Queries ============

  Future<List<Channel>> findSubscribed() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('isSubscribed');
    final results = await index.getAll(true);
    return results.map((item) => Channel.fromJson(item)).toList();
  }

  Future<List<Channel>> findUnsubscribed() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('isSubscribed');
    final results = await index.getAll(false);
    return results.map((item) => Channel.fromJson(item)).toList();
  }

  Future<Channel?> findByYoutubeChannelId(String youtubeChannelId) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('youtubeChannelId');
    final results = await index.getAll(youtubeChannelId);
    return results.isEmpty ? null : Channel.fromJson(results.first);
  }

  Future<Channel?> findByUrl(String youtubeUrl) async {
    final all = await findAll();
    try {
      return all.firstWhere((c) => c.youtubeUrl == youtubeUrl);
    } catch (e) {
      return null;
    }
  }

  Future<List<Channel>> findNeedingCheck() async {
    final all = await findAll();
    return all.where((c) => c.shouldCheckForNew).toList();
  }
}
