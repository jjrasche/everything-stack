/// # EventOB - ObjectBox Wrapper

import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/patterns/ownable.dart';

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

  @Index()
  String eventType;

  @Index()
  String correlationId;

  String? parentEventId;
  String source;

  @Property(type: PropertyType.date)
  DateTime timestamp;

  // Store payload as JSON string for ObjectBox
  String payloadJson;

  // ============ Ownable fields ============
  String? ownerId;
  String? visibility; // 'private', 'shared', 'public'

  EventOB({
    required this.eventType,
    required this.correlationId,
    required this.source,
    required this.timestamp,
    this.parentEventId,
    this.payloadJson = '{}',
    this.ownerId,
    this.visibility,
  });

  factory EventOB.fromEvent(Event event) {
    return EventOB(
      eventType: event.eventType,
      correlationId: event.correlationId,
      source: event.source,
      timestamp: event.timestamp,
      parentEventId: event.parentEventId,
      payloadJson: event.payloadJson,
      ownerId: event.ownerId,
      visibility: event.visibility.toString().split('.').last,
    )
      ..id = event.id
      ..uuid = event.uuid
      ..createdAt = event.createdAt
      ..updatedAt = event.updatedAt
      ..syncId = event.syncId;
  }

  Event toEvent() {
    final event = Event(
      eventType: eventType,
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

    // Restore Ownable fields
    event.ownerId = ownerId;
    if (visibility != null) {
      event.visibility = Visibility.values.firstWhere(
        (v) => v.toString().split('.').last == visibility,
        orElse: () => Visibility.private,
      );
    }

    return event;
  }
}
