/// # LLMInvocationRepository
///
/// ## What it does
/// Manages LLMInvocation entities - LLM response generation records.
/// Queries by response length, token usage, and context type.

import 'invocations.dart';

abstract class LLMInvocationRepository {
  /// Find invocation by UUID
  Future<LLMInvocation?> findByUuid(String uuid);

  /// Find all invocations for a correlation ID (threading through events/turns)
  Future<List<LLMInvocation>> findByCorrelationId(String correlationId);

  /// Find successful invocations (completed normally)
  Future<List<LLMInvocation>> findSuccessful();

  /// Find failed invocations (had retries)
  Future<List<LLMInvocation>> findFailed();

  /// Find invocations by stop reason
  /// [stopReason] One of: 'stop', 'max_tokens', 'length', 'error'
  Future<List<LLMInvocation>> findByStopReason(String stopReason);

  /// Find invocations by context type
  /// [contextType] One of: 'conversation', 'retry', 'background', 'test'
  Future<List<LLMInvocation>> findByContextType(String contextType);

  /// Find invocations exceeding token budget
  /// [tokenThreshold] Max tokens allowed
  Future<List<LLMInvocation>> findExceedingTokens(int tokenThreshold);

  /// Find recent invocations
  Future<List<LLMInvocation>> findRecent({int limit = 10});

  /// Save invocation
  Future<int> save(LLMInvocation invocation);

  /// Delete invocation
  Future<bool> delete(String uuid);

  /// Get total count
  Future<int> count();

  /// Delete all (for testing)
  Future<int> deleteAll();
}
