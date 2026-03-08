
import 'dart:async';
import 'dart:convert';
import 'entities/comm_event.dart';
import 'repositories/comm_event_repository.dart';

/// Parses webhook payloads into CommEvents, persists them, and publishes
/// to a stream for downstream processing (encoder, triage).
class CommIngestionService {
  final CommEventRepository _repository;
  final _controller = StreamController<CommEvent>.broadcast();

  CommIngestionService({required CommEventRepository repository})
      : _repository = repository;

  Stream<CommEvent> get events => _controller.stream;

  /// Parse a webhook payload, persist the CommEvent, publish to stream.
  Future<CommEvent> ingest(Map<String, dynamic> payload) async {
    _validatePayload(payload);
    final event = _parsePayload(payload);
    await _persist(event);
    _publish(event);
    return event;
  }

  void dispose() {
    _controller.close();
  }

  // ============ Private ============

  void _validatePayload(Map<String, dynamic> payload) {
    final missing = <String>[];
    if (payload['source_type'] == null) missing.add('source_type');
    if (payload['source_id'] == null) missing.add('source_id');
    if (payload['content_text'] == null) missing.add('content_text');
    if (missing.isNotEmpty) {
      throw ArgumentError('Missing required fields: ${missing.join(', ')}');
    }
  }

  CommEvent _parsePayload(Map<String, dynamic> payload) {
    return CommEvent(
      sourceType: payload['source_type'] as String,
      sourceId: payload['source_id'] as String,
      contentText: payload['content_text'] as String,
      channelId: payload['channel_id'] as String?,
      channelName: payload['channel_name'] as String?,
      senderId: payload['sender_id'] as String?,
      senderName: payload['sender_name'] as String?,
      contentType: payload['content_type'] as String? ?? 'message',
      rawPayload: jsonEncode(payload),
    );
  }

  Future<void> _persist(CommEvent event) async {
    await _repository.save(event);
  }

  void _publish(CommEvent event) {
    _controller.add(event);
  }
}
