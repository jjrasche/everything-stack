/// # MediaItemIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for MediaItem entities.
/// Handles CRUD operations and persisted HNSW semantic search for web platform.
///
/// ## HNSW Persistence Strategy
/// - In-memory HNSW index using local_hnsw package
/// - Index serialized and stored in _hnsw_index object store (media_items_index key)
/// - On init: Deserialize from IndexedDB (fast load)
/// - On save/delete: Update in-memory index + mark dirty
/// - On close or every N operations: Serialize back to IndexedDB
/// - Fallback: If index missing/corrupt, rebuild from embeddings
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final adapter = MediaItemIndexedDBAdapter(db);
/// await adapter.initialize(); // Load HNSW index
///
/// // Use semantic search
/// final results = await adapter.semanticSearch(queryVector);
///
/// // Clean up on app close
/// await adapter.close(); // Persists HNSW index
/// ```

import 'dart:convert';
import 'dart:typed_data';
import 'package:idb_shim/idb.dart';
import 'package:local_hnsw/local_hnsw.dart';
import 'package:local_hnsw/local_hnsw.item.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';
import '../../tools/media/entities/media_item.dart';

class MediaItemIndexedDBAdapter extends BaseIndexedDBAdapter<MediaItem> {
  static const int _serializeThreshold = 10; // Serialize every N operations
  static const int _embeddingDimensions = 384; // Embedding vector size

  LocalHNSW<String>? _hnswIndex; // In-memory HNSW index (String = UUID)
  bool _indexDirty = false; // Track if index needs serialization
  int _operationsSinceLastSerialize = 0; // Counter for periodic serialization
  bool _isInitialized = false;

  MediaItemIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.mediaItems;

  @override
  MediaItem fromJson(Map<String, dynamic> json) => MediaItem.fromJson(json);

  // ============ Initialization ============

