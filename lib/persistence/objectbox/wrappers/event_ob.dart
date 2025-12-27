/// # EventOB - ObjectBox Wrapper
///
/// ObjectBox-decorated version of Event domain entity.
/// Contains all ObjectBox decorators (@Entity, @Id, @Property, etc.)
///
/// ## Pattern
/// Domain Event stays clean (no ORM annotations).
/// EventOB contains all ObjectBox-specific annotations.
/// Adapter handles conversion automatically.

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

  // ============ Event-specific fields ============

  /// Links to parent event (null for root events)
  String? correlationId;

  /// Event type ('voice', 'tts', 'teams_webhook', etc.)
  String type;

  /// Event source ('teams', 'gitlab', 'voice', etc.)
  String source;

  /// Event payload stored as JSON
  String? payloadJson;

  /// Processing status (stored as int enum index)
  @Property(type: PropertyType.byte)
  int status;

  /// Number of retry attempts
  int retryCount;

  /// Retry policy (stored as int enum index)
  @Property(type: PropertyType.byte)
  int retryPolicy;

  /// Maximum retry attempts
  int maxRetries;

  /// Unix timestamp for next retry (null if not retrying)
  int? nextRetryAt;

  /// When processing completed
  @Property(type: PropertyType.date)
  DateTime? processedAt;

  /// Error message if failed
  String? errorMessage;

  /// Target device ID for routing
  String? targetDeviceId;

  // ============ Constructor ============

  EventOB({
    required this.type,
    required this.source,
    this.correlationId,
    this.payloadJson,
    required this.status,
    required this.retryCount,
    required this.retryPolicy,
    required this.maxRetries,
    this.nextRetryAt,
    this.processedAt,
    this.errorMessage,
    this.targetDeviceId,
  });

  // ============ Conversion Methods ============

  /// Convert from domain Event to ObjectBox wrapper
  factory EventOB.fromEvent(Event event) {
    return EventOB(
      type: event.type,
      source: event.source,
      correlationId: event.correlationId,
      payloadJson: jsonEncode(event.payload),
      status: event.status.index,
      retryCount: event.retryCount,
      retryPolicy: event.retryPolicy.index,
      maxRetries: event.maxRetries,
      nextRetryAt: event.nextRetryAt,
      processedAt: event.processedAt,
      errorMessage: event.errorMessage,
      targetDeviceId: event.targetDeviceId,
    )
      ..id = event.id
      ..uuid = event.uuid
      ..createdAt = event.createdAt
      ..updatedAt = event.updatedAt
      ..syncId = event.syncId;
  }

  /// Convert from ObjectBox wrapper back to domain Event
  Event toEvent() {
    return Event(
      type: type,
      source: source,
      payload: payloadJson != null
          ? Map<String, dynamic>.from(jsonDecode(payloadJson!) as Map)
          : {},
      correlationId: correlationId,
      status: EventStatus.values[status],
      retryCount: retryCount,
      retryPolicy: RetryPolicy.values[retryPolicy],
      maxRetries: maxRetries,
      nextRetryAt: nextRetryAt,
      processedAt: processedAt,
      errorMessage: errorMessage,
      targetDeviceId: targetDeviceId,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..payloadJson = payloadJson;
  }
}
