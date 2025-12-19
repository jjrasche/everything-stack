/// # Invocation Repository Implementations
///
/// Four separate repositories per component:
/// - STTInvocationRepository
/// - IntentInvocationRepository
/// - LLMInvocationRepository
/// - TTSInvocationRepository
///
/// Each extends InvocationRepository<T> with platform-specific storage.

import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocations.dart';

// ============ STT Invocation Repository ============

class STTInvocationRepositoryImpl extends InvocationRepository<STTInvocation> {
  final Map<String, STTInvocation> _store = {};

  STTInvocationRepositoryImpl._();

  factory STTInvocationRepositoryImpl.inMemory() {
    return STTInvocationRepositoryImpl._();
  }

  @override
  Future<STTInvocation?> findById(String id) async {
    return _store[id];
  }

  @override
  Future<List<STTInvocation>> findByTurn(String turnId) async {
    // This would require Turn reference; typically queried from TurnRepository
    // For now, return empty (would be populated via Turn.invocationIds)
    return [];
  }

  @override
  Future<List<STTInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<List<STTInvocation>> findByIds(List<String> ids) async {
    return ids.map((id) => _store[id]).whereType<STTInvocation>().toList();
  }

  @override
  Future<STTInvocation> save(STTInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    // Would delete all invocations for a turn
    // Typically: delete if invocationId in Turn.invocationIds
    return 0;
  }

  @override
  Future<List<STTInvocation>> findAll() async {
    return _store.values.toList();
  }

  void clear() {
    _store.clear();
  }
}

// ============ Intent Invocation Repository ============

class IntentInvocationRepositoryImpl extends InvocationRepository<IntentInvocation> {
  final Map<String, IntentInvocation> _store = {};

  IntentInvocationRepositoryImpl._();

  factory IntentInvocationRepositoryImpl.inMemory() {
    return IntentInvocationRepositoryImpl._();
  }

  @override
  Future<IntentInvocation?> findById(String id) async {
    return _store[id];
  }

  @override
  Future<List<IntentInvocation>> findByTurn(String turnId) async {
    return [];
  }

  @override
  Future<List<IntentInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<List<IntentInvocation>> findByIds(List<String> ids) async {
    return ids.map((id) => _store[id]).whereType<IntentInvocation>().toList();
  }

  @override
  Future<IntentInvocation> save(IntentInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    return 0;
  }

  @override
  Future<List<IntentInvocation>> findAll() async {
    return _store.values.toList();
  }

  void clear() {
    _store.clear();
  }
}

// ============ LLM Invocation Repository ============

class LLMInvocationRepositoryImpl extends InvocationRepository<LLMInvocation> {
  final Map<String, LLMInvocation> _store = {};

  LLMInvocationRepositoryImpl._();

  factory LLMInvocationRepositoryImpl.inMemory() {
    return LLMInvocationRepositoryImpl._();
  }

  @override
  Future<LLMInvocation?> findById(String id) async {
    return _store[id];
  }

  @override
  Future<List<LLMInvocation>> findByTurn(String turnId) async {
    return [];
  }

  @override
  Future<List<LLMInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<List<LLMInvocation>> findByIds(List<String> ids) async {
    return ids.map((id) => _store[id]).whereType<LLMInvocation>().toList();
  }

  @override
  Future<LLMInvocation> save(LLMInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    return 0;
  }

  @override
  Future<List<LLMInvocation>> findAll() async {
    return _store.values.toList();
  }

  void clear() {
    _store.clear();
  }
}

// ============ TTS Invocation Repository ============

class TTSInvocationRepositoryImpl extends InvocationRepository<TTSInvocation> {
  final Map<String, TTSInvocation> _store = {};

  TTSInvocationRepositoryImpl._();

  factory TTSInvocationRepositoryImpl.inMemory() {
    return TTSInvocationRepositoryImpl._();
  }

  @override
  Future<TTSInvocation?> findById(String id) async {
    return _store[id];
  }

  @override
  Future<List<TTSInvocation>> findByTurn(String turnId) async {
    return [];
  }

  @override
  Future<List<TTSInvocation>> findByContextType(String contextType) async {
    return _store.values.where((i) => i.contextType == contextType).toList();
  }

  @override
  Future<List<TTSInvocation>> findByIds(List<String> ids) async {
    return ids.map((id) => _store[id]).whereType<TTSInvocation>().toList();
  }

  @override
  Future<TTSInvocation> save(TTSInvocation invocation) async {
    _store[invocation.uuid] = invocation;
    return invocation;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    return 0;
  }

  @override
  Future<List<TTSInvocation>> findAll() async {
    return _store.values.toList();
  }

  void clear() {
    _store.clear();
  }
}
