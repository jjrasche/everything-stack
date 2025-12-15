/// # NoteHandlerFactory
///
/// ## What it does
/// Thin wrapper around GenericHandlerFactory for Note entities.
/// Uses default handler ordering from generic factory.
///
/// ## Customization
/// If Note ever needs custom handler ordering, override createHandlers().
/// For now, the generic factory order is optimal.

import 'package:everything_stack_template/core/generic_handler_factory.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/repository_pattern_handler.dart';
import 'package:everything_stack_template/core/edge_repository.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'note.dart';

/// Factory for creating Note handlers.
///
/// Inherits handler creation from GenericHandlerFactory.
/// Handler order: SemanticIndexable → Embeddable → Versionable → EdgeCascadeDelete
///
/// This is a thin wrapper that allows:
/// 1. Type-safe Note-specific factory
/// 2. Easy customization if Note needs special handler ordering
/// 3. Clear intent that Note uses the standard handler pattern
class NoteHandlerFactory extends GenericHandlerFactory<Note> {
  NoteHandlerFactory({
    required EmbeddingService? embeddingService,
    required ChunkingService? chunkingService,
    required dynamic versionRepository,
    required PersistenceAdapter<Note> adapter,
    EdgeRepository? edgeRepository,
  }) : super(
    embeddingService: embeddingService,
    chunkingService: chunkingService,
    versionRepository: versionRepository,
    adapter: adapter,
    edgeRepository: edgeRepository,
  );
}
