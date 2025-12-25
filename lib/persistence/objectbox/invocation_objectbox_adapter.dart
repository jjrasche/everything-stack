/// # InvocationObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/invocation.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/invocation_ob.dart';

class InvocationObjectBoxAdapter extends BaseObjectBoxAdapter<Invocation, InvocationOB> {
  InvocationObjectBoxAdapter(Store store) : super(store);

  @override
  InvocationOB toOB(Invocation entity) => InvocationOB.fromInvocation(entity);

  @override
  Invocation fromOB(InvocationOB ob) => ob.toInvocation();

  @override
  Condition<InvocationOB> uuidEqualsCondition(String uuid) =>
      InvocationOB_.uuid.equals(uuid);

  @override
  Condition<InvocationOB> syncStatusLocalCondition() =>
      InvocationOB_.syncId.isNotNull();
}
