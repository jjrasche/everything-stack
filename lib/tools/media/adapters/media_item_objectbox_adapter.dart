/// # MediaItemObjectBoxAdapter
///
/// ObjectBox implementation of PersistenceAdapter for MediaItem entities.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = MediaItemObjectBoxAdapter(store);
/// final repo = MediaItemRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/media_item.dart';
import '../../../objectbox.g.dart';

class MediaItemObjectBoxAdapter implements PersistenceAdapter<MediaItem> {
  final Store _store;
  late final Box<MediaItem> _box;

  MediaItemObjectBoxAdapter(this._store) {
    _box = _store.box<MediaItem>();
  }

  Box<MediaItem> get box => _box;

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<MediaItem?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<MediaItem> getById(int id) async {
    final entity = await findById(id);
    if (entity == null) {
      throw Exception('MediaItem not found with id: $id');
    }
    return entity;
  }

  @override
  Future<MediaItem?> findByUuid(String uuid) async {
    final query = _box.query(MediaItem_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<MediaItem> getByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) {
      throw Exception('MediaItem not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  Future<List<MediaItem>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<MediaItem> save(MediaItem entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<MediaItem>> saveAll(List<MediaItem> entities) async {
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

  // ============ Media-specific Queries ============

  Future<List<MediaItem>> findByChannel(String channelId) async {
    final query = _box.query(MediaItem_.channelId.equals(channelId)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<MediaItem>> findDownloaded() async {
    final query = _box
        .query(MediaItem_.downloadStatus.equals('completed'))
        .order(MediaItem_.downloadedAt, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<MediaItem>> findPending() async {
    final query = _box
        .query(MediaItem_.downloadStatus
            .equals('pending')
            .or(MediaItem_.downloadStatus.equals('downloading')))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<MediaItem>> findByFormat(String format) async {
    final query = _box.query(MediaItem_.format.equals(format)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<MediaItem>> findAudio() async {
    return findByFormat('mp3');
  }

  Future<List<MediaItem>> findVideo() async {
    final query = _box
        .query(MediaItem_.format.notEquals('mp3'))
        .order(MediaItem_.createdAt, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<MediaItem?> findByYoutubeId(String youtubeVideoId) async {
    final query =
        _box.query(MediaItem_.youtubeVideoId.equals(youtubeVideoId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<MediaItem?> findByUrl(String youtubeUrl) async {
    final query = _box.query(MediaItem_.youtubeUrl.equals(youtubeUrl)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<List<MediaItem>> findRecentlyDownloaded({int limit = 10}) async {
    final query = _box
        .query(MediaItem_.downloadStatus.equals('completed'))
        .order(MediaItem_.downloadedAt, flags: Order.descending)
        .build();
    try {
      return query.find().take(limit).toList();
    } finally {
      query.close();
    }
  }

  Future<int> getTotalDownloadedSize() async {
    final downloaded = await findDownloaded();
    return downloaded.fold<int>(
      0,
      (sum, item) => sum + item.fileSizeBytes,
    );
  }

  Future<Map<String, dynamic>> getStats() async {
    final all = await findAll();
    final downloadedCount =
        all.where((m) => m.downloadStatus == 'completed').length;
    final totalSize = await getTotalDownloadedSize();
    final audioCount = all.where((m) => m.format == 'mp3').length;

    return {
      'totalMediaItems': all.length,
      'downloadedCount': downloadedCount,
      'totalDownloadedSizeBytes': totalSize,
      'audioCount': audioCount,
      'videoCount': all.length - audioCount,
    };
  }
}
