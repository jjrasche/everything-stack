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
import 'base_objectbox_adapter.dart';
import '../../core/base_entity.dart';
import '../../domain/note.dart';
import '../../objectbox.g.dart';

class NoteObjectBoxAdapter extends BaseObjectBoxAdapter<Note> {
  NoteObjectBoxAdapter(Store store) : super(store);

  // ============ Entity-Specific Query Conditions ============

  @override
  Condition<Note> uuidEqualsCondition(String uuid) => Note_.uuid.equals(uuid);

  @override
  Condition<Note> syncStatusLocalCondition() =>
      Note_.dbSyncStatus.equals(SyncStatus.local.index);

  // ============ Semantic Search (Override for Embeddings) ============

  @override
  Future<List<Note>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // ObjectBox uses nearestNeighborsF32 for HNSW search
    // The score returned is distance (lower = more similar)
    final query = box
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
    final query = box.query(Note_.embedding.notNull()).build();
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
}
