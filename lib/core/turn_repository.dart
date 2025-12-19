/// # TurnRepository
///
/// ## What it does
/// Manages Turn entities (conversational context).
/// Each turn groups the invocations from one user utterance cycle:
/// STT (input) → Intent (classify) → LLM (respond) → TTS (audio)
///
/// ## Query Operations
/// - findById(): Get specific turn
/// - findByConversation(): Get all turns in a conversation
/// - save(): Persist turn
/// - delete(): Remove turn

import '../domain/turn.dart';

abstract class TurnRepository {
  /// Find turn by ID
  ///
  /// Parameters:
  /// - [id] Turn ID
  ///
  /// Returns: Turn or null if not found
  Future<Turn?> findById(String id);

  /// Find all turns in a conversation
  ///
  /// Ordered by turnIndex (sequential).
  ///
  /// Parameters:
  /// - [conversationId] Which conversation
  ///
  /// Returns: List of turns (ordered)
  Future<List<Turn>> findByConversation(String conversationId);

  /// Find all turns marked for feedback in a conversation
  ///
  /// Used in TurnListScreen to show what needs review.
  ///
  /// Parameters:
  /// - [conversationId] Which conversation
  ///
  /// Returns: Turns sorted by markedAt (most recent first)
  Future<List<Turn>> findMarkedForFeedbackByConversation(String conversationId);

  /// Find turn containing specific invocation
  ///
  /// Used to reconstruct context around an invocation.
  ///
  /// Parameters:
  /// - [invocationId] Which invocation
  ///
  /// Returns: Turn or null if invocation not in any turn
  Future<Turn?> findByInvocationId(String invocationId);

  /// Save turn
  ///
  /// Parameters:
  /// - [turn] Turn to save
  ///
  /// Returns: Saved turn
  Future<Turn> save(Turn turn);

  /// Delete turn
  ///
  /// Parameters:
  /// - [id] Turn ID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Delete all turns in conversation
  ///
  /// Parameters:
  /// - [conversationId] Which conversation
  ///
  /// Returns: Number of turns deleted
  Future<int> deleteByConversation(String conversationId);
}
