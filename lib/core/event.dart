/// Represents a triggering event in the system.
///
/// ## Why two ID fields for chain tracking
/// **correlationId** groups related events in a synchronous pipeline chain
/// (User speaks -> STT -> Context Manager -> LLM -> TTS all share one correlationId).
/// **parentEventId** links async chains (e.g., timer fires hours later with new
/// correlationId, linked back via parentEventId).

import 'dart:convert';
import '../core/base_entity.dart';
import '../patterns/ownable.dart';

class Event extends BaseEntity with Ownable {
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

  /// Event type identifier: 'transcription_complete', 'orchestration_complete', etc.
  String eventType;

  /// Links all operations in this synchronous chain
  String correlationId;

  /// Links async chains (e.g., timer fires later)
  /// Null for root events (user-initiated)
  String? parentEventId;

  /// Who triggered this event: 'user', 'timer', 'system'
  String source;

  /// When this event occurred
  DateTime timestamp;

  /// Typed event payload stored as JSON string
  /// Structure depends on eventType
  String payloadJson;

  // ============ Constructor ============

  Event({
    required this.eventType,
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
        'eventType': eventType,
        'correlationId': correlationId,
        'parentEventId': parentEventId,
        'source': source,
        'timestamp': timestamp.toIso8601String(),
        'payloadJson': payloadJson,
      };

  factory Event.fromJson(Map<String, dynamic> json) {
    final event = Event(
      eventType: json['eventType'] as String,
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

  // ============ Semantic Input ============

  /// Extract the semantic input text that drives the pipeline.
  /// Different event types contain the input in different payload fields.
  /// Used by ExecutionLoop to orchestrate processing.
  String toInputString() {
    try {
      final payload = jsonDecode(payloadJson);
      switch (eventType) {
        case 'transcription_complete':
          return payload['transcript'] as String? ?? '';
        case 'text_input':
          return payload['text'] as String? ?? '';
        case 'clipboard_paste':
          return payload['pastedText'] as String? ?? '';
        case 'voice_command':
          return payload['command'] as String? ?? '';
        default:
          return '';
      }
    } catch (e) {
      return '';
    }
  }

  // ============ UI Display ============

  /// Format event for UI display.
  /// Different from toInputString() - this is the human-readable representation
  /// shown to the user, which may include metadata, timestamps, or status.
  String getDisplayString() {
    try {
      final payload = jsonDecode(payloadJson);
      switch (eventType) {
        case 'transcription_complete':
          final transcript = payload['transcript'] as String? ?? '';
          final confidence = payload['confidence'] as num? ?? 0;
          return '$transcript (${(confidence * 100).toStringAsFixed(0)}% confidence)';

        case 'orchestration_complete':
          final response = payload['response'] as String? ?? '';
          final success = payload['success'] as bool? ?? false;
          return success
              ? response
              : '❌ ${payload["errorMessage"] ?? "Processing failed"}';

        case 'text_input':
          return payload['text'] as String? ?? '';

        case 'clipboard_paste':
          final text = payload['pastedText'] as String? ?? '';
          return text.length > 100 ? '${text.substring(0, 100)}...' : text;

        default:
          return '[$eventType] Event';
      }
    } catch (e) {
      return '[$eventType] Event';
    }
  }

  // ============ Typed Accessors ============

  /// Get response text from orchestration_complete events.
  /// Returns null for other event types.
  String? getResponse() {
    if (eventType != 'orchestration_complete') return null;
    try {
      final payload = jsonDecode(payloadJson);
      return payload['response'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get success flag from orchestration_complete events.
  /// Returns null for other event types.
  bool? getSuccess() {
    if (eventType != 'orchestration_complete') return null;
    try {
      final payload = jsonDecode(payloadJson);
      return payload['success'] as bool?;
    } catch (e) {
      return null;
    }
  }

  /// Get error message from orchestration_error or orchestration_complete (failure) events.
  /// Returns null if no error information available.
  String? getErrorMessage() {
    try {
      final payload = jsonDecode(payloadJson);
      if (eventType == 'orchestration_error') {
        return payload['message'] as String?;
      } else if (eventType == 'orchestration_complete') {
        return payload['errorMessage'] as String?;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
