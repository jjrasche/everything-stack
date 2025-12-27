/// # EventIndexedDBAdapter
///
/// IndexedDB adapter for Event entities with event queue support.
/// Provides methods for FIFO queue processing and retry logic.

import 'package:idb_shim/idb.dart';
import '../../domain/event.dart' as domain_event;
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class EventIndexedDBAdapter extends BaseIndexedDBAdapter<domain_event.Event> {
  EventIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.events;

  @override
  domain_event.Event fromJson(Map<String, dynamic> json) => domain_event.Event.fromJson(json);

  // ============ Event Queue Methods ============

  /// Get next pending event (FIFO: oldest createdAt first)
  /// Returns null if no pending events
  Future<domain_event.Event?> getFirstPending() async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);

    // IndexedDB doesn't have compound filtering, so we scan and filter
    final cursor = store.openCursor(autoAdvance: true);
    domain_event.Event? oldest;

    await for (final record in cursor) {
      final json = record.value as Map<String, dynamic>;
      final event = fromJson(json);

      // Filter by status
      if (event.status == domain_event.EventStatus.pending) {
        // Track oldest by createdAt
        if (oldest == null || event.createdAt.isBefore(oldest.createdAt)) {
          oldest = event;
        }
      }
    }

    return oldest;
  }

  /// Get events ready for retry (status=retrying AND nextRetryAt <= now)
  Future<List<domain_event.Event>> getEventsReadyForRetry() async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);
    final now = DateTime.now().millisecondsSinceEpoch;

    final results = <domain_event.Event>[];
    final cursor = store.openCursor(autoAdvance: true);

    await for (final record in cursor) {
      final json = record.value as Map<String, dynamic>;
      final event = fromJson(json);

      // Filter: status=retrying AND nextRetryAt <= now
      if (event.status == domain_event.EventStatus.retrying &&
          event.nextRetryAt != null &&
          event.nextRetryAt! <= now) {
        results.add(event);
      }
    }

    // Sort by nextRetryAt (earliest first)
    results.sort((a, b) => (a.nextRetryAt ?? 0).compareTo(b.nextRetryAt ?? 0));

    return results;
  }

  /// Get event by correlation ID
  Future<List<domain_event.Event>> findByCorrelationId(String correlationId) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);

    // Use correlationId index if available, else scan
    try {
      final index = store.index(Indexes.eventsCorrelationId);
      final results = <domain_event.Event>[];
      final cursor = index.openCursor(key: correlationId, autoAdvance: true);

      await for (final record in cursor) {
        final json = record.value as Map<String, dynamic>;
        results.add(fromJson(json));
      }

      return results;
    } catch (_) {
      // Fallback: full table scan if index missing
      final results = <domain_event.Event>[];
      final cursor = store.openCursor(autoAdvance: true);

      await for (final record in cursor) {
        final json = record.value as Map<String, dynamic>;
        final event = fromJson(json);
        if (event.correlationId == correlationId) {
          results.add(event);
        }
      }

      return results;
    }
  }

  /// Get event by source and payload webhook ID
  /// Used for deduplication
  Future<domain_event.Event?> findByWebhookId(String source, String webhookId) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);

    // Full table scan with filtering
    final cursor = store.openCursor(autoAdvance: true);

    await for (final record in cursor) {
      final json = record.value as Map<String, dynamic>;
      final event = fromJson(json);

      // Filter by source
      if (event.source == source) {
        // Check payload for webhook ID
        final id = event.payload['id'] ?? event.payload['event_id'];
        if (id == webhookId) {
          return event;
        }
      }
    }

    return null;
  }

  /// Count events by status
  Future<int> countByStatus(domain_event.EventStatus status) async {
    final txn = db.transaction(objectStoreName, idbModeReadOnly);
    final store = txn.objectStore(objectStoreName);

    // Full table scan with counting
    int count = 0;
    final cursor = store.openCursor(autoAdvance: true);

    await for (final record in cursor) {
      final json = record.value as Map<String, dynamic>;
      final event = fromJson(json);

      if (event.status == status) {
        count++;
      }
    }

    return count;
  }
}
