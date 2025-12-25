/// # FeedbackOB - ObjectBox Wrapper

import 'package:objectbox/objectbox.dart';
import '../../domain/feedback.dart';

@Entity()
class FeedbackOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  String invocationId;
  String componentType;
  String? turnId;
  int actionIndex = 0; // Enum stored as int
  String? correctedData;
  String? reason;

  @Property(type: PropertyType.date)
  DateTime timestamp = DateTime.now();

  FeedbackOB({
    required this.invocationId,
    required this.componentType,
    required this.actionIndex,
    this.turnId,
    this.correctedData,
    this.reason,
  });

  factory FeedbackOB.fromFeedback(Feedback feedback) {
    return FeedbackOB(
      invocationId: feedback.invocationId,
      componentType: feedback.componentType,
      actionIndex: feedback.action.index,
      turnId: feedback.turnId,
      correctedData: feedback.correctedData,
      reason: feedback.reason,
    )
      ..id = feedback.id
      ..uuid = feedback.uuid
      ..createdAt = feedback.createdAt
      ..updatedAt = feedback.updatedAt
      ..syncId = feedback.syncId
      ..timestamp = feedback.timestamp;
  }

  Feedback toFeedback() {
    return Feedback(
      invocationId: invocationId,
      componentType: componentType,
      action: FeedbackAction.values[actionIndex],
      turnId: turnId,
      correctedData: correctedData,
      reason: reason,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..timestamp = timestamp;
  }
}
