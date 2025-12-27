/// # Event
///
/// ## What it does
/// Represents a triggering event in the system.
/// Events flow through the Context Manager for processing.
///
/// ## Key Design
/// - correlationId: Links all operations in a synchronous chain
/// - parentEventId: Links async chains (e.g., timer fires hours later)
/// - source: Who triggered this event ('user', 'timer', 'system')
/// - payload: The event data (transcription, timer fire, etc.)
///
/// ## Chain Tracking
/// Synchronous chain: All operations share same correlationId
/// - User speaks → STT → Context Manager → LLM → TTS (same correlationId)
///
/// Async chain: New correlationId, linked via parentEventId
/// - Timer fires → new correlationId, parentEventId = original event
///
/// ## Usage
/// ```dart
/// // User input event
/// final event = Event(
///   correlationId: 'corr_001',
///   source: 'user',
///   payload: {'transcription': 'set a timer for 5 minutes'},
/// );
///
/// // Timer fire event (async, linked)
/// final timerEvent = Event(
///   correlationId: 'corr_002',  // New chain
///   parentEventId: 'corr_001',   // Linked to original
///   source: 'timer',
///   payload: {'timerId': 'timer_001', 'label': '5 minute timer'},
/// );
/// ```
///
/// ## Note
/// Events flow through the system, not persisted long-term for MVP.
/// ContextManagerInvocation captures the decision log.

import '../core/base_entity.dart';

class Event extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  int id = 0;

  @override
  String uuid = '';

  @override
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ Event fields ============

  /// Links all operations in this synchronous chain
  String correlationId;

  /// Links async chains (e.g., timer fires later)
  /// Null for root events (user-initiated)
  String? parentEventId;

  /// Who triggered this event: 'user', 'timer', 'system'
  String source;

  /// When this event occurred
  DateTime timestamp;

  /// Event payload (transcription, timer data, etc.) stored as JSON string
  String payloadJson;

  // ============ Constructor ============

  Event({
    required this.correlationId,
    required this.source,
    required this.payloadJson,
    this.parentEventId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now() {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'correlationId': correlationId,
        'parentEventId': parentEventId,
        'source': source,
        'timestamp': timestamp.toIso8601String(),
        'payloadJson': payloadJson,
      };

  factory Event.fromJson(Map<String, dynamic> json) {
    final event = Event(
      correlationId: json['correlationId'] as String,
      source: json['source'] as String,
      payloadJson: json['payloadJson'] as String? ?? '{}',
      parentEventId: json['parentEventId'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
    event.id = json['id'] as int? ?? 0;
    event.uuid = json['uuid'] as String? ?? '';
    event.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    event.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    event.syncId = json['syncId'] as String?;
    return event;
  }
}
