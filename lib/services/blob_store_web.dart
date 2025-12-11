/// # IndexedDBBlobStore
///
/// Web-specific implementation using browser IndexedDB via idb_shim.
/// Provides persistent client-side storage for web applications.
///
/// Stores blobs in IndexedDB database:
/// - Database name: 'blob_store'
/// - Object store: 'blobs'
/// - Keys: blob id (string)
/// - Values: Uint8List stored as base64 string

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:idb_shim/idb_browser.dart';
import 'blob_store.dart';

/// IndexedDB-based blob store for web platforms.
class IndexedDBBlobStore extends BlobStore {
  static const String _dbName = 'blob_store';
  static const int _dbVersion = 1;
  static const String _storeName = 'blobs';
  static const String _metaStoreName = 'metadata';

  Database? _db;
  final Map<String, int> _sizeCache = {};

  @override
  Future<void> initialize() async {
    if (_db != null) return;

    final factory = getIdbFactory();
    if (factory == null) {
      throw Exception('IndexedDB not supported in this environment');
    }

    _db = await factory.open(
      _dbName,
      version: _dbVersion,
      onUpgradeNeeded: (VersionChangeEvent event) {
        final db = event.database;

        // Create blobs store
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }

        // Create metadata store for size tracking
        if (!db.objectStoreNames.contains(_metaStoreName)) {
          db.createObjectStore(_metaStoreName);
        }
      },
    );

    // Load metadata cache
    await _loadMetadataCache();
  }

  /// Load all metadata into memory cache for fast contains/size checks
  Future<void> _loadMetadataCache() async {
    if (_db == null) return;

    final txn = _db!.transaction(_metaStoreName, idbModeReadOnly);
    final store = txn.objectStore(_metaStoreName);

    final cursor = store.openCursor(autoAdvance: true);
    await for (final entry in cursor) {
      final id = entry.key as String;
      final size = entry.value as int;
      _sizeCache[id] = size;
    }
  }

  @override
  Future<void> save(String id, Uint8List bytes) async {
    if (_db == null) await initialize();

    // Store blob as base64 string (IndexedDB handles strings well)
    final base64Data = base64Encode(bytes);

    final txn =
        _db!.transactionList([_storeName, _metaStoreName], idbModeReadWrite);

    // Save blob
    final blobStore = txn.objectStore(_storeName);
    await blobStore.put(base64Data, id);

    // Save metadata
    final metaStore = txn.objectStore(_metaStoreName);
    await metaStore.put(bytes.length, id);

    await txn.completed;

    // Update cache
    _sizeCache[id] = bytes.length;
  }

  @override
  Future<Uint8List?> load(String id) async {
    if (_db == null) await initialize();

    final txn = _db!.transaction(_storeName, idbModeReadOnly);
    final store = txn.objectStore(_storeName);

    final result = await store.getObject(id);
    if (result == null) return null;

    // Decode from base64
    final base64Data = result as String;
    return Uint8List.fromList(base64Decode(base64Data));
  }

  @override
  Future<bool> delete(String id) async {
    if (_db == null) await initialize();

    if (!_sizeCache.containsKey(id)) return false;

    final txn =
        _db!.transactionList([_storeName, _metaStoreName], idbModeReadWrite);

    // Delete blob
    final blobStore = txn.objectStore(_storeName);
    await blobStore.delete(id);

    // Delete metadata
    final metaStore = txn.objectStore(_metaStoreName);
    await metaStore.delete(id);

    await txn.completed;

    // Update cache
    _sizeCache.remove(id);

    return true;
  }

  @override
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024}) async* {
    final bytes = await load(id);
    if (bytes == null) return;

    // Yield in chunks
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, bytes.length);
      yield bytes.sublist(i, end);
    }
  }

  @override
  bool contains(String id) {
    return _sizeCache.containsKey(id);
  }

  @override
  int size(String id) {
    return _sizeCache[id] ?? -1;
  }

  @override
  void dispose() {
    _db?.close();
    _db = null;
    _sizeCache.clear();
  }
}
