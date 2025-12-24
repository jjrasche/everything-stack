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
    return _store.values.where((i) => i.success).toList();
  }

  @override
  Future<List<STTInvocation>> findFailed() async {
    return _store.values.where((i) => !i.success).toList();
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
  Future<void> save(STTInvocation invocation) async {
    _store[invocation.uuid] = invocation;
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
    return _store.values.where((i) => i.success).toList();
  }

  @override
  Future<List<LLMInvocation>> findByContextType(String contextType) async {
    return _store.values
        .where((i) => i.contextType == contextType)
        .toList();
  }

  @override
  Future<List<LLMInvocation>> findFailed() async {
    return _store.values.where((i) => !i.success).toList();
  }

  @override
  Future<List<LLMInvocation>> findLowConfidence(
      {double confidenceThreshold = 0.7}) async {
    return _store.values.where((i) => i.confidence < confidenceThreshold).toList();
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
  Future<void> save(LLMInvocation invocation) async {
    _store[invocation.uuid] = invocation;
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
    return _store.values.where((i) => i.success).toList();
  }

  @override
  Future<List<TTSInvocation>> findFailed() async {
    return _store.values.where((i) => !i.success).toList();
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
  Future<void> save(TTSInvocation invocation) async {
    _store[invocation.uuid] = invocation;
  }
}
