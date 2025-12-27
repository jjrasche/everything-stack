/// # Event
///
/// ## What it does
/// Represents a triggering event in the system that requires processing.
/// Events flow through the Coordinator's event queue for processing.
///
/// ## Event Types
/// - 'voice': User voice input (processed immediately, skips queue)
/// - 'tts': Text-to-speech request (queued for serialization)
/// - '{provider}_webhook': External webhook (teams_webhook, gitlab_webhook, etc.)
/// - 'create_task': Spawned event from tool processing
/// - 'timer_fire': Timer expiration event
///
/// ## Event Lifecycle
/// 1. Created (status: pending)
/// 2. Queued in EventRepository
/// 3. Claimed by Coordinator (status: processing)
/// 4. Processed by tool/handler
/// 5. Completed (status: completed) OR Failed (status: failed)
/// 6. If failed: retry based on retryPolicy
///
/// ## Correlation Chain
/// - Root event: correlationId = null
/// - Spawned event: correlationId = parent_event.uuid
/// - Invocations: correlationId = event.uuid (what triggered them)
///
/// ## Usage
/// ```dart
/// // Root webhook event
/// final event = Event(
///   correlationId: null,  // No parent
///   type: 'teams_webhook',
///   source: 'teams',
///   payload: {'meeting_id': 123, 'title': 'Q4 Planning'},
///   retryPolicy: RetryPolicy.exponentialBackoff,
///   maxRetries: 3,
/// );
/// await eventRepo.save(event);
///
/// // Spawned TTS event
/// final ttsEvent = Event(
///   correlationId: event.uuid,  // Links to parent
///   type: 'tts',
///   source: 'teams_tool',
///   payload: {'text': 'Meeting scheduled'},
/// );
/// await eventRepo.save(ttsEvent);
/// ```

import '../core/base_entity.dart';

/// Event processing status
enum EventStatus {
  pending,      // Not yet processed
  processing,   // Currently being processed
  completed,    // Successfully processed
  failed,       // Failed and exhausted retries
  retrying,     // Failed but will retry
}

/// Retry policy for failed events
enum RetryPolicy {
  none,                   // No retries
  exponentialBackoff,     // 1s, 10s, 100s (capped at 5min)
  linearBackoff,          // 1s, 2s, 3s (capped at 5min)
}

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

  // ============ Event Identity ============

  /// Links to parent event (for spawned events)
  /// Root events have correlationId = null
  /// Spawned events have correlationId = parent_event.uuid
  String? correlationId;

  /// Event type ('voice', 'tts', 'teams_webhook', 'create_task', etc.)
  String type;

  /// Event source (who created this: 'teams', 'gitlab', 'voice', 'teams_tool', etc.)
  String source;

  // ============ Event Payload (JSON storage) ============

  /// Event payload (stored as JSON)
  Map<String, dynamic> payload;

  /// JSON string storage for payload (persistence)
  String? payloadJson;

  // ============ Processing State ============

  /// Current processing status
  EventStatus status;

  /// Number of retry attempts
  int retryCount;

  /// Retry strategy
  RetryPolicy retryPolicy;

  /// Maximum retry attempts before marking as failed
  int maxRetries;

  /// Unix timestamp for next retry (null if not retrying)
  int? nextRetryAt;

  /// When processing completed (null until done)
  DateTime? processedAt;

  /// Error message if status = failed
  String? errorMessage;

  /// Target device ID (for multi-device routing)
  /// null = all devices, 'broadcast' = all devices, specific ID = one device
  String? targetDeviceId;

  // ============ Constructor ============

  Event({
    required this.type,
    required this.source,
    required this.payload,
    this.correlationId,
    this.status = EventStatus.pending,
    this.retryCount = 0,
    this.retryPolicy = RetryPolicy.exponentialBackoff,
    this.maxRetries = 3,
    this.nextRetryAt,
    this.processedAt,
    this.errorMessage,
    this.targetDeviceId,
  }) {
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
        'type': type,
        'source': source,
        'payload': payload,
        'status': status.name,
        'retryCount': retryCount,
        'retryPolicy': retryPolicy.name,
        'maxRetries': maxRetries,
        'nextRetryAt': nextRetryAt,
        'processedAt': processedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'targetDeviceId': targetDeviceId,
      };

  factory Event.fromJson(Map<String, dynamic> json) {
    final event = Event(
      type: json['type'] as String,
      source: json['source'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      correlationId: json['correlationId'] as String?,
      status: EventStatus.values.byName(json['status'] as String? ?? 'pending'),
      retryCount: json['retryCount'] as int? ?? 0,
      retryPolicy: RetryPolicy.values.byName(
        json['retryPolicy'] as String? ?? 'exponentialBackoff',
      ),
      maxRetries: json['maxRetries'] as int? ?? 3,
      nextRetryAt: json['nextRetryAt'] as int?,
      processedAt: json['processedAt'] != null
          ? DateTime.parse(json['processedAt'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
      targetDeviceId: json['targetDeviceId'] as String?,
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
