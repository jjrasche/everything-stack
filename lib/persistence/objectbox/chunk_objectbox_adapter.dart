/// # ChunkObjectBoxAdapter
///
/// ObjectBox implementation of ChunkRepository.
/// Converts between domain Chunk and ChunkOB wrapper.

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
}
