/// # EventRepository
///
/// ## What it does
/// Repository for Event entities. Manages event queue with FIFO processing,
/// retry logic, and correlation tracking.
///
/// ## Usage
/// ```dart
/// final adapter = EventObjectBoxAdapter(store);  // or EventIndexedDBAdapter
/// final repo = EventRepository(adapter: adapter);
///
/// // Queue event for processing
/// final event = Event(
///   type: 'teams_webhook',
///   source: 'teams',
///   payload: {'meeting_id': 123},
/// );
/// await repo.save(event);
///
/// // Dequeue and claim next event
/// final next = await repo.dequeueAndClaim();
/// if (next != null) {
///   // Process event...
///   next.status = EventStatus.completed;
///   await repo.save(next);
/// }
///
/// // Find events ready for retry
/// final retryable = await repo.getEventsReadyForRetry();
/// ```

import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import '../persistence/objectbox/event_objectbox_adapter.dart';
import '../persistence/indexeddb/event_indexeddb_adapter.dart';
import 'event.dart';

class EventRepository extends EntityRepository<Event> {
  EventRepository({
    required PersistenceAdapter<Event> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Event Queue Operations ============

  /// Dequeue and claim next pending event (FIFO: oldest first)
  ///
  /// Atomically:
  /// 1. Find oldest pending event (by createdAt)
  /// 2. Update status to processing
  /// 3. Return claimed event
  ///
  /// Returns null if no pending events.
  ///
  /// This is the core event queue operation used by Coordinator's event loop.
  Future<Event?> dequeueAndClaim() async {
    Event? event;

    // Adapter-specific implementation for efficient queries
    if (adapter is EventObjectBoxAdapter) {
      event = await (adapter as EventObjectBoxAdapter).getFirstPending();
    } else if (adapter is EventIndexedDBAdapter) {
      event = await (adapter as EventIndexedDBAdapter).getFirstPending();
    } else {
      // Fallback: find all pending, sort by createdAt, take first
      final all = await findAll();
      final pending = all.where((e) => e.status == EventStatus.pending).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      event = pending.isNotEmpty ? pending.first : null;
    }

    if (event == null) return null;

    // Claim by updating status to processing
    event.status = EventStatus.processing;
    await save(event);

    return event;
  }

  /// Get events ready for retry (status=retrying AND nextRetryAt <= now)
  Future<List<Event>> getEventsReadyForRetry() async {
    if (adapter is EventObjectBoxAdapter) {
      return (adapter as EventObjectBoxAdapter).getEventsReadyForRetry();
    } else if (adapter is EventIndexedDBAdapter) {
      return (adapter as EventIndexedDBAdapter).getEventsReadyForRetry();
    } else {
      // Fallback: filter in memory
      final all = await findAll();
      final now = DateTime.now().millisecondsSinceEpoch;
      return all.where((e) =>
        e.status == EventStatus.retrying &&
        e.nextRetryAt != null &&
        e.nextRetryAt! <= now
      ).toList()
        ..sort((a, b) => (a.nextRetryAt ?? 0).compareTo(b.nextRetryAt ?? 0));
    }
  }

  /// Find all events in a correlation chain
  Future<List<Event>> findByCorrelationId(String correlationId) async {
    if (adapter is EventObjectBoxAdapter) {
      return (adapter as EventObjectBoxAdapter).findByCorrelationId(correlationId);
    } else if (adapter is EventIndexedDBAdapter) {
      return (adapter as EventIndexedDBAdapter).findByCorrelationId(correlationId);
    } else {
      // Fallback: filter in memory
      final all = await findAll();
      return all.where((e) => e.correlationId == correlationId).toList();
    }
  }

  /// Find event by webhook ID (for deduplication)
  ///
  /// Checks if an event with the given source and payload webhook ID already exists.
  /// Used to prevent duplicate webhook processing.
  Future<Event?> findByWebhookId(String source, String webhookId) async {
    if (adapter is EventObjectBoxAdapter) {
      return (adapter as EventObjectBoxAdapter).findByWebhookId(source, webhookId);
    } else if (adapter is EventIndexedDBAdapter) {
      return (adapter as EventIndexedDBAdapter).findByWebhookId(source, webhookId);
    } else {
      // Fallback: filter in memory
      final all = await findAll();
      try {
        return all.firstWhere((e) {
          if (e.source != source) return false;
          final id = e.payload['id'] ?? e.payload['event_id'];
          return id == webhookId;
        });
      } catch (_) {
        return null;
      }
    }
  }

  /// Count events by status
  Future<int> countByStatus(EventStatus status) async {
    if (adapter is EventObjectBoxAdapter) {
      return (adapter as EventObjectBoxAdapter).countByStatus(status);
    } else if (adapter is EventIndexedDBAdapter) {
      return (adapter as EventIndexedDBAdapter).countByStatus(status);
    } else {
      // Fallback: filter in memory
      final all = await findAll();
      return all.where((e) => e.status == status).length;
    }
  }

  // ============ Retry Logic Helpers ============

  /// Mark event as failed (exhausted retries)
  Future<void> markFailed(Event event, String errorMessage) async {
    event.status = EventStatus.failed;
    event.errorMessage = errorMessage;
    event.processedAt = DateTime.now();
    await save(event);
  }

  /// Mark event as completed
  Future<void> markCompleted(Event event) async {
    event.status = EventStatus.completed;
    event.processedAt = DateTime.now();
    event.errorMessage = null;
    await save(event);
  }

  /// Schedule event for retry
  ///
  /// Increments retry count and calculates nextRetryAt based on retry policy.
  /// Caller must provide the retry backoff calculation.
  Future<void> scheduleRetry(Event event, int nextRetryAtMs) async {
    event.retryCount++;
    event.status = EventStatus.retrying;
    event.nextRetryAt = nextRetryAtMs;
    await save(event);
  }
}
