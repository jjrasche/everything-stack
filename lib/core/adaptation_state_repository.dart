/// # AdaptationStateRepository Base Class
///
/// ## What it does
/// Abstract base for adaptation state repositories.
/// Each component (STT, Intent, LLM, TTS) has its own repo.
///
/// ## Query Strategy: Fallback Chain
/// getCurrent() implements:
/// 1. Check user-scoped state (if userId provided)
/// 2. Fall back to global state
/// 3. Create default if neither exists
///
/// ## Concurrency Control
/// Uses optimistic locking with version numbers.
/// updateWithVersion() only succeeds if version matches.

abstract class AdaptationStateRepository<T> {
  /// Get current adaptation state with fallback chain
  ///
  /// Strategy:
  /// 1. If userId provided, try to get user-scoped state
  /// 2. Fall back to global state
  /// 3. Create and return default if neither exists
  ///
  /// Parameters:
  /// - [userId] Optional: get user-scoped state
  ///
  /// Returns: Current state (global, user, or default)
  Future<T> getCurrent({String? userId});

  /// Get user-scoped state (doesn't fall back to global)
  ///
  /// Parameters:
  /// - [userId] Which user
  ///
  /// Returns: User state or null if doesn't exist
  Future<T?> getUserState(String userId);

  /// Get global state (doesn't fall back to user)
  ///
  /// Returns: Global state or null if doesn't exist
  Future<T?> getGlobal();

  /// Save state with version check (optimistic locking)
  ///
  /// Only updates if state.version matches current version in DB.
  /// Prevents race conditions when multiple components update simultaneously.
  ///
  /// Parameters:
  /// - [state] State to save (must have version set)
  ///
  /// Returns: true if update succeeded, false if version conflict
  /// Throws: Exception if state not found
  Future<bool> updateWithVersion(T state);

  /// Save or create state
  ///
  /// If state has id, updates. Otherwise creates new.
  ///
  /// Parameters:
  /// - [state] State to save
  ///
  /// Returns: Saved state
  Future<T> save(T state);

  /// Get state history (all versions)
  ///
  /// Useful for auditing how state evolved.
  ///
  /// Returns: All versions ordered by version (ascending)
  Future<List<T>> getHistory();

  /// Delete state
  ///
  /// Parameters:
  /// - [id] State ID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Create default state
  ///
  /// Returns: New state with default tunable parameters
  T createDefault();
}
