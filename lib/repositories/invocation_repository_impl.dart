/// # Invocation Repository Implementations
///
/// Four separate repositories per component:
/// - STTInvocationRepository
/// - LLMInvocationRepository
/// - TTSInvocationRepository
/// - ContextManagerInvocationRepository (in-memory for testing)
///
/// Each implements domain-specific repository interface with in-memory storage.

import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/stt_invocation_repository.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';
import 'package:everything_stack_template/domain/tts_invocation_repository.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';

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
    return _store.values
        .where((i) => i.correlationId == correlationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<STTInvocation>> findSuccessful() async {
    return _store.values
        .where((i) => i.retryCount == 0)
        .toList();
  }

  @override
  Future<List<STTInvocation>> findFailed() async {
    return _store.values
        .where((i) => i.retryCount > 0)
        .toList();
  }

  @override
  Future<List<STTInvocation>> findLowConfidence(
      {double confidenceThreshold = 0.7}) async {
    return _store.values
        .where((i) => i.confidence < confidenceThreshold)
        .toList();
  }

  @override
  Future<List<STTInvocation>> findRecent({int limit = 10}) async {
    final all = _store.values.toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  @override
  Future<int> save(STTInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation.id;
  }

  @override
  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<int> count() async {
    return _store.length;
  }

  @override
  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  void clear() {
    _store.clear();
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
  Future<List<LLMInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
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
    return _store.values
        .where((i) => i.retryCount == 0)
        .toList();
  }

  @override
  Future<List<LLMInvocation>> findFailed() async {
    return _store.values
        .where((i) => i.retryCount > 0)
        .toList();
  }

  @override
  Future<List<LLMInvocation>> findByStopReason(String stopReason) async {
    return _store.values
        .where((i) => i.stopReason == stopReason)
        .toList();
  }

  @override
  Future<List<LLMInvocation>> findExceedingTokens(int tokenThreshold) async {
    return _store.values
        .where((i) => i.tokenCount > tokenThreshold)
        .toList();
  }

  @override
  Future<List<LLMInvocation>> findRecent({int limit = 10}) async {
    final all = _store.values.toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  @override
  Future<int> save(LLMInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation.id;
  }

  @override
  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<int> count() async {
    return _store.length;
  }

  @override
  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  void clear() {
    _store.clear();
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
  Future<List<TTSInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<List<TTSInvocation>> findByCorrelationId(String correlationId) async {
    return _store.values
        .where((i) => i.correlationId == correlationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
  Future<List<TTSInvocation>> findSuccessful() async {
    return _store.values
        .where((i) => i.retryCount == 0)
        .toList();
  }

  @override
  Future<List<TTSInvocation>> findFailed() async {
    return _store.values
        .where((i) => i.retryCount > 0)
        .toList();
  }

  @override
  Future<List<TTSInvocation>> findSlowInvocations(int maxLatencyMs) async {
    // Would calculate latency: timestamp to now
    // For now, return empty
    return [];
  }

  @override
  Future<List<TTSInvocation>> findRecent({int limit = 10}) async {
    final all = _store.values.toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  @override
  Future<int> save(TTSInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation.id;
  }

  @override
  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<int> count() async {
    return _store.length;
  }

  @override
  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  void clear() {
    _store.clear();
  }
}

// ============ ContextManager Invocation Repository ============

class ContextManagerInvocationRepositoryImpl {
  final Map<String, ContextManagerInvocation> _store = {};

  ContextManagerInvocationRepositoryImpl._();

  factory ContextManagerInvocationRepositoryImpl.inMemory() {
    return ContextManagerInvocationRepositoryImpl._();
  }

  Future<ContextManagerInvocation?> findByUuid(String uuid) async {
    return _store[uuid];
  }

  Future<List<ContextManagerInvocation>> findByCorrelationId(
      String correlationId) async {
    return _store.values
        .where((i) => i.correlationId == correlationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<List<ContextManagerInvocation>> findByPersonality(
      String personalityId) async {
    return _store.values
        .where((i) => i.personalityId == personalityId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<ContextManagerInvocation>> findRecent({int limit = 50}) async {
    final all = _store.values.toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  Future<List<ContextManagerInvocation>> findWithErrors() async {
    return _store.values
        .where((i) => i.errorType != null)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<int> save(ContextManagerInvocation invocation) async {
    invocation.prepareForSave();
    _store[invocation.uuid] = invocation;
    return invocation.id;
  }

  Future<bool> delete(String uuid) async {
    return _store.remove(uuid) != null;
  }

  Future<int> count() async {
    return _store.length;
  }

  Future<int> deleteAll() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  void clear() {
    _store.clear();
  }
}
