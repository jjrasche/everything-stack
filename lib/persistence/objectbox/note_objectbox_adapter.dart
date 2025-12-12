/// # NoteObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Note entities.
/// Uses NoteOB wrapper (Anti-Corruption Layer) to keep domain entities clean.
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
import 'wrappers/note_ob.dart';
import '../../objectbox.g.dart';

class NoteObjectBoxAdapter extends BaseObjectBoxAdapter<Note, NoteOB> {
  NoteObjectBoxAdapter(Store store) : super(store);

  // ============ Abstract Method Implementations ============

  @override
  NoteOB toOB(Note entity) => NoteOB.fromNote(entity);

  @override
  Note fromOB(NoteOB ob) => ob.toNote();

  @override
  Condition<NoteOB> uuidEqualsCondition(String uuid) =>
      NoteOB_.uuid.equals(uuid);

  @override
  Condition<NoteOB> syncStatusLocalCondition() =>
      NoteOB_.dbSyncStatus.equals(SyncStatus.local.index);

  // ============ Entity-Specific Methods (Semantic Search) ============

  @override
  Future<List<Note>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // ObjectBox HNSW vector search on wrapper entity
    final query = box
        .query(NoteOB_.embedding.nearestNeighborsF32(queryVector, limit))
        .build();

    try {
      final results = query.findWithScores();

      // Filter by minimum similarity (1 - distance)
      final filtered = <Note>[];
      for (final result in results) {
        final similarity = 1.0 - result.score;
        if (similarity >= minSimilarity) {
          filtered.add(fromOB(result.object));
        }
      }

      return filtered;
    } finally {
      query.close();
    }
  }

  @override
  int get indexSize {
    final query = box.query(NoteOB_.embedding.notNull()).build();
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
