/// # TTSInvocationRepository
///
/// ## What it does
/// Manages TTSInvocation entities - text-to-speech synthesis records.
/// Queries by audio metadata, retry status, and context type.

import 'invocations.dart';

abstract class TTSInvocationRepository {
  /// Find invocation by UUID
  Future<TTSInvocation?> findByUuid(String uuid);

  /// Find all invocations for a correlation ID (threading through events/turns)
  Future<List<TTSInvocation>> findByCorrelationId(String correlationId);

  /// Find all invocations for an audio ID
  /// Used to find which synthesis created a particular audio
  Future<List<TTSInvocation>> findByAudioId(String audioId);

  /// Find invocations for specific text
  Future<List<TTSInvocation>> findByText(String text);

  /// Find successful invocations (completed without retries)
  Future<List<TTSInvocation>> findSuccessful();

  /// Find failed invocations (had retries)
  Future<List<TTSInvocation>> findFailed();

  /// Find invocations exceeding latency threshold
  /// [maxLatencyMs] Maximum acceptable latency in milliseconds
  Future<List<TTSInvocation>> findSlowInvocations(int maxLatencyMs);

  /// Find invocations by context type
  /// [contextType] One of: 'conversation', 'retry', 'background', 'test'
  Future<List<TTSInvocation>> findByContextType(String contextType);

  /// Find recent invocations
  Future<List<TTSInvocation>> findRecent({int limit = 10});

  /// Save invocation
  Future<int> save(TTSInvocation invocation);

  /// Delete invocation
  Future<bool> delete(String uuid);

  /// Get total count
  Future<int> count();

  /// Delete all (for testing)
  Future<int> deleteAll();
}
