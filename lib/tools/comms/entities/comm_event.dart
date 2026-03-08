
import '../../../core/base_entity.dart';

/// An incoming communication event from an external source.
///
/// Source-agnostic: Teams message, GitLab pipeline, Jira update, SMS —
/// all become CommEvents. The contentText feeds the encoder pipeline
/// for knowledge extraction and triage classification.
class CommEvent extends BaseEntity {
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

  // ============ Source identification ============

  /// Origin service: 'teams', 'gitlab', 'jira', 'sms', 'email'
  String sourceType;

  /// External ID from the source system (message ID, pipeline ID, etc.)
  String sourceId;

  /// External channel/room/project identifier
  String? channelId;

  /// Human-readable channel name
  String? channelName;

  /// External user ID of the sender
  String? senderId;

  /// Human-readable sender name
  String? senderName;

  // ============ Content ============

  /// The actual text content to process through the encoder
  String contentText;

  /// Content category: 'message', 'mention', 'pipeline_status', 'ticket_update'
  String contentType;

  /// Full JSON payload from the webhook for re-processing
  String? rawPayload;

  // ============ Processing state ============

  /// When the encoder processed this event (null = unprocessed)
  DateTime? processedAt;

  /// Triage classification: 'noise', 'fyi', 'attention' (null = untriaged)
  String? triageLevel;

  /// UUID linking to the encoder trace for this event
  String? encoderTraceId;

  /// Whether the user dismissed this notification
  bool dismissed;

  // ============ Constructor ============

  CommEvent({
    required this.sourceType,
    required this.sourceId,
    required this.contentText,
    this.channelId,
    this.channelName,
    this.senderId,
    this.senderName,
    this.contentType = 'message',
    this.rawPayload,
    this.processedAt,
    this.triageLevel,
    this.encoderTraceId,
    this.dismissed = false,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Computed properties ============

  bool get isProcessed => processedAt != null;

  bool get isDismissed => dismissed;

  bool get isActionable =>
      triageLevel == 'attention' && !dismissed;

  /// Extract the text for encoder pipeline input.
  String toEncoderSourceText() => contentText;

  // ============ Actions ============

  void markProcessed({required String triageLevel}) {
    processedAt = DateTime.now();
    this.triageLevel = triageLevel;
    touch();
  }

  void dismiss() {
    dismissed = true;
    touch();
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'channelId': channelId,
        'channelName': channelName,
        'senderId': senderId,
        'senderName': senderName,
        'contentText': contentText,
        'contentType': contentType,
        'rawPayload': rawPayload,
        'processedAt': processedAt?.toIso8601String(),
        'triageLevel': triageLevel,
        'encoderTraceId': encoderTraceId,
        'dismissed': dismissed,
      };

  factory CommEvent.fromJson(Map<String, dynamic> json) {
    final event = CommEvent(
      sourceType: json['sourceType'] as String,
      sourceId: json['sourceId'] as String,
      contentText: json['contentText'] as String,
      channelId: json['channelId'] as String?,
      channelName: json['channelName'] as String?,
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String?,
      contentType: json['contentType'] as String? ?? 'message',
      rawPayload: json['rawPayload'] as String?,
      processedAt: json['processedAt'] != null
          ? DateTime.parse(json['processedAt'] as String)
          : null,
      triageLevel: json['triageLevel'] as String?,
      encoderTraceId: json['encoderTraceId'] as String?,
      dismissed: json['dismissed'] as bool? ?? false,
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
