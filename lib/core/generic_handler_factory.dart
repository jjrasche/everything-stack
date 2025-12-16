/// # GenericHandlerFactory
///
/// ## What it does
/// Creates handler chains for ANY entity type that implements patterns.
/// Eliminates per-entity factory boilerplate while keeping handler ordering explicit.
///
/// ## Design Philosophy
/// This is the template solution: one factory for all entity types.
/// Specific entities can override if they need custom handler ordering.
///
/// ## Usage
///
/// **Directly (most entities):**
/// ```dart
/// final handlers = GenericHandlerFactory<Edge>(
///   embeddingService: embeddingService,
///   chunkingService: chunkingService,
///   versionRepository: versionRepository,
///   adapter: edgeAdapter,
/// ).createHandlers();
/// ```
///
/// **Via thin wrapper (entities with custom ordering):**
/// ```dart
/// class NoteHandlerFactory extends GenericHandlerFactory<Note> {
///   @override
///   List<RepositoryPatternHandler<Note>> createHandlers() {
///     // Custom ordering if needed
///     return super.createHandlers();
///   }
/// }
/// ```

import 'base_entity.dart';
import 'persistence/persistence_adapter.dart';
import 'repository_pattern_handler.dart';
import 'handlers/embeddable_handler.dart';
import 'handlers/versionable_handler.dart';
import 'handlers/edge_cascade_delete_handler.dart';
import 'edge_repository.dart';
import '../services/embedding_service.dart';
import '../services/chunking_service.dart';

/// Generic handler factory for all entity types.
///
/// Handles conditional handler creation based on available services.
/// Handler order is fixed and optimal for most cases:
/// 1. SemanticIndexable - ephemeral, safe to fail post-save
/// 2. Embeddable - lightweight embedding generation
/// 3. Versionable - atomic, needs transaction
/// 4. EdgeCascadeDelete - cascade delete edges (if EdgeRepository provided)
///
/// Override createHandlers() if your entity needs different order.
class GenericHandlerFactory<T extends BaseEntity>
    implements RepositoryHandlerFactory<T> {
  final EmbeddingService? embeddingService;
  final ChunkingService? chunkingService;
  final dynamic versionRepository;
  final PersistenceAdapter<T> adapter;
  final EdgeRepository? edgeRepository;

  GenericHandlerFactory({
    required this.embeddingService,
    required this.chunkingService,
    required this.versionRepository,
    required this.adapter,
    this.edgeRepository,
  });

  /// Create handlers in optimal execution order.
  ///
  /// Order:
  /// 1. SemanticIndexable - delete old chunks before save (ephemeral, fail-safe)
  /// 2. Embeddable - generate embeddings before save (lightweight)
  /// 3. Versionable - record changes inside transaction (atomic)
  /// 4. EdgeCascadeDelete - cascade delete edges (if EdgeRepository provided)
  ///
  /// Handlers are only created if their service is provided.
  ///
  /// **Delete-specific handlers** (e.g., EdgeCascadeDelete) are added even if not
  /// used for saves, because they hook into the delete lifecycle via
  /// beforeDelete and beforeDeleteInTransaction.
  @override
  List<RepositoryPatternHandler<T>> createHandlers() {
    final handlerList = <RepositoryPatternHandler<T>>[];

    // SemanticIndexableHandler and EmbeddableHandler removed
    // All embedding generation now happens asynchronously via EmbeddingQueueService
    // This prevents blocking saves on API calls and enables batch processing

    // Versioning: atomic, needs transaction, must succeed with entity
    if (versionRepository != null) {
      handlerList.add(
        VersionableHandler<T>(
          versionRepository: versionRepository,
          findByUuidSync: (ctx, uuid) => adapter.findByUuidInTx(ctx, uuid),
          getLatestVersionNumberSync: (ctx, entityUuid) =>
              versionRepository.getLatestVersionNumberInTx(ctx, entityUuid) ??
              0,
        ),
      );
    }

    // Edge cascade delete: delete edges atomically with entity
    if (edgeRepository != null) {
      handlerList.add(EdgeCascadeDeleteHandler<T>(
        edgeRepository: edgeRepository!,
      ));
    }

    return handlerList;
  }
}
