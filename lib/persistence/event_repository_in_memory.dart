/// # In-Memory Event Repository
///
/// Simple implementation for testing and offline-first operation.
/// All events are stored in memory (lost on app restart).
///
/// Used by:
/// - Integration tests (fresh repository per test)
/// - Early MVP (before ObjectBox/IndexedDB integration)
library;

import '../core/event_repository.dart';
import '../services/events/system_event.dart';
import '../services/events/transcription_complete.dart';
import '../services/events/error_occurred.dart';

class InMemoryEventRepository implements EventRepository {
  final List<SystemEvent> _events = [];

  @override
  Future<void> save(SystemEvent event) async {
    _events.add(event);
  }

  @override
  Future<void> saveBatch(List<SystemEvent> events) async {
    _events.addAll(events);
  }

  @override
  Future<List<SystemEvent>> getByCorrelationId(String correlationId) async {
    return _events.where((e) => e.correlationId == correlationId).toList();
  }

  @override
  Future<List<T>> getByType<T extends SystemEvent>() async {
    return _events.where((e) => e.runtimeType == T).cast<T>().toList();
  }

  @override
  Future<List<SystemEvent>> getSince(DateTime timestamp) async {
    return _events.where((e) => e.createdAt.isAfter(timestamp)).toList();
  }

  @override
  Future<List<SystemEvent>> getAll() async {
    return List.from(_events);
  }

  @override
  Future<bool> delete(String eventId) async {
    // In-memory doesn't use IDs, just remove first matching
    final initialLength = _events.length;
    _events.removeWhere((e) => e.correlationId == eventId);
    return _events.length < initialLength;
  }

  @override
  Future<void> clear() async {
    _events.clear();
  }

  @override
  Future<int> count() async {
    return _events.length;
  }

  @override
  Future<int> countByCorrelationId(String correlationId) async {
    return _events.where((e) => e.correlationId == correlationId).length;
  }
}
