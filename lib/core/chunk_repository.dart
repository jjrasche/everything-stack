/// # ChunkRepository
///
/// Abstract interface for chunk persistence operations.
/// Implemented by platform-specific adapters (ObjectBox for native, IndexedDB for web).
///
/// ChunkingService depends on this interface, not on specific persistence implementations.
/// This allows web builds to compile without ObjectBox/dart:ffi.

import '../services/semantic_search/chunk.dart';

abstract class ChunkRepository {
  /// Save a chunk to persistent storage.
  Future<void> put(Chunk chunk);

  /// Get all chunks from storage.
  Future<List<Chunk>> getAll();

  /// Get all chunks for a specific entity.
  Future<List<Chunk>> getForEntity(String entityId);

  /// Get a specific chunk by its ID.
  Future<Chunk?> getById(String chunkId);

  /// Remove all chunks for an entity.
  Future<void> removeForEntity(String entityId);

  /// Remove specific chunks by their IDs.
  Future<void> removeMany(List<String> chunkIds);
}
