import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/comms/entities/comm_event.dart';

@Entity()
class CommEventOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Source identification ============

  String sourceType;
  String sourceId;
  String? channelId;
  String? channelName;
  String? senderId;
  String? senderName;

  // ============ Content ============

  String contentText;
  String contentType;
  String? rawPayload;

  // ============ Processing state ============

  @Property(type: PropertyType.date)
  DateTime? processedAt;

  String? triageLevel;
  String? encoderTraceId;
  bool dismissed;

  // ============ Constructor ============

  CommEventOB({
    required this.sourceType,
    required this.sourceId,
    required this.contentText,
    this.contentType = 'message',
    this.dismissed = false,
  });

  // ============ Conversion ============

  factory CommEventOB.fromCommEvent(CommEvent event) {
    return CommEventOB(
      sourceType: event.sourceType,
      sourceId: event.sourceId,
      contentText: event.contentText,
      contentType: event.contentType,
      dismissed: event.dismissed,
    )
      ..id = event.id
      ..uuid = event.uuid
      ..createdAt = event.createdAt
      ..updatedAt = event.updatedAt
      ..syncId = event.syncId
      ..channelId = event.channelId
      ..channelName = event.channelName
      ..senderId = event.senderId
      ..senderName = event.senderName
      ..rawPayload = event.rawPayload
      ..processedAt = event.processedAt
      ..triageLevel = event.triageLevel
      ..encoderTraceId = event.encoderTraceId;
  }

  CommEvent toCommEvent() {
    final event = CommEvent(
      sourceType: sourceType,
      sourceId: sourceId,
      contentText: contentText,
      contentType: contentType,
      rawPayload: rawPayload,
      processedAt: processedAt,
      triageLevel: triageLevel,
      encoderTraceId: encoderTraceId,
      dismissed: dismissed,
      channelId: channelId,
      channelName: channelName,
      senderId: senderId,
      senderName: senderName,
    );
    event.id = id;
    event.uuid = uuid;
    event.createdAt = createdAt;
    event.updatedAt = updatedAt;
    event.syncId = syncId;
    return event;
  }
}
