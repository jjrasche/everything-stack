/// # NoteRepository
///
/// ## What it does
/// Repository for Note entities. Extends EntityRepository with
/// Note-specific queries.
///
/// ## Usage
/// ```dart
/// final adapter = NoteObjectBoxAdapter(store);
/// final repo = NoteRepository(adapter: adapter);
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

import '../core/entity_repository.dart';
import '../core/base_entity.dart';
import '../core/persistence/persistence_adapter.dart';
import '../core/entity_version.dart';
import '../core/version_repository.dart';
import '../core/edge_repository.dart';
import 'note.dart';

class NoteRepository extends EntityRepository<Note> {
  final VersionRepository? _versionRepo;
  EdgeRepository? _edgeRepo;

  NoteRepository({
    required PersistenceAdapter<Note> adapter,
    super.embeddingService,
    VersionRepository? versionRepo,
  })  : _versionRepo = versionRepo,
        super(adapter: adapter, versionRepository: versionRepo);

  /// Set EdgeRepository after construction (avoids circular dependency)
  void setEdgeRepository(EdgeRepository edgeRepo) {
    _edgeRepo = edgeRepo;
  }

  // ============ Note-specific queries ============
  // These queries load all notes and filter in memory.
  // For production scale, extend the adapter with optimized queries.

  /// Find all pinned notes (sorted by updatedAt descending)
  Future<List<Note>> findPinned() async {
    final all = await findAll();
    return all
        .where((n) => n.isPinned && !n.isArchived)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Find all archived notes
  Future<List<Note>> findArchived() async {
    final all = await findAll();
    return all.where((n) => n.isArchived).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Find notes by tag
  Future<List<Note>> findByTag(String tag) async {
    final all = await findAll();
    return all
        .where((n) => n.tags.contains(tag) && !n.isArchived)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Find all non-archived notes (default view)
  Future<List<Note>> findActive() async {
    final all = await findAll();
    final active = all.where((n) => !n.isArchived).toList();
    active.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return active;
  }

  /// Find notes accessible by user (owned by or shared with)
  Future<List<Note>> findAccessibleBy(String userId) async {
    final all = await findAll();
    final accessible = all.where((n) =>
        !n.isArchived &&
        (n.ownerId == userId || n.sharedWith.contains(userId))).toList();
    accessible.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return accessible;
  }

  /// Find notes owned by user
  Future<List<Note>> findOwnedBy(String userId) async {
    final all = await findAll();
    final owned = all.where((n) =>
        n.ownerId == userId && !n.isArchived).toList();
    owned.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return owned;
  }

  /// Get all unique tags used in notes
  Future<List<String>> getAllTags() async {
    final notes = await findAll();
    final tags = <String>{};
    for (final note in notes) {
      tags.addAll(note.tags);
    }
    return tags.toList()..sort();
  }

  // ============ Pattern Integration Methods ============

  /// Get version history for a note (Versionable pattern)
  Future<List<EntityVersion>> getHistory(String uuid) async {
    if (_versionRepo == null) {
      throw StateError('VersionRepository not provided to NoteRepository');
    }
    return _versionRepo!.getHistory(uuid);
  }

  /// Get all notes linked from this note (Edgeable pattern)
  /// Uses multi-hop traversal (depth=2) to find indirectly connected notes too.
  Future<List<Note>> getLinkedNotes(String uuid) async {
    if (_edgeRepo == null) {
      throw StateError(
          'EdgeRepository not set. Call setEdgeRepository() first');
    }

    // Use traverse for multi-hop discovery (up to 2 hops)
    final reachableUuids = await _edgeRepo!.traverse(
      startUuid: uuid,
      depth: 2,
      direction: 'outgoing',
    );

    // Load all reachable notes
    final linkedNotes = <Note>[];
    for (final targetUuid in reachableUuids.keys) {
      final note = await findByUuid(targetUuid);
      if (note != null) {
        linkedNotes.add(note);
      }
    }

    return linkedNotes;
  }
}
