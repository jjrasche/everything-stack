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
