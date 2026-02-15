/// Web stub: class name matches native adapter for conditional import compatibility.
/// Semantic search is disabled on web (ObjectBox/dart:ffi not available).
/// ChunkingService is not initialized on web (see bootstrap.dart).

import '../../core/chunk_repository.dart';
import '../../services/semantic_search/chunk.dart';

/// Web stub - named ChunkObjectBoxAdapter to match native import.
/// Never instantiated on web (semantic search disabled).
class ChunkObjectBoxAdapter implements ChunkRepository {
  /// Stub constructor that accepts Store-like parameter to match native signature.
  /// Parameter is ignored since this is never called on web.
  ChunkObjectBoxAdapter(dynamic store);

  @override
  Future<void> put(Chunk chunk) async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<void> updateEmbedding(String chunkId, List<double> embedding) async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<List<Chunk>> getAll() async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<List<Chunk>> getForEntity(String entityId) async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<Chunk?> getById(String chunkId) async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<void> removeForEntity(String entityId) async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<void> removeMany(List<String> chunkIds) async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }

  @override
  Future<int> removeDuplicates() async {
    throw UnsupportedError('Chunk persistence not supported on web');
  }
}
