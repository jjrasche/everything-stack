/// # FeedbackRepository Implementation
///
/// Stores user feedback across all components.
/// Queries by turn, component, and context type.

import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/domain/feedback.dart';

class FeedbackRepositoryImpl extends FeedbackRepository {
  final Map<String, Feedback> _store = {};

  FeedbackRepositoryImpl._();

  factory FeedbackRepositoryImpl.inMemory() {
    return FeedbackRepositoryImpl._();
  }

  @override
  Future<List<Feedback>> findByInvocationId(String invocationId) async {
    return _store.values
        .where((f) => f.invocationId == invocationId)
        .toList();
  }

  @override
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds) async {
    final set = invocationIds.toSet();
    return _store.values
        .where((f) => set.contains(f.invocationId))
        .toList();
  }

  @override
  Future<List<Feedback>> findByTurn(String turnId) async {
    return _store.values.where((f) => f.turnId == turnId).toList();
  }

  @override
  Future<List<Feedback>> findByTurnAndComponent(
    String turnId,
    String componentType,
  ) async {
    return _store.values
        .where((f) => f.turnId == turnId && f.componentType == componentType)
        .toList();
  }

  @override
  Future<List<Feedback>> findByContextType(String contextType) async {
    // Context type is implicit in the invocation, not directly on Feedback
    // For background/retry/test, check if turnId is null
    if (contextType == 'background' ||
        contextType == 'retry' ||
        contextType == 'test') {
      return _store.values.where((f) => f.turnId == null).toList();
    }
    return [];
  }

  @override
  Future<List<Feedback>> findAllConversational() async {
    return _store.values.where((f) => f.isConversational).toList();
  }

  @override
  Future<List<Feedback>> findAllBackground() async {
    return _store.values.where((f) => f.isBackground).toList();
  }

  @override
  Future<Feedback> save(Feedback feedback) async {
    _store[feedback.uuid] = feedback;
    return feedback;
  }

  @override
  Future<bool> delete(String id) async {
    return _store.remove(id) != null;
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final keys = _store.keys
        .where((key) => _store[key]!.turnId == turnId)
        .toList();
    for (final key in keys) {
      _store.remove(key);
    }
    return keys.length;
  }

  void clear() {
    _store.clear();
  }
}
