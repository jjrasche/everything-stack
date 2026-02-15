library;

import '../core/event.dart';

abstract class EventBus {
  /// Publish an event (persisted simultaneously)
  ///
  /// Event is saved to ObjectBox/IndexedDB and published to listeners.
  /// Both operations complete before returning.
  ///
  /// Callers MUST await this:
  /// ```dart
  /// await eventBus.publish(event);
  /// ```
  Future<void> publish(Event event);

  /// Subscribe to all events
  ///
  /// Returns a broadcast stream. Multiple listeners can subscribe.
  /// Filter by eventType in the listener:
  /// ```dart
  /// late StreamSubscription _sub;
  ///
  /// void initialize() {
  ///   _sub = eventBus.subscribe().listen((event) {
  ///     if (event.eventType == 'transcription_complete') {
  ///       // handle transcription
  ///     }
  ///   });
  /// }
  ///
  /// void dispose() {
  ///   _sub.cancel();
  /// }
  /// ```
  Stream<Event> subscribe();

  /// Get all events with a specific correlation ID
  ///
  /// Used for turn-level debugging and testing.
  /// Returns events in chronological order.
  List<Event> getEventsByCorrelationId(String correlationId);

  /// Get all events of a specific eventType
  ///
  /// Used for filtering events (e.g., 'transcription_complete', 'orchestration_complete').
  List<Event> getEventsByType(String eventType);

  /// Get all events since a specific time
  ///
  /// Used for monitoring and log collection.
  List<Event> getEventsSince(DateTime timestamp);

  /// Clear all events (for testing)
  ///
  /// Removes events from in-memory cache only.
  void clear();

  /// Dispose EventBus and cancel all listeners
  ///
  /// Called during app shutdown or test cleanup.
  void dispose();
}
