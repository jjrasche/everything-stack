/// # TurnRepository
///
/// ## What it does
/// Manages Turn entities - links between invocations and feedback.
/// Queries turns by correlationId, result status, and component failure.

import 'turn.dart';

abstract class TurnRepository {
  /// Find turn by UUID
  Future<Turn?> findByUuid(String uuid);

  /// Find turn by correlationId (Event ID that triggered the turn)
  Future<Turn?> findByCorrelationId(String correlationId);

  /// Find all successful turns
  Future<List<Turn>> findSuccessful();

  /// Find all failed turns
  Future<List<Turn>> findFailed();

  /// Find turns that failed in specific component
  /// [component] One of: 'stt', 'context_manager', 'llm', 'tts'
  Future<List<Turn>> findFailedInComponent(String component);

  /// Find recent turns (last N)
  Future<List<Turn>> findRecent({int limit = 10});

  /// Save turn
  Future<int> save(Turn turn);

  /// Delete turn by UUID
  Future<bool> delete(String uuid);

  /// Get total turn count
  Future<int> count();

  /// Delete all turns (for testing)
  Future<int> deleteAll();
}
