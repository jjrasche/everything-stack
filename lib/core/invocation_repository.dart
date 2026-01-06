/// # InvocationRepository Base Class
///
/// ## What it does
/// Abstract base for all invocation repositories.
/// Each component (STT, Intent, LLM, TTS) has its own repo that extends this.
///
/// ## Why Abstract?
/// Provides consistent interface while allowing platform-specific implementations:
/// - ObjectBox on iOS/Android
/// - IndexedDB on Web
/// Different implementations, same contract.
///
/// ## Query Operations
/// - findById(): Get specific invocation
/// - findByTurn(): Get all invocations for a turn
/// - findByContextType(): Get all invocations of a context (background, retry, etc.)
/// - save(): Persist invocation
/// - delete(): Remove invocation

import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/handlers/semantic_indexable_handler.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

abstract class InvocationRepository<T> {
  /// Find invocation by ID
  ///
  /// Parameters:
  /// - [id] Invocation ID
  ///
  /// Returns: Invocation or null if not found
  Future<T?> findById(String id);

  /// Find all invocations for a specific turn
  ///
  /// Parameters:
  /// - [turnId] Which turn
  ///
  /// Returns: List of invocations (may be empty)
  Future<List<T>> findByTurn(String turnId);

  /// Find all invocations of a specific context type
  ///
  /// Parameters:
  /// - [contextType] 'conversation', 'retry', 'background', 'test'
  ///
  /// Returns: List of invocations matching context
  Future<List<T>> findByContextType(String contextType);

  /// Find invocations by IDs
  ///
  /// Used when Turn.invocationIds contains specific IDs to load.
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

  /// Delete all invocations for a turn
  ///
  /// Parameters:
  /// - [turnId] Which turn to clear
  ///
  /// Returns: Number of invocations deleted
  Future<int> deleteByTurn(String turnId);

  /// Find all invocations (for cleanup/archival)
  ///
  /// Returns: All invocations of this type
  Future<List<T>> findAll();
}

/// # InvocationRepository Adapter
///
/// Bridges EntityRepository to InvocationRepository interface while adding
/// semantic indexing via SemanticIndexableHandler.
///
/// This adapter:
/// - Extends EntityRepository to get CRUD operations
/// - Implements InvocationRepository to satisfy type contracts
/// - Wires SemanticIndexableHandler for automatic chunking on save/delete
///
/// Unlike a dead wrapper, this adapter performs real work: it orchestrates
/// the handler lifecycle while implementing the required interface.
/// Create InvocationRepository with SemanticIndexableHandler wired.
///
/// Returns an EntityRepository configured with semantic indexing handler.
/// Cast to InvocationRepository<Invocation> when registering in GetIt.
EntityRepository<Invocation> createInvocationRepository({
  required PersistenceAdapter<Invocation> adapter,
  required EmbeddingService embeddingService,
  required ChunkingService chunkingService,
}) =>
    EntityRepository<Invocation>(
      adapter: adapter,
      embeddingService: embeddingService,
      chunkingService: chunkingService,
      handlers: [SemanticIndexableHandler<Invocation>(chunkingService)],
    );
