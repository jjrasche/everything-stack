/// # EventOB - ObjectBox Wrapper

import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/event.dart';

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
  DateTime timestamp;

  // Store payload as JSON string for ObjectBox
  String payloadJson;

  EventOB({
    required this.correlationId,
    required this.source,
    required this.timestamp,
    this.parentEventId,
    this.payloadJson = '{}',
  });

  factory EventOB.fromEvent(Event event) {
    return EventOB(
      correlationId: event.correlationId,
      source: event.source,
      timestamp: event.timestamp,
      parentEventId: event.parentEventId,
      payloadJson: event.payloadJson,
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
      payloadJson: payloadJson,
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
