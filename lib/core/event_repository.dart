/// # EventRepository Interface
///
/// Persistence layer for SystemEvents.
/// Adapters implement this for platform-specific backends:
/// - Native (Android/iOS/macOS/Windows/Linux): ObjectBox
/// - Web: IndexedDB
///
/// ## Write-Through Pattern
/// EventBusImpl calls save() before publishing to listeners.
/// This guarantees events persist even if listeners fail.
///
/// ## Querying
/// - Query by correlationId: getByCorrelationId(id)
/// - Query by event type: getByType(T)
/// - Query by timestamp range: getSince(timestamp)
/// - Query all: getAll()
library;

import '../services/events/system_event.dart';

abstract class EventRepository {
  /// Save an event to persistent storage
  ///
  /// Should complete synchronously or very quickly.
  /// Called from EventBusImpl.publish() before notifying listeners.
  /// If this throws, the publish() call will rethrow (fail fast).
  Future<void> save(SystemEvent event);

  /// Save multiple events in batch
  ///
  /// Used for testing and bulk operations.
  Future<void> saveBatch(List<SystemEvent> events);

  /// Get all events with a specific correlation ID
  ///
  /// Returns events in chronological order (oldest first).
  Future<List<SystemEvent>> getByCorrelationId(String correlationId);

  /// Get all events of a specific type
  ///
  /// Generic type T must be a concrete SystemEvent subclass.
  /// Returns events in chronological order.
  Future<List<T>> getByType<T extends SystemEvent>();

  /// Get all events since a specific timestamp
  ///
  /// Used for monitoring (e.g., "show last hour of events").
  Future<List<SystemEvent>> getSince(DateTime timestamp);

  /// Get all events in storage
  ///
  /// Use sparingly - large systems may have many events.
  Future<List<SystemEvent>> getAll();

  /// Delete event by ID/UUID
  ///
  /// Individual deletion (rarely used - prefer clear for tests).
  Future<bool> delete(String eventId);

  /// Delete all events (for testing)
  ///
  /// Clears repository completely.
  Future<void> clear();

  /// Count events in storage
  ///
  /// Used for monitoring (e.g., "database has 50K events").
  Future<int> count();

  /// Count events with a specific correlation ID
  ///
  /// Used for turn-level diagnostics.
  Future<int> countByCorrelationId(String correlationId);
}
