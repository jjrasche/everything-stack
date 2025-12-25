/// # AdaptationStateRepository Implementations
///
/// Four separate repositories per component:
/// - STTAdaptationStateRepository
/// - IntentAdaptationStateRepository
/// - LLMAdaptationStateRepository
/// - TTSAdaptationStateRepository
///
/// ## Query Strategy
/// getCurrent() implements fallback chain:
/// 1. Check user-scoped state
/// 2. Fall back to global state
/// 3. Create default if neither exists

import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/domain/adaptation_state.dart';
import 'package:everything_stack_template/domain/adaptation_state_generic.dart';

// ============ STT Adaptation State Repository ============

class STTAdaptationStateRepositoryImpl
    extends AdaptationStateRepository<STTAdaptationState> {
  final Map<String, STTAdaptationState> _store = {};

  STTAdaptationStateRepositoryImpl._();

  factory STTAdaptationStateRepositoryImpl.inMemory() {
    return STTAdaptationStateRepositoryImpl._();
  }

  @override
  Future<STTAdaptationState> getCurrent({String? userId}) async {
    // 1. Check user-scoped state
    if (userId != null) {
      try {
        final userState = _store.values.firstWhere(
          (s) => s.scope == 'user' && s.userId == userId,
        );
        return userState;
      } catch (e) {
        // Not found, continue
      }
    }

    // 2. Fall back to global state
    try {
      final globalState = _store.values.firstWhere(
        (s) => s.scope == 'global',
      );
      return globalState;
    } catch (e) {
      // Not found, create default
    }

    // 3. Create default
    return createDefault();
  }

  @override
  Future<STTAdaptationState?> getUserState(String userId) async {
    try {
      return _store.values.firstWhere(
        (s) => s.scope == 'user' && s.userId == userId,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<STTAdaptationState?> getGlobal() async {
    try {
      return _store.values.firstWhere((s) => s.scope == 'global');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> updateWithVersion(STTAdaptationState state) async {
    final current = _store[state.uuid];
    if (current == null || current.version != state.version) {
      return false; // Version conflict
    }

    _store[state.uuid] = state;
    return true;
  }

  @override
  Future<STTAdaptationState> save(STTAdaptationState state) async {
    _store[state.uuid] = state;
    return state;
  }

  @override
  Future<List<STTAdaptationState>> getHistory() async {
    final states = _store.values.toList();
    states.sort((a, b) => a.version.compareTo(b.version));
    return states;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  STTAdaptationState createDefault() {
    return STTAdaptationState(scope: 'global');
  }

  void clear() {
    _store.clear();
  }
}

// ============ LLM Adaptation State Repository ============

class LLMAdaptationStateRepositoryImpl
    extends AdaptationStateRepository<LLMAdaptationState> {
  final Map<String, LLMAdaptationState> _store = {};

  LLMAdaptationStateRepositoryImpl._();

  factory LLMAdaptationStateRepositoryImpl.inMemory() {
    return LLMAdaptationStateRepositoryImpl._();
  }

  @override
  Future<LLMAdaptationState> getCurrent({String? userId}) async {
    if (userId != null) {
      try {
        return _store.values.firstWhere(
          (s) => s.scope == 'user' && s.userId == userId,
        );
      } catch (e) {
        // Not found, continue
      }
    }

    try {
      return _store.values.firstWhere(
        (s) => s.scope == 'global',
      );
    } catch (e) {
      // Not found, create default
    }

    return createDefault();
  }

  @override
  Future<LLMAdaptationState?> getUserState(String userId) async {
    try {
      return _store.values.firstWhere(
        (s) => s.scope == 'user' && s.userId == userId,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<LLMAdaptationState?> getGlobal() async {
    try {
      return _store.values.firstWhere((s) => s.scope == 'global');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> updateWithVersion(LLMAdaptationState state) async {
    final current = _store[state.uuid];
    if (current == null || current.version != state.version) {
      return false;
    }

    _store[state.uuid] = state;
    return true;
  }

  @override
  Future<LLMAdaptationState> save(LLMAdaptationState state) async {
    _store[state.uuid] = state;
    return state;
  }

  @override
  Future<List<LLMAdaptationState>> getHistory() async {
    final states = _store.values.toList();
    states.sort((a, b) => a.version.compareTo(b.version));
    return states;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  LLMAdaptationState createDefault() {
    return LLMAdaptationState(scope: 'global');
  }

  void clear() {
    _store.clear();
  }
}

// ============ TTS Adaptation State Repository ============

class TTSAdaptationStateRepositoryImpl
    extends AdaptationStateRepository<TTSAdaptationState> {
  final Map<String, TTSAdaptationState> _store = {};

  TTSAdaptationStateRepositoryImpl._();

  factory TTSAdaptationStateRepositoryImpl.inMemory() {
    return TTSAdaptationStateRepositoryImpl._();
  }

  @override
  Future<TTSAdaptationState> getCurrent({String? userId}) async {
    if (userId != null) {
      try {
        return _store.values.firstWhere(
          (s) => s.scope == 'user' && s.userId == userId,
        );
      } catch (e) {
        // Not found, continue
      }
    }

    try {
      return _store.values.firstWhere(
        (s) => s.scope == 'global',
      );
    } catch (e) {
      // Not found, create default
    }

    return createDefault();
  }

  @override
  Future<TTSAdaptationState?> getUserState(String userId) async {
    try {
      return _store.values.firstWhere(
        (s) => s.scope == 'user' && s.userId == userId,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<TTSAdaptationState?> getGlobal() async {
    try {
      return _store.values.firstWhere((s) => s.scope == 'global');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> updateWithVersion(TTSAdaptationState state) async {
    final current = _store[state.uuid];
    if (current == null || current.version != state.version) {
      return false;
    }

    _store[state.uuid] = state;
    return true;
  }

  @override
  Future<TTSAdaptationState> save(TTSAdaptationState state) async {
    _store[state.uuid] = state;
    return state;
  }

  @override
  Future<List<TTSAdaptationState>> getHistory() async {
    final states = _store.values.toList();
    states.sort((a, b) => a.version.compareTo(b.version));
    return states;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  TTSAdaptationState createDefault() {
    return TTSAdaptationState(scope: 'global');
  }

  void clear() {
    _store.clear();
  }
}

// ============ Generic Adaptation State Repository ============

class AdaptationStateRepositoryImpl
    extends AdaptationStateRepository<AdaptationState> {
  final Map<String, AdaptationState> _store = {};

  AdaptationStateRepositoryImpl._();

  factory AdaptationStateRepositoryImpl() {
    // TODO: Phase 1 - Replace with ObjectBox/IndexedDB per platform
    // For now, in-memory is the only implementation
    return AdaptationStateRepositoryImpl._();
  }

  factory AdaptationStateRepositoryImpl.inMemory() {
    return AdaptationStateRepositoryImpl._();
  }

  @override
  Future<AdaptationState> getCurrent({String? userId}) async {
    // For now, return first state (Phase 0 - no user scoping yet)
    if (_store.isEmpty) {
      return createDefault();
    }
    return _store.values.first;
  }

  @override
  Future<AdaptationState?> getUserState(String userId) async {
    try {
      return _store.values.firstWhere((s) => s.uuid == userId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<AdaptationState?> getGlobal() async {
    if (_store.isEmpty) return null;
    return _store.values.first;
  }

  @override
  Future<bool> updateWithVersion(AdaptationState state) async {
    final current = _store[state.uuid];
    if (current == null || current.version != state.version) {
      return false;
    }
    _store[state.uuid] = state;
    return true;
  }

  @override
  Future<AdaptationState> save(AdaptationState state) async {
    _store[state.uuid] = state;
    return state;
  }

  @override
  Future<List<AdaptationState>> getHistory() async {
    final states = _store.values.toList();
    states.sort((a, b) => a.version.compareTo(b.version));
    return states;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  AdaptationState createDefault() {
    return AdaptationState(
      componentType: 'default',
      data: {},
    );
  }

  void clear() {
    _store.clear();
  }
}
