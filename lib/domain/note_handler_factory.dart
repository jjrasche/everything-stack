/// # NoteHandlerFactory
///
/// ## What it does
/// Creates the ordered list of pattern handlers for Note entities.
///
/// ## Handler Wiring Strategy
/// Services are injected via constructor parameters. Factory receives:
/// - EmbeddingService (required for Embeddable pattern)
/// - ChunkingService (optional, for SemanticIndexable pattern)
/// - VersionRepository (optional, for Versionable pattern)
/// - TransactionManager (optional, for atomic version recording)
/// - PersistenceAdapter (required for transaction context callbacks)
///
/// ## Handler Order
/// 1. SemanticIndexableHandler - deletes old chunks before save (ephemeral)
/// 2. EmbeddableHandler - generates embeddings before save (best-effort)
/// 3. VersionableHandler - records changes inside transaction (atomic)
///
/// Order is critical for multi-pattern entities.

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/handlers/embeddable_handler.dart';
import 'package:everything_stack_template/core/handlers/semantic_indexable_handler.dart';
import 'package:everything_stack_template/core/handlers/versionable_handler.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import 'package:everything_stack_template/core/repository_pattern_handler.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'note.dart';

/// Factory for creating Note handlers.
///
/// This factory decides:
/// 1. Which patterns Note implements
/// 2. Which handlers to create
/// 3. Handler execution order
/// 4. Service dependencies for each handler
class NoteHandlerFactory implements RepositoryHandlerFactory<Note> {
  final EmbeddingService? embeddingService;
  final ChunkingService? chunkingService;
  final dynamic versionRepository;
  final PersistenceAdapter<Note> adapter;

  NoteHandlerFactory({
    required this.embeddingService,
    required this.chunkingService,
    required this.versionRepository,
    required this.adapter,
  });

  /// Create handlers in execution order.
  ///
  /// Order:
  /// 1. SemanticIndexable - deletes old chunks before save
  /// 2. Embeddable - generates embeddings before save
  /// 3. Versionable - records changes inside transaction
  @override
  List<RepositoryPatternHandler<Note>> createHandlers() {
    final handlerList = <RepositoryPatternHandler<Note>>[];

    // Add handler only if service is provided
    if (chunkingService != null) {
      handlerList.add(SemanticIndexableHandler<Note>(chunkingService!));
    }

    if (embeddingService != null) {
      handlerList.add(EmbeddableHandler<Note>(embeddingService!));
    }

    if (versionRepository != null) {
      handlerList.add(
        VersionableHandler<Note>(
          versionRepository: versionRepository,
          findByUuidSync: (ctx, uuid) => adapter.findByUuidInTx(ctx, uuid),
          getLatestVersionNumberSync: (ctx, entityUuid) =>
              versionRepository.getLatestVersionNumberInTx(ctx, entityUuid) ??
              0,
        ),
      );
    }

    return handlerList;
  }
}
