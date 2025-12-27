/// # AdaptationStateOB - ObjectBox Wrapper

import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/core/adaptation_state.dart';

@Entity()
class AdaptationStateOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  String componentType;
  String scope = 'global';
  String? userId;
  String dataJson = '{}';
  int version = 0;
  DateTime lastUpdatedAt = DateTime.now();
  String lastUpdateReason = '';
  int feedbackCountApplied = 0;

  AdaptationStateOB({
    required this.componentType,
    this.scope = 'global',
    this.userId,
  });

  factory AdaptationStateOB.fromAdaptationState(AdaptationState state) {
    return AdaptationStateOB(
      componentType: state.componentType,
      scope: state.scope,
      userId: state.userId,
    )
      ..id = state.id
      ..uuid = state.uuid
      ..createdAt = state.createdAt
      ..updatedAt = state.updatedAt
      ..syncId = state.syncId
      ..dataJson = state.dataJson
      ..version = state.version
      ..lastUpdatedAt = state.lastUpdatedAt
      ..lastUpdateReason = state.lastUpdateReason
      ..feedbackCountApplied = state.feedbackCountApplied;
  }

  AdaptationState toAdaptationState() {
    return AdaptationState(
      componentType: componentType,
      scope: scope,
      userId: userId,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..dataJson = dataJson
      ..version = version
      ..lastUpdatedAt = lastUpdatedAt
      ..lastUpdateReason = lastUpdateReason
      ..feedbackCountApplied = feedbackCountApplied;
  }
}
