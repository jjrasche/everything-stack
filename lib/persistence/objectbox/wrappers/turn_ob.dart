/// # TurnOB - ObjectBox Wrapper

import 'package:objectbox/objectbox.dart';
import '../../domain/turn.dart';

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

  @Property(type: PropertyType.date)
  DateTime timestamp = DateTime.now();

  String? sttInvocationId;
  String? contextManagerInvocationId;
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

  TurnOB({required this.correlationId});

  factory TurnOB.fromTurn(Turn turn) {
    return TurnOB(correlationId: turn.correlationId)
      ..id = turn.id
      ..uuid = turn.uuid
      ..createdAt = turn.createdAt
      ..updatedAt = turn.updatedAt
      ..syncId = turn.syncId
      ..timestamp = turn.timestamp
      ..sttInvocationId = turn.sttInvocationId
      ..contextManagerInvocationId = turn.contextManagerInvocationId
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
    return Turn(correlationId: correlationId)
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..timestamp = timestamp
      ..sttInvocationId = sttInvocationId
      ..contextManagerInvocationId = contextManagerInvocationId
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