  /// Initialize the adapter and load HNSW index.
  ///
  /// Call this after creating the adapter:
  /// ```dart
  /// final adapter = MediaItemIndexedDBAdapter(db);
  /// await adapter.initialize();
  /// ```
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Try to deserialize index from IndexedDB
      await _deserializeIndex();
    } catch (e) {
      print('Failed to deserialize HNSW index: $e');
      print('Will rebuild on first semantic search');
    }

    _isInitialized = true;
  }

  /// Deserialize HNSW index from _hnsw_index object store.
  Future<void> _deserializeIndex() async {
    final txn = db.transaction(ObjectStores.hnswIndex, idbModeReadOnly);
    final store = txn.objectStore(ObjectStores.hnswIndex);

    final value = await store.getObject('media_items_index');
    if (value == null) {
      print('No persisted HNSW index found - will build on demand');
      return;
    }

    final data = value as Map<String, dynamic>;
    final bytes = data['bytes'] as Uint8List;
    final entityCount = data['entityCount'] as int;
    final version = data['version'] as int;

    print('Deserializing MediaItem HNSW index: v$version, $entityCount entities');

    // Deserialize HNSW index from JSON
    final jsonStr = utf8.decode(bytes);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    _hnswIndex = LocalHNSW.load(
      json: json,
      dim: _embeddingDimensions,
      decodeItem: (itemJson) => itemJson, // itemJson is already String (UUID)
    );

    // Validate count matches
    final currentCount = await count();
    if (currentCount != entityCount) {
      print('Warning: Entity count mismatch ($currentCount vs $entityCount)');
      print('Index may be stale - will rebuild if needed');
    }
  }

  /// Serialize HNSW index to _hnsw_index object store.
  Future<void> _serializeIndex() async {
    if (_hnswIndex == null || !_indexDirty) return;

    print('Serializing MediaItem HNSW index...');

    // Serialize to JSON then encode to bytes
    final json = _hnswIndex!.save(encodeItem: (item) => item); // item is UUID string
    final jsonStr = jsonEncode(json);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    final entityCount = await count();

    final data = {
      'key': 'media_items_index',
      'bytes': bytes,
      'version': 1, // Increment on schema changes
      'entityCount': entityCount,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
    };

    final txn = db.transaction(ObjectStores.hnswIndex, idbModeReadWrite);
    final store = txn.objectStore(ObjectStores.hnswIndex);
    await store.put(data);

    _indexDirty = false;
    _operationsSinceLastSerialize = 0;

    print('MediaItem HNSW index serialized: $entityCount entities');
  }

  // ============ Semantic Search ============

  @override
  Future<List<MediaItem>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Ensure index is built
    if (_hnswIndex == null) {
      print('HNSW index not loaded - rebuilding from embeddings');
      await rebuildIndex();
    }

    if (_hnswIndex == null) {
      print('No embeddings found - returning empty results');
      return [];
    }

    // Search using HNSW index (2 positional args)
    final searchResult = _hnswIndex!.search(queryVector, limit);

    // Filter by minimum similarity and fetch entities
    final items = <MediaItem>[];
    for (final resultItem in searchResult.items) {
      // local_hnsw returns distance (lower = more similar)
      // Convert to similarity: similarity = 1 - distance for cosine
      final similarity = 1.0 - resultItem.distance;
      if (similarity >= minSimilarity) {
        // resultItem.item is the UUID string
        final item = await findById(resultItem.item);
        if (item != null) {
          items.add(item);
        }
      }
    }

    return items;
  }

  @override
  int get indexSize {
    // LocalHNSW doesn't expose size property - count nodes by iterating
    // For now, return 0 if null, otherwise we'd need to track count manually
    return _hnswIndex == null ? 0 : -1; // -1 indicates "unknown but exists"
  }

  @override
  Future<void> rebuildIndex([
    Future<List<double>?> Function(MediaItem entity)? generateEmbedding,
  ]) async {
    print('Rebuilding MediaItem HNSW index from all embeddings...');

    // Create new HNSW index (cosine distance)
    _hnswIndex = LocalHNSW<String>(
      dim: _embeddingDimensions,
      metric: LocalHnswMetric.cosine,
    );

    // Load all media items with embeddings
    final items = await findAll();
    int addedCount = 0;

    for (final item in items) {
      if (item.embedding != null && item.embedding!.isNotEmpty) {
        _hnswIndex!.add(
          LocalHnswItem<String>(
            item: item.uuid, // Use UUID as identifier
            vector: item.embedding!,
          ),
        );
        addedCount++;
      }
    }

    print('MediaItem HNSW index rebuilt: $addedCount entities');

    // Mark dirty and serialize
    _indexDirty = true;
    await _serializeIndex();
  }

  // ============ CRUD with Index Updates ============

  @override
  Future<MediaItem> save(MediaItem entity, {bool touch = true}) async {
    // Save entity
    final saved = await super.save(entity, touch: touch);

    // Update HNSW index if entity has embedding
    if (saved.embedding != null && saved.embedding!.isNotEmpty) {
      // Initialize index if not already created
      if (_hnswIndex == null) {
        _hnswIndex = LocalHNSW<String>(
          dim: _embeddingDimensions,
          metric: LocalHnswMetric.cosine,
        );
      }

      _hnswIndex!.add(
        LocalHnswItem<String>(
          item: saved.uuid,
          vector: saved.embedding!,
        ),
      );

      _markDirtyAndCheckSerialize();
    }

    return saved;
  }

  @override
  Future<List<MediaItem>> saveAll(List<MediaItem> entities) async {
    // Save entities
    final saved = await super.saveAll(entities);

    // Update HNSW index for all entities with embeddings
    bool hasEmbeddings =
        saved.any((e) => e.embedding != null && e.embedding!.isNotEmpty);
    if (hasEmbeddings) {
      // Initialize index if not already created
      if (_hnswIndex == null) {
        _hnswIndex = LocalHNSW<String>(
          dim: _embeddingDimensions,
          metric: LocalHnswMetric.cosine,
        );
      }

      for (final entity in saved) {
        if (entity.embedding != null && entity.embedding!.isNotEmpty) {
          _hnswIndex!.add(
            LocalHnswItem<String>(
              item: entity.uuid,
              vector: entity.embedding!,
            ),
          );
        }
      }
      _markDirtyAndCheckSerialize();
    }

    return saved;
  }

  @override
  Future<bool> delete(String uuid) async {
    // Delete from HNSW index first
    if (_hnswIndex != null) {
      // delete() takes the value type (String = UUID), not LocalHnswItem
      _hnswIndex!.delete(uuid);
      _markDirtyAndCheckSerialize();
    }

    // Delete entity
    return await super.delete(uuid);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    // Delete from HNSW index
    if (_hnswIndex != null) {
      final entities = await Future.wait(uuids.map((uuid) => findById(uuid)));
      for (final entity in entities) {
        if (entity != null) {
          // delete() takes the value type (String = UUID)
          _hnswIndex!.delete(entity.uuid);
        }
      }
      _markDirtyAndCheckSerialize();
    }

    // Delete entities
    await super.deleteAll(uuids);
  }

  /// Mark index as dirty and serialize if threshold reached.
  void _markDirtyAndCheckSerialize() {
    _indexDirty = true;
    _operationsSinceLastSerialize++;

    // Serialize every N operations (fire-and-forget)
    if (_operationsSinceLastSerialize >= _serializeThreshold) {
      _serializeIndex(); // Async but don't await
    }
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Serialize index before closing
    if (_indexDirty) {
      await _serializeIndex();
    }

    await super.close();
  }
}
