/// # NoteRepository
///
/// ## What it does
/// Repository for Note entities. Extends EntityRepository with
/// Note-specific queries.
///
/// ## Usage - Production
/// ```dart
/// final adapter = NoteObjectBoxAdapter(store);
/// final repo = NoteRepository.production(
///   adapter: adapter,
/// );
/// ```
///
/// ## Usage - Testing
/// ```dart
/// final repo = NoteRepository(
///   adapter: adapter,
///   embeddingService: MockEmbeddingService(),
///   chunkingService: chunkingService,
/// );
/// ```

import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../core/persistence/transaction_manager.dart';
import '../core/entity_version.dart';
import '../core/version_repository.dart';
import '../core/edge_repository.dart';
import '../services/embedding_service.dart';
import '../services/chunking_service.dart';
import '../services/embedding_queue_service.dart';
import '../bootstrap.dart' show embeddingQueueService;
import 'note.dart';
import 'note_handler_factory.dart';

class NoteRepository extends EntityRepository<Note> {
  final VersionRepository? _versionRepo;
  EdgeRepository? _edgeRepo;
  final EmbeddingQueueService? _embeddingQueueService;

  /// Full constructor for testing and infrastructure setup.
  /// Requires explicit service injection.
  ///
  /// Services are wired into handlers via NoteHandlerFactory.
  /// Handler factory determines which patterns are integrated.
  ///
  /// If edgeRepository is provided, cascade delete for edges is automatically
  /// integrated via EdgeCascadeDeleteHandler in the handler factory.
  NoteRepository({
    required PersistenceAdapter<Note> adapter,
    EmbeddingService? embeddingService,
    ChunkingService? chunkingService,
    VersionRepository? versionRepo,
    TransactionManager? transactionManager,
    EdgeRepository? edgeRepository,
    EmbeddingQueueService? embeddingQueueService,
  })  : _versionRepo = versionRepo,
        _edgeRepo = edgeRepository,
        _embeddingQueueService = embeddingQueueService,
        super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
          chunkingService: chunkingService,
          versionRepository: versionRepo,
          transactionManager: transactionManager,
          handlers: NoteHandlerFactory(
            embeddingService: embeddingService,
            chunkingService: chunkingService,
            versionRepository: versionRepo,
            adapter: adapter,
            edgeRepository: edgeRepository,
          ).createHandlers(),
        );

  /// Factory for production use - uses global singleton services.
  /// Requires EmbeddingService to be initialized globally.
  /// Uses global embeddingQueueService for background embedding generation.
  /// EdgeRepository can be provided for cascade delete support on delete.
  factory NoteRepository.production({
    required PersistenceAdapter<Note> adapter,
    ChunkingService? chunkingService,
    VersionRepository? versionRepo,
    EdgeRepository? edgeRepository,
  }) {
    return NoteRepository(
      adapter: adapter,
      embeddingService: EmbeddingService.instance,
      chunkingService: chunkingService,
      versionRepo: versionRepo,
      edgeRepository: edgeRepository,
      embeddingQueueService: embeddingQueueService, // Use global instance
    );
  }

  /// Set EdgeRepository after construction (avoids circular dependency).
  /// NOTE: This does NOT update the handlers if they were already created!
  /// Prefer passing edgeRepository in the constructor instead.
  ///
  /// This method is deprecated and kept for backward compatibility only.
  @deprecated
  void setEdgeRepository(EdgeRepository edgeRepo) {
    _edgeRepo = edgeRepo;
  }

  // ============ Repository Overrides ============

  /// Override save to enqueue background embedding generation.
  /// Save completes immediately, embedding happens asynchronously.
  @override
  Future<int> save(Note entity) async {
    // Save entity first (returns immediately)
    final id = await super.save(entity);

    // Enqueue for background embedding if queue service is available
    if (_embeddingQueueService != null) {
      // Combine title and content for embedding
      final textToEmbed = '${entity.title}\n${entity.content}'.trim();

      if (textToEmbed.isNotEmpty) {
        await _embeddingQueueService!.enqueue(
          entityUuid: entity.uuid,
          entityType: 'Note',
          text: textToEmbed,
        );
      }
    }

    return id;
  }

  // ============ Note-specific queries ============
  // These queries load all notes and filter in memory.
  // For production scale, extend the adapter with optimized queries.

  /// Find all pinned notes (sorted by updatedAt descending)
  Future<List<Note>> findPinned() async {
    final all = await findAll();
    return all.where((n) => n.isPinned && !n.isArchived).toList()
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
    return all.where((n) => n.tags.contains(tag) && !n.isArchived).toList()
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
    final accessible = all
        .where((n) =>
            !n.isArchived &&
            (n.ownerId == userId || n.sharedWith.contains(userId)))
        .toList();
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
    final owned =
        all.where((n) => n.ownerId == userId && !n.isArchived).toList();
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
