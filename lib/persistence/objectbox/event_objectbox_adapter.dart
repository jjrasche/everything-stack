/// # EventObjectBoxAdapter
///
/// ObjectBox adapter for Event entities with event queue support.
/// Provides methods for FIFO queue processing and retry logic.

import 'package:objectbox/objectbox.dart';
import '../../domain/event.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/event_ob.dart';

class EventObjectBoxAdapter extends BaseObjectBoxAdapter<Event, EventOB> {
  EventObjectBoxAdapter(Store store) : super(store);

  @override
  EventOB toOB(Event entity) => EventOB.fromEvent(entity);

  @override
  Event fromOB(EventOB ob) => ob.toEvent();

  @override
  Condition<EventOB> uuidEqualsCondition(String uuid) =>
      EventOB_.uuid.equals(uuid);

  @override
  Condition<EventOB> syncStatusLocalCondition() =>
      EventOB_.syncId.notNull();

  // ============ Event Queue Methods ============

  /// Get next pending event (FIFO: oldest createdAt first)
  /// Returns null if no pending events
  Future<Event?> getFirstPending() async {
    try {
      final query = box.query(
        EventOB_.status.equals(EventStatus.pending.index)
      ).order(EventOB_.createdAt).build();

      try {
        final ob = query.findFirst();
        return ob != null ? fromOB(ob) : null;
      } finally {
        query.close();
      }
    } catch (e, stackTrace) {
      _translateException(e, stackTrace);
    }
  }

  /// Get events ready for retry (status=retrying AND nextRetryAt <= now)
  Future<List<Event>> getEventsReadyForRetry() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final query = box.query(
        EventOB_.status.equals(EventStatus.retrying.index) &
        EventOB_.nextRetryAt.lessOrEqual(now)
      ).order(EventOB_.nextRetryAt).build();

      try {
        final obs = query.find();
        return obs.map((ob) => fromOB(ob)).toList();
      } finally {
        query.close();
      }
    } catch (e, stackTrace) {
      _translateException(e, stackTrace);
    }
  }

  /// Get event by correlation ID
  Future<List<Event>> findByCorrelationId(String correlationId) async {
    try {
      final query = box.query(
        EventOB_.correlationId.equals(correlationId)
      ).build();

      try {
        final obs = query.find();
        return obs.map((ob) => fromOB(ob)).toList();
      } finally {
        query.close();
      }
    } catch (e, stackTrace) {
      _translateException(e, stackTrace);
    }
  }

  /// Get event by source and payload webhook ID
  /// Used for deduplication
  Future<Event?> findByWebhookId(String source, String webhookId) async {
    try {
      // Query for source match
      final query = box.query(
        EventOB_.source.equals(source)
      ).build();

      try {
        final events = query.find().map((ob) => fromOB(ob)).where((event) {
          // Check if payload contains matching webhook ID
          final id = event.payload['id'] ?? event.payload['event_id'];
          return id == webhookId;
        });

        return events.isNotEmpty ? events.first : null;
      } finally {
        query.close();
      }
    } catch (e, stackTrace) {
      _translateException(e, stackTrace);
    }
  }

  /// Count events by status
  Future<int> countByStatus(EventStatus status) async {
    try {
      final query = box.query(
        EventOB_.status.equals(status.index)
      ).build();

      try {
        return query.count();
      } finally {
        query.close();
      }
    } catch (e, stackTrace) {
      _translateException(e, stackTrace);
    }
  }
}
