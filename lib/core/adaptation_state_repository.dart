/// # AdaptationStateRepository
///
/// ## What it does
/// Repository for the single generic AdaptationState entity.
/// Stores adaptation state for all components (STT, LLM, TTS, selectors, etc.)
/// Each state has componentType field to identify which component it belongs to.
///
/// ## Query Strategy: User → Default
/// getForComponent() implements:
/// 1. Check user-scoped state (if userId provided)
/// 2. Return null if not found (caller creates default)
/// Per-implementer tracking enables implementation-level learning
/// (e.g., Groq and Claude have separate learned parameters)
///
/// ## Concurrency Control
/// Uses optimistic locking with version numbers.
/// updateWithVersion() only succeeds if version matches.

import 'adaptation_state.dart';

abstract class AdaptationStateRepository {
  /// Find adaptation state for a component and implementer.
  ///
  /// Query by (componentType, implementer, userId).
  /// Returns null if not found; caller creates default.
  ///
  /// Parameters:
  /// - [componentType] Which component (e.g., 'stt', 'llm', 'namespace_selector')
  /// - [implementer] Which implementer (e.g., 'groq', 'deepgram'). Can be null for single-implementer components.
  /// - [userId] Optional: user ID for user-scoped state
  ///
  /// Returns: User-scoped state or null if not found
  Future<AdaptationState?> getForComponent(
    String componentType, {
    required String? implementer,
    String? userId,
  });

  /// Find all states for a component and implementer (all users)
  ///
  /// Parameters:
  /// - [componentType] Which component
  /// - [implementer] Which implementer (can be null)
  ///
  /// Returns: All states for that (componentType, implementer) pair
  Future<List<AdaptationState>> findByComponentAndImplementer(
    String componentType, {
    required String? implementer,
  });

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

  /// Delete state
  ///
  /// Parameters:
  /// - [id] State ID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Create default state for component and implementer
  ///
  /// Parameters:
  /// - [componentType] Which component
  /// - [implementer] Which implementer (can be null for single-implementer components)
  /// - [userId] Optional: user ID for user-scoped state
  ///
  /// Returns: New state with default tunable parameters
  AdaptationState createDefault(
    String componentType, {
    required String? implementer,
    String? userId,
  });
}
