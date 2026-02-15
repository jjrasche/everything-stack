import 'package:objectbox/objectbox.dart';
import '../../core/chunk_repository.dart';
import '../../services/semantic_search/chunk.dart';
import '../../objectbox.g.dart';
import 'wrappers/chunk_ob.dart';

class ChunkObjectBoxAdapter implements ChunkRepository {
  final Box<ChunkOB> _box;

  ChunkObjectBoxAdapter(Store store) : _box = store.box<ChunkOB>();

  @override
  Future<void> put(Chunk chunk) async {
    final ob = ChunkOB.fromChunk(chunk);
    ob.validate();
    _box.put(ob);
  }

  @override
  Future<void> updateEmbedding(String chunkId, List<double> embedding) async {
    // Find existing chunk by chunkId
    final query = _box.query(ChunkOB_.chunkId.equals(chunkId)).build();
    try {
      final existing = query.findFirst();
      if (existing != null) {
        // Update in place (preserves ObjectBox ID)
        existing.embedding = embedding;
        _box.put(existing);
      }
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Chunk>> getAll() async {
    final obList = _box.getAll();
    return obList.map((ob) => ob.toChunk()).toList();
  }

  @override
  Future<List<Chunk>> getForEntity(String entityId) async {
    final query = _box.query(ChunkOB_.sourceEntityId.equals(entityId)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => ob.toChunk()).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<Chunk?> getById(String chunkId) async {
    final query = _box.query(ChunkOB_.chunkId.equals(chunkId)).build();
    try {
      final ob = query.findFirst();
      return ob?.toChunk();
    } finally {
      query.close();
    }
  }

  @override
  Future<void> removeForEntity(String entityId) async {
    final query = _box.query(ChunkOB_.sourceEntityId.equals(entityId)).build();
    try {
      final ids = query.findIds();
      _box.removeMany(ids);
    } finally {
      query.close();
    }
  }

  @override
  Future<void> removeMany(List<String> chunkIds) async {
    if (chunkIds.isEmpty) return;

    // Build query for all chunk IDs
    final query = _box.query(ChunkOB_.chunkId.oneOf(chunkIds)).build();
    try {
      final ids = query.findIds();
      _box.removeMany(ids);
    } finally {
      query.close();
    }
  }

  @override
  Future<int> removeDuplicates() async {
    // Get all chunks
    final all = _box.getAll();
    if (all.isEmpty) return 0;

    // Group by chunkId
    final Map<String, List<ChunkOB>> byChunkId = {};
    for (final ob in all) {
      byChunkId.putIfAbsent(ob.chunkId, () => []).add(ob);
    }

    // Find duplicates: keep only the one with embedding (or first if none have embeddings)
    final toRemove = <int>[];
    for (final entry in byChunkId.entries) {
      if (entry.value.length > 1) {
        // Sort: prefer ones WITH embeddings, then by ID (keep lower ID = original)
        entry.value.sort((a, b) {
          final aHasEmbedding = a.embedding != null && a.embedding!.isNotEmpty;
          final bHasEmbedding = b.embedding != null && b.embedding!.isNotEmpty;
          if (aHasEmbedding && !bHasEmbedding) return -1;
          if (!aHasEmbedding && bHasEmbedding) return 1;
          return a.id.compareTo(b.id);
        });
        // Keep first (best), remove rest
        for (var i = 1; i < entry.value.length; i++) {
          toRemove.add(entry.value[i].id);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      _box.removeMany(toRemove);
    }
    return toRemove.length;
  }
}
