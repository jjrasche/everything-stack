/// # NoteObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Note entities.
/// Handles CRUD operations and native HNSW vector search.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = NoteObjectBoxAdapter(store);
/// final repo = NoteRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/note.dart';
import '../../objectbox.g.dart';

class NoteObjectBoxAdapter implements PersistenceAdapter<Note> {
  final Store _store;
  late final Box<Note> _box;

  NoteObjectBoxAdapter(this._store) {
    _box = _store.box<Note>();
  }

  // ============ CRUD ============

  @override
  Future<Note?> findById(int id) async {
    return _box.get(id);
  }

  @override
  Future<Note?> findByUuid(String uuid) async {
    final query = _box.query(Note_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Note>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<Note> save(Note entity) async {
    entity.touch();
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<Note>> saveAll(List<Note> entities) async {
    for (final entity in entities) {
      entity.touch();
    }
    _box.putMany(entities);
    return entities;
  }

  @override
  Future<bool> delete(int id) async {
    return _box.remove(id);
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) return false;
    return _box.remove(entity.id);
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    _box.removeMany(ids);
  }

  // ============ Queries ============

  @override
  Future<List<Note>> findUnsynced() async {
    final query = _box
        .query(Note_.dbSyncStatus.equals(SyncStatus.local.index))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  // ============ Semantic Search ============

  @override
  Future<List<Note>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // ObjectBox uses nearestNeighborsF32 for HNSW search
    // The score returned is distance (lower = more similar)
    final query = _box
        .query(Note_.embedding.nearestNeighborsF32(queryVector, limit))
        .build();

    try {
      final results = query.findWithScores();

      // Filter by minimum similarity
      // ObjectBox returns cosine distance, convert to similarity: 1 - distance
      final filtered = <Note>[];
      for (final result in results) {
        final similarity = 1.0 - result.score;
        if (similarity >= minSimilarity) {
          filtered.add(result.object);
        }
      }

      return filtered;
    } finally {
      query.close();
    }
  }

  @override
  int get indexSize {
    // Count entities that have embeddings
    final query = _box.query(Note_.embedding.notNull()).build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Note entity) generateEmbedding,
  ) async {
    // For ObjectBox, the HNSW index is automatic.
    // We just need to ensure all entities have embeddings.
    final notes = await findAll();

    for (final note in notes) {
      if (note.embedding == null) {
        final embedding = await generateEmbedding(note);
        if (embedding != null) {
          note.embedding = embedding;
          await save(note);
        }
      }
    }
  }

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle is managed externally
    // Don't close the store here - it may be shared
  }
}
