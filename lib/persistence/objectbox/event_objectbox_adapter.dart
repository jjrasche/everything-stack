/// # EventObjectBoxAdapter
///
/// ObjectBox adapter for Event entity persistence on native platforms.
library;

import 'package:objectbox/objectbox.dart';
import '../../core/event_repository.dart';
import '../../domain/event.dart';
import 'wrappers/event_ob.dart';

class EventObjectBoxAdapter implements EventRepository {
  final Box<EventOB> box;

  EventObjectBoxAdapter(Store store) : box = store.box<EventOB>();

  @override
  Future<void> save(Event event) async {
    final ob = _toOB(event);
    box.put(ob);
  }

  @override
  Future<void> saveBatch(List<Event> events) async {
    final obs = events.map(_toOB).toList();
    box.putMany(obs);
  }

  @override
  Future<List<Event>> getByCorrelationId(String correlationId) async {
    final obs = box
        .query(EventOB_.correlationId.equals(correlationId))
        .build()
        .find();
    return obs.map(_fromOB).toList();
  }

  @override
  Future<List<Event>> getByType(String eventType) async {
    final obs = box
        .query(EventOB_.eventType.equals(eventType))
        .build()
        .find();
    return obs.map(_fromOB).toList();
  }

  @override
  Future<List<Event>> getSince(DateTime timestamp) async {
    final obs = box
        .query(EventOB_.timestamp.greaterThan(timestamp.millisecondsSinceEpoch))
        .build()
        .find();
    return obs.map(_fromOB).toList();
  }

  @override
  Future<List<Event>> getAll() async {
    return box.getAll().map(_fromOB).toList();
  }

  @override
  Future<bool> delete(String uuid) async {
    final ob = box
        .query(EventOB_.uuid.equals(uuid))
        .build()
        .findFirst();
    if (ob != null) {
      return box.remove(ob.id) > 0;
    }
    return false;
  }

  @override
  Future<void> clear() async {
    box.removeAll();
  }

  @override
  Future<int> count() async {
    return box.count();
  }

  @override
  Future<int> countByCorrelationId(String correlationId) async {
    return box
        .query(EventOB_.correlationId.equals(correlationId))
        .build()
        .count();
  }

  // Conversion helpers
  EventOB _toOB(Event event) {
    return EventOB(
      uuid: event.uuid,
      createdAt: event.createdAt,
      updatedAt: event.updatedAt,
      syncId: event.syncId,
      eventType: event.eventType,
      correlationId: event.correlationId,
      parentEventId: event.parentEventId,
      source: event.source,
      timestamp: event.timestamp,
      payloadJson: event.payloadJson,
    );
  }

  Event _fromOB(EventOB ob) {
    final event = Event(
      eventType: ob.eventType,
      correlationId: ob.correlationId,
      source: ob.source,
      payloadJson: ob.payloadJson,
      parentEventId: ob.parentEventId,
      timestamp: ob.timestamp,
    );
    event.id = ob.id;
    event.uuid = ob.uuid;
    event.createdAt = ob.createdAt;
    event.updatedAt = ob.updatedAt;
    event.syncId = ob.syncId;
    return event;
  }
}
