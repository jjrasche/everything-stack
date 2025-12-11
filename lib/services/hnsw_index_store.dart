/// # HnswIndexStore
///
/// ## What it does
/// Persists the HNSW index to Isar for restoration across app restarts.
/// Stores the serialized index bytes in a dedicated collection.
///
/// ## What it enables
/// - Index survives app restarts without full rebuild
/// - Fast startup (deserialize vs regenerate all embeddings)
/// - Single source of truth for index state
///
/// ## Usage
/// ```dart
/// final store = HnswIndexStore(isar);
///
/// // Save index after changes
/// await store.save(hnswIndex);
///
/// // Restore on startup
/// final restored = await store.load();
/// if (restored != null) {
///   hnswIndex = restored;
/// } else {
///   // Index missing/corrupt - rebuild from entities
///   await repository.rebuildIndex();
/// }
/// ```
///
/// ## Storage format
/// Single row with key 'main' stores serialized index bytes.
/// Only one index exists (Option A: global index for all types).

import 'dart:typed_data';
import 'package:isar/isar.dart';
import 'hnsw_index.dart';
import 'embedding_service.dart';

part 'hnsw_index_store.g.dart';

/// Isar collection for storing serialized HNSW index
@Collection()
class HnswIndexData {
  Id id = Isar.autoIncrement;

  /// Identifier for this index (allows multiple indices if needed later)
  @Index(unique: true)
  String key;

  /// Serialized HNSW index bytes
  List<byte> data;

  /// When the index was last updated
  DateTime updatedAt;

  /// Number of vectors in the index (for quick stats without deserializing)
  int vectorCount;

  HnswIndexData({
    required this.key,
    required this.data,
    required this.updatedAt,
    required this.vectorCount,
  });
}

/// Service for persisting and restoring HNSW index
class HnswIndexStore {
  final Isar isar;

  /// Key for the main (global) index
  static const String mainIndexKey = 'main';

  HnswIndexStore(this.isar);

  /// Save the current index state to Isar
  Future<void> save(HnswIndex index, {String key = mainIndexKey}) async {
    final bytes = index.toBytes();

    await isar.writeTxn(() async {
      // Find existing or create new
      final existing =
          await isar.hnswIndexDatas.where().keyEqualTo(key).findFirst();

      final data = HnswIndexData(
        key: key,
        data: bytes.toList(),
        updatedAt: DateTime.now(),
        vectorCount: index.size,
      );

      if (existing != null) {
        data.id = existing.id;
      }

      await isar.hnswIndexDatas.put(data);
    });
  }

  /// Load index from Isar
  ///
  /// Returns null if no stored index exists or if deserialization fails.
  Future<HnswIndex?> load({String key = mainIndexKey}) async {
    try {
      final data =
          await isar.hnswIndexDatas.where().keyEqualTo(key).findFirst();

      if (data == null) return null;

      return HnswIndex.fromBytes(Uint8List.fromList(data.data));
    } catch (e) {
      // Index corrupt or incompatible - return null to trigger rebuild
      return null;
    }
  }

  /// Check if a stored index exists
  Future<bool> exists({String key = mainIndexKey}) async {
    final count = await isar.hnswIndexDatas.where().keyEqualTo(key).count();
    return count > 0;
  }

  /// Get stats about stored index without loading it
  Future<Map<String, dynamic>?> getStats({String key = mainIndexKey}) async {
    final data = await isar.hnswIndexDatas.where().keyEqualTo(key).findFirst();

    if (data == null) return null;

    return {
      'vectorCount': data.vectorCount,
      'bytesSize': data.data.length,
      'updatedAt': data.updatedAt,
    };
  }

  /// Delete stored index
  Future<void> delete({String key = mainIndexKey}) async {
    await isar.writeTxn(() async {
      await isar.hnswIndexDatas.where().keyEqualTo(key).deleteAll();
    });
  }

  /// Create a new empty index with default parameters
  static HnswIndex createEmpty() {
    return HnswIndex(
      dimensions: EmbeddingService.dimension,
    );
  }
}
