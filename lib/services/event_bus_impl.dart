library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'event_bus.dart';
import '../core/event.dart';
import '../core/event_repository.dart';

class EventBusImpl implements EventBus {
  final EventRepository repository;

  // Single broadcast stream for all Event entities
  late StreamController<Event> _eventStream;

  // Ring buffer: keep only recent events in memory (bounded)
  // Prevents unbounded memory growth in long-running apps
  late List<Event> _eventLog;
  int _eventLogIndex = 0;
  static const int _maxEventLogSize = 1000; // Ring buffer max events

  // Map of correlationId → event count (for testing)
  final Map<String, int> _correlationIdCounts = {};

  EventBusImpl({required this.repository}) {
    _eventLog = List.filled(_maxEventLogSize, _DummyEvent());
    _eventStream = StreamController<Event>.broadcast();
  }

  /// Dummy event for initializing ring buffer
  static Event _DummyEvent() => Event(
        eventType: '__dummy__',
        correlationId: '',
        source: '',
        payloadJson: '{}',
      );

  @override
  Future<void> publish(Event event) async {
    // Step 1: Persist immediately
    await repository.save(event);

    // Step 2: Update ring buffer and correlation ID counts
    _eventLog[_eventLogIndex] = event;
    _eventLogIndex = (_eventLogIndex + 1) % _maxEventLogSize;

    final count = _correlationIdCounts[event.correlationId] ?? 0;
    _correlationIdCounts[event.correlationId] = count + 1;

    // Step 3: Notify listeners
    try {
      _eventStream.add(event);
      debugPrint('📤 EventBus: Published ${event.eventType}');
    } catch (e) {
      debugPrint(
          '⚠️ EventBus: Error notifying listeners for ${event.eventType}: $e');
    }
  }

  @override
  Stream<Event> subscribe() {
    return _eventStream.stream;
  }

  @override
  List<Event> getEventsByCorrelationId(String correlationId) {
    return _eventLog
        .where((e) =>
            e.eventType != '__dummy__' && e.correlationId == correlationId)
        .toList();
  }

  @override
  List<Event> getEventsByType(String eventType) {
    return _eventLog
        .where((e) => e.eventType != '__dummy__' && e.eventType == eventType)
        .toList();
  }

  @override
  List<Event> getEventsSince(DateTime timestamp) {
    return _eventLog
        .where(
            (e) => e.eventType != '__dummy__' && e.createdAt.isAfter(timestamp))
        .toList();
  }

  @override
  void clear() {
    debugPrint('🧹 EventBus: Clearing event log');
    _eventLog = List.filled(_maxEventLogSize, _DummyEvent());
    _eventLogIndex = 0;
    _correlationIdCounts.clear();
  }

  @override
  void dispose() {
    debugPrint('🛑 EventBus: Disposing');
    _eventStream.close();
    debugPrint('✅ EventBus: Disposed');
  }
}
