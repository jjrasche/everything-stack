/// # InvocationObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/invocation.dart' as domain_invocation;
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/invocation_ob.dart';

class InvocationObjectBoxAdapter extends BaseObjectBoxAdapter<domain_invocation.Invocation, InvocationOB> {
  InvocationObjectBoxAdapter(Store store) : super(store);

  @override
  InvocationOB toOB(domain_invocation.Invocation entity) => InvocationOB.fromInvocation(entity);

  @override
  domain_invocation.Invocation fromOB(InvocationOB ob) => ob.toInvocation();

  @override
  Condition<InvocationOB> uuidEqualsCondition(String uuid) =>
      InvocationOB_.uuid.equals(uuid);

  @override
  Condition<InvocationOB> syncStatusLocalCondition() =>
      InvocationOB_.syncId.notNull();
}
