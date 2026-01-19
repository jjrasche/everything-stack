/// # TrialOB - ObjectBox Wrapper
///
/// ObjectBox-specific wrapper for Trial entity.
/// Contains ORM decorators (@Entity, @Id, etc.) that domain entities must not have.

import 'package:objectbox/objectbox.dart';
import '../../../core/trial.dart';

@Entity()
class TrialOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  /// Which component is being optimized?
  @Index()
  String componentType;

  /// User ID for multi-user isolation
  @Index()
  String? userId;

  /// Normalized parameters as JSON
  String paramsJson;

  /// Reward signal (-1.0 to 1.0)
  double reward;

  /// Optional metadata
  String? metadata;

  TrialOB({
    required this.componentType,
    required this.paramsJson,
    required this.reward,
    this.userId,
    this.metadata,
  });

  factory TrialOB.fromTrial(Trial trial) {
    return TrialOB(
      componentType: trial.componentType,
      paramsJson: trial.paramsJson,
      reward: trial.reward,
      userId: trial.userId,
      metadata: trial.metadata,
    )
      ..id = trial.id
      ..uuid = trial.uuid
      ..createdAt = trial.createdAt
      ..updatedAt = trial.updatedAt
      ..syncId = trial.syncId;
  }

  Trial toTrial() {
    return Trial(
      componentType: componentType,
      paramsJson: paramsJson,
      reward: reward,
      userId: userId,
      metadata: metadata,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId;
  }
}
