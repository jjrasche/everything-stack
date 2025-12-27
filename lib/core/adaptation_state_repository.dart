/// # AdaptationStateRepository
///
/// ## What it does
/// Repository for the single generic AdaptationState entity.
/// Stores adaptation state for all components (STT, LLM, TTS, selectors, etc.)
/// Each state has componentType field to identify which component it belongs to.
///
/// ## Query Strategy: Fallback Chain
/// getForComponent() implements:
/// 1. Check user-scoped state (if userId provided)
/// 2. Fall back to global state
/// 3. Create default if neither exists
///
/// ## Concurrency Control
/// Uses optimistic locking with version numbers.
/// updateWithVersion() only succeeds if version matches.

import 'adaptation_state.dart';

abstract class AdaptationStateRepository {
  /// Find or create adaptation state for a component.
  ///
  /// Strategy:
  /// 1. If userId provided, try to get user-scoped state
  /// 2. Fall back to global state
  /// 3. Create and return default if neither exists
  ///
  /// Parameters:
  /// - [componentType] Which component (e.g., 'stt', 'llm', 'namespace_selector')
  /// - [userId] Optional: get user-scoped state; if null, get global
  ///
  /// Returns: Current state (global, user-scoped, or default)
  Future<AdaptationState> getForComponent(
    String componentType, {
    String? userId,
  });

  /// Get current adaptation state with optional component type.
  ///
  /// Convenience method: if componentType is null, uses global state.
  /// Otherwise equivalent to getForComponent().
  ///
  /// Parameters:
  /// - [componentType] Optional: which component. If null, uses global state
  /// - [userId] Optional: user ID for user-scoped state
  ///
  /// Returns: Current state
  Future<AdaptationState> getCurrent({
    String? componentType,
    String? userId,
  });


  /// Get user-scoped state (doesn't fall back to global)
  ///
  /// Parameters:
  /// - [componentType] Which component
  /// - [userId] Which user
  ///
  /// Returns: User state or null if doesn't exist
  Future<AdaptationState?> getUserState(
    String componentType,
    String userId,
  );

  /// Get global state (doesn't fall back to user)
  ///
  /// Parameters:
  /// - [componentType] Which component
  ///
  /// Returns: Global state or null if doesn't exist
  Future<AdaptationState?> getGlobal(String componentType);

  /// Find all states for a component (all users + global)
  ///
  /// Parameters:
  /// - [componentType] Which component
  ///
  /// Returns: All states for that component (global + all users)
  Future<List<AdaptationState>> findByComponent(String componentType);

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
  Future<bool> updateWithVersion(AdaptationState state);

  /// Save or create state
  ///
  /// If state has id, updates. Otherwise creates new.
  ///
  /// Parameters:
  /// - [state] State to save
  ///
  /// Returns: Saved state
  Future<AdaptationState> save(AdaptationState state);

  /// Get state history for a component (all versions, all scopes)
  ///
  /// Useful for auditing how state evolved.
  ///
  /// Parameters:
  /// - [componentType] Which component
  ///
  /// Returns: All versions ordered by version (ascending)
  Future<List<AdaptationState>> getHistory(String componentType);

  /// Delete state
  ///
  /// Parameters:
  /// - [id] State ID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Create default state for component
  ///
  /// Parameters:
  /// - [componentType] Which component
  /// - [scope] Scope: 'global' or 'user'
  /// - [userId] Optional: user ID if scope is 'user'
  ///
  /// Returns: New state with default tunable parameters
  AdaptationState createDefault(
    String componentType, {
    String scope = 'global',
    String? userId,
  });
}
