import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/invocation_repository.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../core/invocation.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/invocation_ob.dart';

class InvocationObjectBoxAdapter
    extends BaseObjectBoxAdapter<Invocation, InvocationOB>
    implements InvocationRepository<Invocation> {
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
      InvocationOB_.syncId.notNull();

  // ============ InvocationRepository Implementation ============

  @override
  Future<List<Invocation>> findByContextType(String contextType) async {
    final query =
        box.query(InvocationOB_.componentType.equals(contextType)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Invocation>> findByIds(List<String> ids) async {
    final allInvocations = await findAll();
    return allInvocations.where((inv) => ids.contains(inv.uuid)).toList();
  }
}
