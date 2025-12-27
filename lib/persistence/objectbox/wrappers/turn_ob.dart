/// # TurnOB - ObjectBox Wrapper

import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/turn.dart';

@Entity()
class TurnOB {
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
  String conversationId;

  @Property(type: PropertyType.date)
  DateTime timestamp = DateTime.now();

  String? sttInvocationId;
  String? llmInvocationId;
  String? ttsInvocationId;

  String result = 'success';
  String? errorMessage;
  String? failureComponent;
  int latencyMs = 0;
  bool markedForFeedback = false;

  @Property(type: PropertyType.date)
  DateTime? markedAt;

  @Property(type: PropertyType.date)
  DateTime? feedbackTrainedAt;

  TurnOB({
    required this.correlationId,
    required this.conversationId,
  });

  factory TurnOB.fromTurn(Turn turn) {
    return TurnOB(
      correlationId: turn.correlationId,
      conversationId: turn.conversationId,
    )
      ..id = turn.id
      ..uuid = turn.uuid
      ..createdAt = turn.createdAt
      ..updatedAt = turn.updatedAt
      ..syncId = turn.syncId
      ..timestamp = turn.timestamp
      ..sttInvocationId = turn.sttInvocationId
      ..llmInvocationId = turn.llmInvocationId
      ..ttsInvocationId = turn.ttsInvocationId
      ..result = turn.result
      ..errorMessage = turn.errorMessage
      ..failureComponent = turn.failureComponent
      ..latencyMs = turn.latencyMs
      ..markedForFeedback = turn.markedForFeedback
      ..markedAt = turn.markedAt
      ..feedbackTrainedAt = turn.feedbackTrainedAt;
  }

  Turn toTurn() {
    return Turn(
      correlationId: correlationId,
      conversationId: conversationId,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..timestamp = timestamp
      ..sttInvocationId = sttInvocationId
      ..llmInvocationId = llmInvocationId
      ..ttsInvocationId = ttsInvocationId
      ..result = result
      ..errorMessage = errorMessage
      ..failureComponent = failureComponent
      ..latencyMs = latencyMs
      ..markedForFeedback = markedForFeedback
      ..markedAt = markedAt
      ..feedbackTrainedAt = feedbackTrainedAt;
  }
}
