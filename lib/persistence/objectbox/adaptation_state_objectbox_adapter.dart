/// # AdaptationStateObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../domain/adaptation_state_generic.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/adaptation_state_ob.dart';

class AdaptationStateObjectBoxAdapter
    extends BaseObjectBoxAdapter<AdaptationState, AdaptationStateOB> {
  AdaptationStateObjectBoxAdapter(Store store) : super(store);

  @override
  AdaptationStateOB toOB(AdaptationState entity) =>
      AdaptationStateOB.fromAdaptationState(entity);

  @override
  AdaptationState fromOB(AdaptationStateOB ob) =>
      ob.toAdaptationState();

  @override
  Condition<AdaptationStateOB> uuidEqualsCondition(String uuid) =>
      AdaptationStateOB_.uuid.equals(uuid);

  @override
  Condition<AdaptationStateOB> syncStatusLocalCondition() =>
      AdaptationStateOB_.syncId.notNull();
}
