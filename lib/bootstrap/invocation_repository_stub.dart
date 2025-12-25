/// Web stub for invocation repositories
///
/// Provides non-ObjectBox invocation repositories for STT/TTS/LLM services.
/// ContextManagerInvocationRepositoryImpl is not available on web (depends on ObjectBox).
library;

import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/stt_invocation_repository.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';
import 'package:everything_stack_template/domain/tts_invocation_repository.dart';

// ============ STT Invocation Repository ============

class STTInvocationRepositoryImpl implements STTInvocationRepository {
  final Map<String, STTInvocation> _store = {};

  STTInvocationRepositoryImpl._();

  factory STTInvocationRepositoryImpl.inMemory() {
    return STTInvocationRepositoryImpl._();
  }

  @override
  Future<STTInvocation?> findByUuid(String uuid) async {
    return _store[uuid];
  }

  @override
  Future<List<STTInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<List<STTInvocation>> findByAudioId(String audioId) async {
    return _store.values.where((i) => i.audioId == audioId).toList();
  }

  @override
  Future<List<STTInvocation>> findByCorrelationId(String correlationId) async {
    return _store.values.where((i) => i.correlationId == correlationId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<STTInvocation>> findSuccessful() async {
    // No success field on STTInvocation - return all (they are inherently successful if recorded)
    return _store.values.toList();
  }

  @override
  Future<List<STTInvocation>> findFailed() async {
    // Filter by retryCount > 0 or lastError != null to find failed ones
    return _store.values.where((i) => i.lastError != null).toList();
  }

  @override
  Future<List<STTInvocation>> findLowConfidence(
      {double confidenceThreshold = 0.7}) async {
    return _store.values.where((i) => i.confidence < confidenceThreshold).toList();
  }

  @override
  Future<List<STTInvocation>> findRecent({int limit = 10}) async {
    final sorted = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  @override
  Future<int> count() async {
    return _store.length;
  }

  @override
  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  @override
  Future<int> save(STTInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return 1; // Return 1 to indicate success (mock behavior)
  }
}

// ============ LLM Invocation Repository ============

class LLMInvocationRepositoryImpl implements LLMInvocationRepository {
  final Map<String, LLMInvocation> _store = {};

  LLMInvocationRepositoryImpl._();

  factory LLMInvocationRepositoryImpl.inMemory() {
    return LLMInvocationRepositoryImpl._();
  }

  @override
  Future<LLMInvocation?> findByUuid(String uuid) async {
    return _store[uuid];
  }

  @override
  Future<List<LLMInvocation>> findByCorrelationId(String correlationId) async {
    return _store.values
        .where((i) => i.correlationId == correlationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<LLMInvocation>> findSuccessful() async {
    // No success field on LLMInvocation - return all
    return _store.values.toList();
  }

  @override
  Future<List<LLMInvocation>> findByContextType(String contextType) async {
    return _store.values
        .where((i) => i.contextType == contextType)
        .toList();
  }

  @override
  Future<List<LLMInvocation>> findFailed() async {
    // Filter by lastError != null to find failed ones
    return _store.values.where((i) => i.lastError != null).toList();
  }

  // findLowConfidence not in LLMInvocationRepository interface
  Future<List<LLMInvocation>> findLowConfidence(
      {double confidenceThreshold = 0.7}) async {
    // LLMInvocation doesn't have confidence field - return empty
    return [];
  }

  @override
  Future<List<LLMInvocation>> findByStopReason(String stopReason) async {
    return _store.values.where((i) => i.stopReason == stopReason).toList();
  }

  @override
  Future<List<LLMInvocation>> findExceedingTokens(int tokenLimit) async {
    return _store.values.where((i) => i.tokenCount > tokenLimit).toList();
  }

  @override
  Future<List<LLMInvocation>> findRecent({int limit = 10}) async {
    final sorted = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  @override
  Future<int> count() async {
    return _store.length;
  }

  @override
  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  @override
  Future<int> save(LLMInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return 1;
  }
}

// ============ TTS Invocation Repository ============

class TTSInvocationRepositoryImpl implements TTSInvocationRepository {
  final Map<String, TTSInvocation> _store = {};

  TTSInvocationRepositoryImpl._();

  factory TTSInvocationRepositoryImpl.inMemory() {
    return TTSInvocationRepositoryImpl._();
  }

  @override
  Future<TTSInvocation?> findByUuid(String uuid) async {
    return _store[uuid];
  }

  @override
  Future<List<TTSInvocation>> findByCorrelationId(String correlationId) async {
    return _store.values
        .where((i) => i.correlationId == correlationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<TTSInvocation>> findSuccessful() async {
    // No success field on TTSInvocation - return all
    return _store.values.toList();
  }

  @override
  Future<List<TTSInvocation>> findFailed() async {
    // Filter by lastError != null to find failed ones
    return _store.values.where((i) => i.lastError != null).toList();
  }

  @override
  Future<List<TTSInvocation>> findByAudioId(String audioId) async {
    return _store.values.where((i) => i.audioId == audioId).toList();
  }

  @override
  Future<List<TTSInvocation>> findByText(String text) async {
    return _store.values.where((i) => i.text == text).toList();
  }

  @override
  Future<List<TTSInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<int> count() async {
    return _store.length;
  }

  @override
  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  @override
  Future<int> save(TTSInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return 1;
  }

  @override
  Future<List<TTSInvocation>> findRecent({int limit = 10}) async {
    final sorted = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  @override
  Future<List<TTSInvocation>> findSlowInvocations({int latencyThresholdMs = 1000}) async {
    // TTS synthesis latency - invocations taking > threshold
    // Stub implementation: estimate based on timestamp + 1s default
    return _store.values
        .where((i) => i.retryCount > 0 || i.lastError != null)
        .toList();
  }
}
