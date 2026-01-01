/// # EventBusImpl
///
/// In-memory pub/sub with write-through persistence.
///
/// ## Architecture
/// - Maintains type registry (no dart:mirrors - not supported in Flutter)
/// - Each event type has its own BroadcastStreamController
/// - publish() is synchronous for repository save, async for listeners
/// - Maintains ring buffer of recent events (bounded memory)
/// - All StreamControllers properly disposed on cleanup
///
/// ## Write-Through Pattern
/// ```
/// publish(event) {
///   1. await repository.save(event)  // Synchronous, guaranteed
///   2. _getStream(T).add(event)      // Fire-and-forget to listeners
/// }
/// ```
///
/// This guarantees events persist even if ALL listeners fail or are absent.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'event_bus.dart';
import 'events/system_event.dart';
import 'events/transcription_complete.dart';
import 'events/error_occurred.dart';
import '../core/event_repository.dart';

class EventBusImpl implements EventBus {
  final EventRepository repository;

  // Type registry: runtime type name → StreamController
  // Used instead of dart:mirrors (not supported in Flutter)
  final Map<Type, StreamController<SystemEvent>> _streams = {};

  // Ring buffer: keep only recent events in memory (bounded)
  // Prevents unbounded memory growth in long-running apps
  late List<SystemEvent> _eventLog;
  int _eventLogIndex = 0;
  static const int _maxEventLogSize = 1000; // Ring buffer max events

  // Map of correlationId → event count (for testing)
  final Map<String, int> _correlationIdCounts = {};

  EventBusImpl({required this.repository}) {
    _eventLog = List.filled(_maxEventLogSize, _DummyEvent());
    _registerEventTypes();
  }

  /// Register known event types
  /// Required because we can't use dart:mirrors in Flutter
  void _registerEventTypes() {
    _getStream<TranscriptionComplete>();
    _getStream<ErrorOccurred>();
  }

  /// Get or create a broadcast stream for type T
  /// Lazily creates stream on first subscription
  StreamController<SystemEvent> _getStream<T extends SystemEvent>() {
    final key = T;
    if (!_streams.containsKey(key)) {
      _streams[key] = StreamController<SystemEvent>.broadcast();
      debugPrint('📡 EventBus: Created stream for $T');
    }
    return _streams[key]!;
  }

  @override
  Future<void> publish<T extends SystemEvent>(T event) async {
    try {
      // Step 1: Persist immediately (synchronous, await for guarantee)
      await repository.save(event);

      // Step 2: Update ring buffer and correlation ID counts
      _eventLog[_eventLogIndex] = event;
      _eventLogIndex = (_eventLogIndex + 1) % _maxEventLogSize;

      final count = _correlationIdCounts[event.correlationId] ?? 0;
      _correlationIdCounts[event.correlationId] = count + 1;

      // Step 3: Notify listeners (async, fire-and-forget)
      // If listeners fail, event is still persisted (Step 1)
      try {
        _getStream<T>().add(event as SystemEvent);
        debugPrint('📤 EventBus: Published ${event.eventType}');
      } catch (e) {
        debugPrint(
            '⚠️ EventBus: Error notifying listeners for ${event.eventType}: $e');
        // Don't rethrow - event is already persisted
      }
    } catch (e) {
      debugPrint('❌ EventBus: Failed to persist event: $e');
      // Still notify listeners even if persistence failed (eventual consistency)
      // This allows system to continue, though we lost the event
      try {
        _getStream<T>().add(event as SystemEvent);
      } catch (e2) {
        debugPrint('❌ EventBus: Also failed to notify listeners: $e2');
      }
    }
  }

  @override
  Stream<T> subscribe<T extends SystemEvent>() {
    return _getStream<T>().stream.cast<T>();
  }

  @override
  List<SystemEvent> getEventsByCorrelationId(String correlationId) {
    return _eventLog
        .where((e) => e != _DummyEvent() && e.correlationId == correlationId)
        .toList();
  }

  @override
  List<T> getEventsByType<T extends SystemEvent>() {
    return _eventLog
        .where((e) => e != _DummyEvent() && e.runtimeType == T)
        .cast<T>()
        .toList();
  }

  @override
  List<SystemEvent> getEventsSince(DateTime timestamp) {
    return _eventLog
        .where((e) => e != _DummyEvent() && e.createdAt.isAfter(timestamp))
        .toList();
  }

  @override
  void clear() {
    debugPrint('🧹 EventBus: Clearing event log and repository');
    _eventLog = List.filled(_maxEventLogSize, _DummyEvent());
    _eventLogIndex = 0;
    _correlationIdCounts.clear();
    repository.clear();
  }

  @override
  void dispose() {
    debugPrint('🛑 EventBus: Disposing');
    // Close all stream controllers
    for (final stream in _streams.values) {
      stream.close();
    }
    _streams.clear();
    debugPrint('✅ EventBus: Disposed');
  }

  /// Wait for a chain of events to be published and persisted
  ///
  /// Used in tests to coordinate async event flow.
  /// Waits for all expected event types to be published with same correlationId.
  ///
  /// Example:
  /// ```dart
  /// // Trigger STT
  /// await sttService.transcribe(...);
  ///
  /// // Wait for both TranscriptionComplete and LLM response
  /// await eventBus.waitForChain(
  ///   'corr_001',
  ///   [TranscriptionComplete, CoordinationComplete],
  ///   timeout: Duration(seconds: 5),
  /// );
  ///
  /// // Both events are now in repository
  /// final events = eventBus.getEventsByCorrelationId('corr_001');
  /// ```
  Future<void> waitForChain(
    String correlationId,
    List<Type> expectedEventTypes, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    final expectedSet = expectedEventTypes.toSet();
    final receivedSet = <Type>{};

    final completer = Completer<void>();

    // Subscribe to each event type
    final subscriptions = <StreamSubscription>[];

    for (final eventType in expectedEventTypes) {
      // Create subscription based on type
      if (eventType == TranscriptionComplete) {
        final sub = subscribe<TranscriptionComplete>().listen((event) {
          if (event.correlationId == correlationId) {
            receivedSet.add(TranscriptionComplete);
            if (receivedSet == expectedSet) {
              completer.complete();
            }
          }
        });
        subscriptions.add(sub);
      } else if (eventType == ErrorOccurred) {
        final sub = subscribe<ErrorOccurred>().listen((event) {
          if (event.correlationId == correlationId) {
            receivedSet.add(ErrorOccurred);
            if (receivedSet == expectedSet) {
              completer.complete();
            }
          }
        });
        subscriptions.add(sub);
      }
    }

    try {
      await completer.future.timeout(timeout);
      debugPrint(
          '✅ EventBus: waitForChain complete for $correlationId after ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint(
          '❌ EventBus: waitForChain timeout for $correlationId (received: $receivedSet, expected: $expectedSet)');
      rethrow;
    } finally {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    }
  }
}

/// Dummy event for ring buffer
/// Used as placeholder in circular buffer
class _DummyEvent extends SystemEvent {
  _DummyEvent() : super(correlationId: '');

  @override
  bool operator ==(Object other) => other is _DummyEvent;

  @override
  int get hashCode => 0;
}
