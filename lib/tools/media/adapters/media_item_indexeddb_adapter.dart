/// # MediaItemIndexedDBAdapter
///
/// IndexedDB implementation of PersistenceAdapter for MediaItem entities.
/// Used on web platform for client-side persistence.
///
/// ## Usage
/// ```dart
/// final adapter = await MediaItemIndexedDBAdapter.create();
/// final repo = MediaItemRepository(adapter: adapter);
/// ```

import 'dart:html' show window;
import 'package:idb/idb.dart' as idb;
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/media_item.dart';

class MediaItemIndexedDBAdapter implements PersistenceAdapter<MediaItem> {
  late final idb.Database _db;
  final String _storeName = 'mediaItems';

  MediaItemIndexedDBAdapter._(this._db);

  static Future<MediaItemIndexedDBAdapter> create() async {
    final idbFactory = idb.idbFactory;
    final db = await idbFactory.open('everything_stack',
        version: 1, onUpgradeNeeded: (idb.VersionChangeEvent event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('mediaItems')) {
        final store = db.createObjectStore('mediaItems', keyPath: 'id');
        store.createIndex('uuid', 'uuid');
        store.createIndex('channelId', 'channelId');
        store.createIndex('downloadStatus', 'downloadStatus');
        store.createIndex('format', 'format');
        store.createIndex('youtubeVideoId', 'youtubeVideoId');
      }
    });

    return MediaItemIndexedDBAdapter._(db);
  }

  // ============ PersistenceAdapter Implementation ============

  @override
  Future<MediaItem?> findById(int id) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final result = await store.getObject(id);
    return result != null ? MediaItem.fromJson(result) : null;
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
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('uuid');
    final results = await index.getAll(uuid);

    if (results.isEmpty) return null;
    return MediaItem.fromJson(results.first);
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
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final results = await store.getAll();
    return results.map((item) => MediaItem.fromJson(item)).toList();
  }

  @override
  Future<MediaItem> save(MediaItem entity, {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }

    final transaction = _db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.put(entity.toJson());
    return entity;
  }

  @override
  Future<List<MediaItem>> saveAll(List<MediaItem> entities) async {
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

  // ============ Media-specific Queries ============

  Future<List<MediaItem>> findByChannel(String channelId) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('channelId');
    final results = await index.getAll(channelId);
    return results.map((item) => MediaItem.fromJson(item)).toList();
  }

  Future<List<MediaItem>> findDownloaded() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('downloadStatus');
    final results = await index.getAll('completed');
    return results
        .map((item) => MediaItem.fromJson(item))
        .toList()
        .reversed
        .toList();
  }

  Future<List<MediaItem>> findPending() async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('downloadStatus');
    final pending = await index.getAll('pending');
    final downloading = await index.getAll('downloading');
    return [...pending, ...downloading]
        .map((item) => MediaItem.fromJson(item))
        .toList();
  }

  Future<List<MediaItem>> findByFormat(String format) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('format');
    final results = await index.getAll(format);
    return results.map((item) => MediaItem.fromJson(item)).toList();
  }

  Future<List<MediaItem>> findAudio() async {
    return findByFormat('mp3');
  }

  Future<List<MediaItem>> findVideo() async {
    final all = await findAll();
    return all.where((m) => m.format != 'mp3').toList();
  }

  Future<MediaItem?> findByYoutubeId(String youtubeVideoId) async {
    final transaction = _db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final index = store.index('youtubeVideoId');
    final results = await index.getAll(youtubeVideoId);
    return results.isEmpty ? null : MediaItem.fromJson(results.first);
  }

  Future<MediaItem?> findByUrl(String youtubeUrl) async {
    final all = await findAll();
    try {
      return all.firstWhere((m) => m.youtubeUrl == youtubeUrl);
    } catch (e) {
      return null;
    }
  }

  Future<List<MediaItem>> findRecentlyDownloaded({int limit = 10}) async {
    final downloaded = await findDownloaded();
    return downloaded.take(limit).toList();
  }

  Future<int> getTotalDownloadedSize() async {
    final downloaded = await findDownloaded();
    return downloaded.fold<int>(0, (sum, item) => sum + item.fileSizeBytes);
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
