/// HNSW Index Store - Native Platform Implementation
///
/// File-based persistence for Android, iOS, macOS, Windows, Linux.
/// Uses dart:io for file operations.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'hnsw_index.dart';
import 'hnsw_index_store.dart';

/// File-based HNSW index store for native platforms
class HnswIndexStoreNative implements HnswIndexStore {
  final String basePath;

  HnswIndexStoreNative({required this.basePath});

  String get _indexPath => '$basePath/hnsw_index.bin';
  String get _metadataPath => '$basePath/hnsw_index.meta';

  @override
  Future<void> saveIndex(HnswIndex index) async {
    final stopwatch = Stopwatch()..start();

    try {
      final bytes = index.toBytes();

      // Ensure directory exists
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File(_indexPath);
      await file.writeAsBytes(bytes, flush: true);

      final metaFile = File(_metadataPath);
      final meta = '${DateTime.now().toIso8601String()}\n${bytes.length}\n${index.size}';
      await metaFile.writeAsString(meta);

      stopwatch.stop();
      debugPrint('✅ [HnswIndexStore] Saved ${index.size} vectors (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB) in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ [HnswIndexStore] Failed to save index: $e');
      rethrow;
    }
  }

  @override
  Future<IndexLoadResult> loadIndex() async {
    final stopwatch = Stopwatch()..start();

    try {
      final file = File(_indexPath);
      if (!await file.exists()) {
        debugPrint('📭 [HnswIndexStore] No cached index at $_indexPath');
        return IndexLoadResult.notFound();
      }

      final metadata = await getMetadata();

      final bytes = await file.readAsBytes();

      // Deserialize
      final index = HnswIndex.fromBytes(bytes);

      stopwatch.stop();
      debugPrint('✅ [HnswIndexStore] Loaded ${index.size} vectors (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB) in ${stopwatch.elapsedMilliseconds}ms');

      return IndexLoadResult.success(index, metadata);
    } catch (e) {
      debugPrint('❌ [HnswIndexStore] Failed to load index: $e');
      // If load fails, clear corrupted cache
      await clear();
      return IndexLoadResult.failed(e.toString());
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = File(_indexPath);
      if (await file.exists()) {
        await file.delete();
      }

      final metaFile = File(_metadataPath);
      if (await metaFile.exists()) {
        await metaFile.delete();
      }

      debugPrint('🗑️ [HnswIndexStore] Cleared cached index');
    } catch (e) {
      debugPrint('⚠️ [HnswIndexStore] Failed to clear index: $e');
    }
  }

  @override
  Future<HnswIndexMetadata?> getMetadata() async {
    try {
      final metaFile = File(_metadataPath);
      if (!await metaFile.exists()) return null;

      final content = await metaFile.readAsString();
      final lines = content.split('\n');
      if (lines.length < 3) return null;

      return HnswIndexMetadata(
        savedAt: DateTime.parse(lines[0]),
        sizeBytes: int.parse(lines[1]),
        vectorCount: int.parse(lines[2]),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Factory function for creating platform-appropriate store
HnswIndexStore createHnswIndexStore(String basePath) {
  return HnswIndexStoreNative(basePath: basePath);
}
