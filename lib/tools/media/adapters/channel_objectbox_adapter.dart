/// # ChannelObjectBoxAdapter
///
/// ObjectBox implementation of PersistenceAdapter for Channel entities.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = ChannelObjectBoxAdapter(store);
/// final repo = ChannelRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/channel.dart';
import '../../../objectbox.g.dart';

class ChannelObjectBoxAdapter implements PersistenceAdapter<Channel> {
  final Store _store;
  late final Box<Channel> _box;

  ChannelObjectBoxAdapter(this._store) {
    _box = _store.box<Channel>();
  }

  Box<Channel> get box => _box;

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<Channel?> findById(int id) async {
    return _box.get(id);
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
    final query = _box.query(Channel_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
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
    return _box.getAll();
  }

  @override
  Future<Channel> save(Channel entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Channel>> saveAll(List<Channel> entities) async {
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

  // ============ Channel-specific Queries ============

  Future<List<Channel>> findSubscribed() async {
    final query = _box.query(Channel_.isSubscribed.equals(true)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<Channel>> findUnsubscribed() async {
    final query = _box.query(Channel_.isSubscribed.equals(false)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<Channel?> findByYoutubeChannelId(String youtubeChannelId) async {
    final query =
        _box.query(Channel_.youtubeChannelId.equals(youtubeChannelId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<Channel?> findByUrl(String youtubeUrl) async {
    final query = _box.query(Channel_.youtubeUrl.equals(youtubeUrl)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<List<Channel>> findNeedingCheck() async {
    final query = _box
        .query(Channel_.shouldCheckForNew.equals(true))
        .order(Channel_.lastCheckedAt)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}
