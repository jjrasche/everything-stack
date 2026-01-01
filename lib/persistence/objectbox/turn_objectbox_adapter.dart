/// # TurnObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../core/turn_repository.dart';
import '../../domain/turn.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/turn_ob.dart';

class TurnObjectBoxAdapter extends BaseObjectBoxAdapter<Turn, TurnOB>
    implements TurnRepository {
  TurnObjectBoxAdapter(Store store) : super(store);

  @override
  TurnOB toOB(Turn entity) => TurnOB.fromTurn(entity);

  @override
  Turn fromOB(TurnOB ob) => ob.toTurn();

  @override
  Condition<TurnOB> uuidEqualsCondition(String uuid) =>
      TurnOB_.uuid.equals(uuid);

  @override
  Condition<TurnOB> syncStatusLocalCondition() =>
      TurnOB_.syncId.notNull();

  // ============ TurnRepository Implementation ============

  @override
  Future<List<Turn>> findByConversation(String conversationId) async {
    final query = box
        .query(TurnOB_.conversationId.equals(conversationId))
        .order(TurnOB_.createdAt)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Turn>> findMarkedForFeedbackByConversation(
      String conversationId) async {
    final query = box
        .query(TurnOB_.conversationId.equals(conversationId)
            .and(TurnOB_.markedForFeedback.equals(true)))
        .order(TurnOB_.markedAt, flags: Order.descending)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<Turn?> findByInvocationId(String invocationId) async {
    final allTurns = await findAll();
    return allTurns.firstWhere(
      (turn) =>
          turn.getInvocationIds().contains(invocationId),
      orElse: () => null as dynamic,
    ) as Turn?;
  }

  @override
  Future<int> deleteByConversation(String conversationId) async {
    final query = box.query(TurnOB_.conversationId.equals(conversationId)).build();
    try {
      return query.remove();
    } finally {
      query.close();
    }
  }
}
