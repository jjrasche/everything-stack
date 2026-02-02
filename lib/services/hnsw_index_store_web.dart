/// HNSW Index Store - Web Platform Implementation
///
/// Uses IndexedDB for storing the serialized HNSW index blob.
/// This provides fast startup on web by caching the pre-built index.
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'hnsw_index.dart';
import 'hnsw_index_store.dart';

/// IndexedDB-backed HNSW index store for web
class HnswIndexStoreWeb implements HnswIndexStore {
  static const _dbName = 'hnsw_index_cache';
  static const _storeName = 'index';
  static const _indexKey = 'cached_hnsw_index';
  static const _metadataKey = 'cached_hnsw_metadata';
  static const _dbVersion = 1;

  HnswIndexStoreWeb();

  @override
  Future<void> saveIndex(HnswIndex index) async {
    final stopwatch = Stopwatch()..start();

    try {
      final bytes = index.toBytes();
      final db = await _openDatabase();

      // Store index bytes
      final transaction = db.transaction(_storeName.toJS, 'readwrite');
      final store = transaction.objectStore(_storeName);

      // Convert Uint8List to JSArrayBuffer for IndexedDB
      final jsArray = bytes.toJS;
      store.put(jsArray, _indexKey.toJS);

      // Store metadata
      final metadata = {
        'savedAt': DateTime.now().toIso8601String(),
        'sizeBytes': bytes.length,
        'vectorCount': index.size,
      };
      store.put(metadata.jsify(), _metadataKey.toJS);

      await transaction.completed;
      db.close();

      stopwatch.stop();
      debugPrint('✅ [HnswIndexStore/Web] Saved ${index.size} vectors (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB) in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ [HnswIndexStore/Web] Failed to save index: $e');
      rethrow;
    }
  }

  @override
  Future<IndexLoadResult> loadIndex() async {
    final stopwatch = Stopwatch()..start();

    try {
      final db = await _openDatabase();
      final transaction = db.transaction(_storeName.toJS, 'readonly');
      final store = transaction.objectStore(_storeName);

      // Get index bytes
      final request = store.get(_indexKey.toJS);
      await request.completed;

      if (request.result == null) {
        db.close();
        debugPrint('📭 [HnswIndexStore/Web] No cached index in IndexedDB');
        return IndexLoadResult.notFound();
      }

      // Convert JSArrayBuffer back to Uint8List
      final jsArrayBuffer = request.result as JSArrayBuffer;
      final bytes = jsArrayBuffer.toDart.asUint8List();

      // Get metadata
      final metadataRequest = store.get(_metadataKey.toJS);
      await metadataRequest.completed;

      HnswIndexMetadata? metadata;
      if (metadataRequest.result != null) {
        final metaMap = (metadataRequest.result as JSObject).dartify() as Map;
        metadata = HnswIndexMetadata(
          savedAt: DateTime.parse(metaMap['savedAt'] as String),
          sizeBytes: metaMap['sizeBytes'] as int,
          vectorCount: metaMap['vectorCount'] as int,
        );
      }

      db.close();

      // Deserialize
      final index = HnswIndex.fromBytes(bytes);

      stopwatch.stop();
      debugPrint('✅ [HnswIndexStore/Web] Loaded ${index.size} vectors (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB) in ${stopwatch.elapsedMilliseconds}ms');

      return IndexLoadResult.success(index, metadata);
    } catch (e) {
      debugPrint('❌ [HnswIndexStore/Web] Failed to load index: $e');
      await clear();
      return IndexLoadResult.failed(e.toString());
    }
  }

  @override
  Future<void> clear() async {
    try {
      final db = await _openDatabase();
      final transaction = db.transaction(_storeName.toJS, 'readwrite');
      final store = transaction.objectStore(_storeName);

      store.delete(_indexKey.toJS);
      store.delete(_metadataKey.toJS);

      await transaction.completed;
      db.close();

      debugPrint('🗑️ [HnswIndexStore/Web] Cleared cached index');
    } catch (e) {
      debugPrint('⚠️ [HnswIndexStore/Web] Failed to clear index: $e');
    }
  }

  @override
  Future<HnswIndexMetadata?> getMetadata() async {
    try {
      final db = await _openDatabase();
      final transaction = db.transaction(_storeName.toJS, 'readonly');
      final store = transaction.objectStore(_storeName);

      final request = store.get(_metadataKey.toJS);
      await request.completed;

      db.close();

      if (request.result == null) return null;

      final metaMap = (request.result as JSObject).dartify() as Map;
      return HnswIndexMetadata(
        savedAt: DateTime.parse(metaMap['savedAt'] as String),
        sizeBytes: metaMap['sizeBytes'] as int,
        vectorCount: metaMap['vectorCount'] as int,
      );
    } catch (e) {
      return null;
    }
  }

  /// Open IndexedDB database, creating object store if needed
  Future<web.IDBDatabase> _openDatabase() async {
    final completer = Completer<web.IDBDatabase>();

    final request = web.window.indexedDB.open(_dbName, _dbVersion);

    request.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;

    request.onsuccess = ((web.Event event) {
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;

    request.onerror = ((web.Event event) {
      completer.completeError('IndexedDB open failed');
    }).toJS;

    return completer.future;
  }
}

/// Extension to wait for IDB transaction completion
extension IDBTransactionExt on web.IDBTransaction {
  Future<void> get completed {
    final completer = Completer<void>();
    oncomplete = ((web.Event e) => completer.complete()).toJS;
    onerror = ((web.Event e) => completer.completeError('Transaction failed')).toJS;
    return completer.future;
  }
}

/// Extension to wait for IDB request completion
extension IDBRequestExt on web.IDBRequest {
  Future<void> get completed {
    final completer = Completer<void>();
    onsuccess = ((web.Event e) => completer.complete()).toJS;
    onerror = ((web.Event e) => completer.completeError('Request failed')).toJS;
    return completer.future;
  }
}

/// Factory function for creating platform-appropriate store
HnswIndexStore createHnswIndexStore(String basePath) {
  return HnswIndexStoreWeb();
}
