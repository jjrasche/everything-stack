/// # InvocationObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../core/base_entity.dart';
import '../../core/invocation_repository.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/invocation.dart' as domain_invocation;
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/invocation_ob.dart';

class InvocationObjectBoxAdapter
    extends BaseObjectBoxAdapter<domain_invocation.Invocation, InvocationOB>
    implements InvocationRepository<domain_invocation.Invocation> {
  InvocationObjectBoxAdapter(Store store) : super(store);

  @override
  InvocationOB toOB(domain_invocation.Invocation entity) =>
      InvocationOB.fromInvocation(entity);

  @override
  domain_invocation.Invocation fromOB(InvocationOB ob) => ob.toInvocation();

  @override
  Condition<InvocationOB> uuidEqualsCondition(String uuid) =>
      InvocationOB_.uuid.equals(uuid);

  @override
  Condition<InvocationOB> syncStatusLocalCondition() =>
      InvocationOB_.syncId.notNull();

  // ============ InvocationRepository Implementation ============

  @override
  Future<List<domain_invocation.Invocation>> findByTurn(String turnId) async {
    final query = box
        .query(InvocationOB_.turnId.equals(turnId))
        .order(InvocationOB_.createdAt)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<domain_invocation.Invocation>> findByContextType(
      String contextType) async {
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
  Future<List<domain_invocation.Invocation>> findByIds(List<String> ids) async {
    final allInvocations = await findAll();
    return allInvocations.where((inv) => ids.contains(inv.uuid)).toList();
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final query = box.query(InvocationOB_.turnId.equals(turnId)).build();
    try {
      return query.remove();
    } finally {
      query.close();
    }
  }
}
