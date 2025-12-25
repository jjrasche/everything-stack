/// # TurnObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../domain/turn.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/turn_ob.dart';

class TurnObjectBoxAdapter extends BaseObjectBoxAdapter<Turn, TurnOB> {
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
      TurnOB_.syncId.isNotNull();
}
