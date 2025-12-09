/// # NoteRepository
///
/// ## What it does
/// Repository for Note entities. Extends EntityRepository with
/// Note-specific queries.
///
/// ## Usage
/// ```dart
/// final repo = NoteRepository(isar, hnswIndex: index);
///
/// // CRUD
/// final id = await repo.save(note);
/// final note = await repo.findById(id);
/// await repo.delete(id);
///
/// // Semantic search
/// final results = await repo.semanticSearch('project timeline');
///
/// // Note-specific queries
/// final pinned = await repo.findPinned();
/// final byTag = await repo.findByTag('work');
/// final accessible = await repo.findAccessibleBy(userId);
/// ```

import 'package:isar/isar.dart';
import '../core/entity_repository.dart';
import '../services/hnsw_index.dart';
import '../services/embedding_service.dart';
import 'note.dart';

class NoteRepository extends EntityRepository<Note> {
  NoteRepository(
    super.isar, {
    super.hnswIndex,
    super.embeddingService,
  });

  @override
  IsarCollection<Note> get collection => isar.notes;

  /// Find note by UUID using indexed field - O(1) lookup.
  /// Overrides base implementation to leverage the @Index(unique: true)
  /// override of uuid field in Note class.
  @override
  Future<Note?> findByUuid(String uuid) async {
    return collection.where().uuidEqualTo(uuid).findFirst();
  }

  // ============ Note-specific queries ============

  /// Find all pinned notes (sorted by updatedAt descending)
  Future<List<Note>> findPinned() async {
    return collection
        .filter()
        .isPinnedEqualTo(true)
        .isArchivedEqualTo(false)
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// Find all archived notes
  Future<List<Note>> findArchived() async {
    return collection
        .filter()
        .isArchivedEqualTo(true)
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// Find notes by tag
  Future<List<Note>> findByTag(String tag) async {
    return collection
        .filter()
        .tagsElementEqualTo(tag)
        .isArchivedEqualTo(false)
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// Find all non-archived notes (default view)
  Future<List<Note>> findActive() async {
    return collection
        .filter()
        .isArchivedEqualTo(false)
        .sortByIsPinnedDesc()
        .thenByUpdatedAtDesc()
        .findAll();
  }

  /// Find notes accessible by user (owned by or shared with)
  Future<List<Note>> findAccessibleBy(String userId) async {
    // Get owned notes
    final owned = await collection
        .filter()
        .ownerIdEqualTo(userId)
        .isArchivedEqualTo(false)
        .findAll();

    // Get shared notes
    final shared = await collection
        .filter()
        .sharedWithElementEqualTo(userId)
        .isArchivedEqualTo(false)
        .findAll();

    // Combine and sort
    final all = {...owned, ...shared}.toList();
    all.sort((a, b) {
      // Pinned first
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      // Then by updatedAt
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return all;
  }

  /// Find notes owned by user
  Future<List<Note>> findOwnedBy(String userId) async {
    return collection
        .filter()
        .ownerIdEqualTo(userId)
        .isArchivedEqualTo(false)
        .sortByIsPinnedDesc()
        .thenByUpdatedAtDesc()
        .findAll();
  }

  /// Get all unique tags used in notes
  Future<List<String>> getAllTags() async {
    final notes = await collection.where().findAll();
    final tags = <String>{};
    for (final note in notes) {
      tags.addAll(note.tags);
    }
    return tags.toList()..sort();
  }
}
