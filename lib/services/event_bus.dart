/// # EventBus Interface
///
/// Pub/sub event coordination for the Everything Stack.
///
/// ## Design: Write-Through Persistence
/// Every event is:
/// 1. Persisted to EventRepository immediately (synchronous, guaranteed)
/// 2. Published to listeners asynchronously (fire-and-forget)
///
/// This ensures events are NEVER LOST even if listeners fail.
///
/// ## Usage
/// ```dart
/// // Publish an event (persisted immediately)
/// eventBus.publish(TranscriptionComplete(
///   correlationId: 'corr_001',
///   transcript: 'hello world',
///   durationMs: 2500,
///   confidence: 0.95,
/// ));
///
/// // Subscribe to events of a type
/// eventBus.subscribe<TranscriptionComplete>().listen((event) {
///   print('Heard transcription: ${event.transcript}');
/// });
///
/// // Query events by correlation ID (for testing)
/// final events = eventBus.getEventsByCorrelationId('corr_001');
/// print('Events in turn: ${events.length}');
/// ```
library;

import 'events/system_event.dart';

abstract class EventBus {
  /// Publish an event
  ///
  /// Async: persists to repository first (guaranteed)
  /// Then notifies listeners (fire-and-forget)
  ///
  /// Event is guaranteed to persist even if all listeners fail.
  ///
  /// Callers MUST await this for write-through guarantee:
  /// ```dart
  /// await eventBus.publish(event);  // Waits for persistence
  /// ```
  Future<void> publish<T extends SystemEvent>(T event);

  /// Subscribe to events of type T
  ///
  /// Returns a broadcast stream. Multiple listeners can subscribe.
  /// Listeners receive events published after subscription.
  ///
  /// Remember to cancel subscription to avoid memory leaks:
  /// ```dart
  /// late StreamSubscription _sub;
  ///
  /// void initialize() {
  ///   _sub = eventBus.subscribe<TranscriptionComplete>().listen(...);
  /// }
  ///
  /// void dispose() {
  ///   _sub.cancel();
  /// }
  /// ```
  Stream<T> subscribe<T extends SystemEvent>();

  /// Get all events with a specific correlation ID
  ///
  /// Used for turn-level debugging and testing.
  /// Returns events in chronological order.
  List<SystemEvent> getEventsByCorrelationId(String correlationId);

  /// Get all events of a specific type
  ///
  /// Used for filtering events by source (STT, Coordinator, etc).
  List<T> getEventsByType<T extends SystemEvent>();

  /// Get all events since a specific time
  ///
  /// Used for monitoring and log collection.
  List<SystemEvent> getEventsSince(DateTime timestamp);

  /// Clear all events (for testing)
  ///
  /// Removes events from both repository and in-memory cache.
  void clear();

  /// Dispose EventBus and cancel all listeners
  ///
  /// Called during app shutdown or test cleanup.
  void dispose();
}
