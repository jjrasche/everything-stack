/// # EventBus Interface
///
/// Pub/sub event coordination for the Everything Stack.
///
/// ## Design: Simultaneous Persistence & Publication
/// Every Event is:
/// 1. Published to EventBus listeners immediately
/// 2. Persisted to ObjectBox/IndexedDB simultaneously
///
/// Both operations complete before publish() returns.
///
/// ## Usage
/// ```dart
/// // Publish an event (persisted simultaneously)
/// final event = Event(
///   eventType: 'transcription_complete',
///   correlationId: 'corr_001',
///   source: 'stt',
///   payloadJson: '{"transcript":"hello world","confidence":0.95}',
/// );
/// await eventBus.publish(event);
///
/// // Subscribe to all events and filter by eventType
/// eventBus.subscribe().listen((event) {
///   if (event.eventType == 'transcription_complete') {
///     print('Heard transcription');
///   }
/// });
///
/// // Query events by correlation ID (for testing)
/// final events = eventBus.getEventsByCorrelationId('corr_001');
/// print('Events in turn: ${events.length}');
/// ```
library;

import '../domain/event.dart';

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
