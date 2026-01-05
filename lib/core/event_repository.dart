/// # EventRepository Interface
///
/// Persistence layer for Event entities.
/// Adapters implement this for platform-specific backends:
/// - Native (Android/iOS/macOS/Windows/Linux): ObjectBox
/// - Web: IndexedDB
///
/// Called synchronously by EventBusImpl.publish() before returning.
library;

import './event.dart';

abstract class EventRepository {
  /// Save an event to persistent storage
  ///
  /// Called from EventBusImpl.publish() synchronously.
  /// Must complete before publish() returns.
  Future<void> save(Event event);

  /// Save multiple events in batch
  Future<void> saveBatch(List<Event> events);

  /// Get all events with a specific correlation ID
  ///
  /// Returns events in chronological order (oldest first).
  Future<List<Event>> getByCorrelationId(String correlationId);

  /// Get all events of a specific type
  ///
  /// Returns events in chronological order.
  Future<List<Event>> getByType(String eventType);

  /// Get all events since a specific timestamp
  Future<List<Event>> getSince(DateTime timestamp);

  /// Get all events in storage
  Future<List<Event>> getAll();

  /// Delete event by uuid
  Future<bool> delete(String uuid);

  /// Delete all events (for testing)
  Future<void> clear();

  /// Count events in storage
  Future<int> count();

  /// Count events with a specific correlation ID
  Future<int> countByCorrelationId(String correlationId);
}
