/// # EmbeddableHandler
///
/// ## What it does
/// Orchestrates embedding generation for Embeddable entities.
/// Generates vector embeddings before persistence for semantic search.
///
/// ## Pattern
/// Entities that implement Embeddable opt-in to vector embeddings.
/// Embeddings are generated from entity text and stored with entity.
///
/// ## Lifecycle
/// beforeSave: Generate embedding from entity content
///
/// ## Error Semantics
/// Fail-fast: If embedding generation fails, save is aborted.
/// The entity must have a valid embedding to be persisted.

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/embeddable.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import '../repository_pattern_handler.dart';

/// Handler for Embeddable pattern.
///
/// Responsible for:
/// - Generating embeddings before entity persistence (fail-fast)
class EmbeddableHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final EmbeddingService embeddingService;

  EmbeddableHandler(this.embeddingService);

  /// Generate embedding before entity is persisted.
  ///
  /// Called before entity is persisted. Fail-fast: if embedding generation
  /// fails, save is aborted.
  ///
  /// For empty input: sets embedding to null (no vector for empty text).
  @override
  Future<void> beforeSave(T entity) async {
    if (entity is! Embeddable) return;

    await _generateEmbedding(entity as Embeddable);
  }

  /// Generate embedding for an Embeddable entity.
  ///
  /// Sets embedding to null if input is empty or whitespace.
  Future<void> _generateEmbedding(Embeddable entity) async {
    final input = entity.toEmbeddingInput();
    if (input.trim().isEmpty) {
      entity.embedding = null;
      return;
    }
    entity.embedding = await embeddingService.generate(input);
  }
}
