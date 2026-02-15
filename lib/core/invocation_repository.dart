/// Abstract base for invocation repositories.
/// Provides consistent interface across platform-specific implementations.

import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/handlers/semantic_indexable_handler.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/enrichment/enrichment_runner.dart';

abstract class InvocationRepository<T> {
  /// Find invocation by ID
  ///
  /// Parameters:
  /// - [id] Invocation ID
  ///
  /// Returns: Invocation or null if not found
  Future<T?> findById(String id);

  /// Find all invocations of a specific context type
  ///
  /// Parameters:
  /// - [contextType] 'conversation', 'retry', 'background', 'test'
  ///
  /// Returns: List of invocations matching context
  Future<List<T>> findByContextType(String contextType);

  /// Find invocations by IDs
  ///
  /// Parameters:
  /// - [ids] List of invocation IDs
  ///
  /// Returns: List of invocations (filters to only existing IDs)
  Future<List<T>> findByIds(List<String> ids);

  /// Save (create or update) an invocation
  ///
  /// Parameters:
  /// - [invocation] Invocation to save
  ///
  /// Returns: The saved invocation (with ID if newly created)
  Future<T> save(T invocation);

  /// Delete an invocation
  ///
  /// Parameters:
  /// - [id] Invocation ID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Find all invocations (for cleanup/archival)
  ///
  /// Returns: All invocations of this type
  Future<List<T>> findAll();
}

/// Creates an EntityRepository configured with SemanticIndexableHandler for invocations.
EntityRepository<Invocation> createInvocationRepository({
  required PersistenceAdapter<Invocation> adapter,
  required EmbeddingService embeddingService,
  required ChunkingService chunkingService,
  EnrichmentRunner? enrichmentRunner,
}) =>
    EntityRepository<Invocation>(
      adapter: adapter,
      embeddingService: embeddingService,
      chunkingService: chunkingService,
      enrichmentRunner: enrichmentRunner,
      handlers: [SemanticIndexableHandler<Invocation>(chunkingService)],
    );
