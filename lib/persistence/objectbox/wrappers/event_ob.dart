/// # EventOB - ObjectBox Wrapper

import 'package:objectbox/objectbox.dart';
import '../../domain/event.dart';

@Entity()
class EventOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  String correlationId;
  String? parentEventId;
  String source;

  @Property(type: PropertyType.date)
  DateTime timestamp = DateTime.now();

  String payloadJson = '{}';

  EventOB({
    required this.correlationId,
    required this.source,
    this.parentEventId,
    this.timestamp,
    this.payloadJson = '{}',
  });

  factory EventOB.fromEvent(Event event) {
    return EventOB(
      correlationId: event.correlationId,
      source: event.source,
      parentEventId: event.parentEventId,
      timestamp: event.timestamp,
      payloadJson: event.payloadJson ?? '{}',
    )
      ..id = event.id
      ..uuid = event.uuid
      ..createdAt = event.createdAt
      ..updatedAt = event.updatedAt
      ..syncId = event.syncId;
  }

  Event toEvent() {
    return Event(
      correlationId: correlationId,
      source: source,
      parentEventId: parentEventId,
      timestamp: timestamp,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId;
  }
}
