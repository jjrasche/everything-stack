/// # STTInvocationRepository
///
/// ## What it does
/// Manages STTInvocation entities - speech-to-text execution records.
/// Queries by confidence, retry status, and context type.

import 'invocations.dart';

abstract class STTInvocationRepository {
  /// Find invocation by UUID
  Future<STTInvocation?> findByUuid(String uuid);

  /// Find all invocations for an audio
  Future<List<STTInvocation>> findByAudioId(String audioId);

  /// Find all invocations for a correlation ID (threading through events/turns)
  Future<List<STTInvocation>> findByCorrelationId(String correlationId);

  /// Find successful invocations (no retries)
  Future<List<STTInvocation>> findSuccessful();

  /// Find failed invocations (had retries)
  Future<List<STTInvocation>> findFailed();

  /// Find invocations with low confidence (< threshold)
  /// [confidenceThreshold] Default 0.7
  Future<List<STTInvocation>> findLowConfidence({double confidenceThreshold = 0.7});

  /// Find invocations by context type
  /// [contextType] One of: 'conversation', 'retry', 'background', 'test'
  Future<List<STTInvocation>> findByContextType(String contextType);

  /// Find recent invocations
  Future<List<STTInvocation>> findRecent({int limit = 10});

  /// Save invocation
  Future<int> save(STTInvocation invocation);

  /// Delete invocation
  Future<bool> delete(String uuid);

  /// Get total count
  Future<int> count();

  /// Delete all (for testing)
  Future<int> deleteAll();
}
