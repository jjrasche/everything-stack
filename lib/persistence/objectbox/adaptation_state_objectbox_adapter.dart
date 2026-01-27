/// # AdaptationStateObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../core/adaptation_state.dart';
import '../../core/adaptation_state_repository.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/adaptation_state_ob.dart';

class AdaptationStateObjectBoxAdapter
    extends BaseObjectBoxAdapter<AdaptationState, AdaptationStateOB>
    implements AdaptationStateRepository {
  AdaptationStateObjectBoxAdapter(Store store) : super(store);

  @override
  AdaptationStateOB toOB(AdaptationState entity) =>
      AdaptationStateOB.fromAdaptationState(entity);

  @override
  AdaptationState fromOB(AdaptationStateOB ob) => ob.toAdaptationState();

  @override
  Condition<AdaptationStateOB> uuidEqualsCondition(String uuid) =>
      AdaptationStateOB_.uuid.equals(uuid);

  @override
  Condition<AdaptationStateOB> syncStatusLocalCondition() =>
      AdaptationStateOB_.syncId.notNull();

  // ============ AdaptationStateRepository Implementation ============

  @override
  Future<AdaptationState?> getForComponent(
    String componentType, {
    required String? implementer,
    String? userId,
  }) async {
    // Query by (componentType, implementer, userId)
    late Condition<AdaptationStateOB> condition;

    if (userId != null) {
      // User-scoped state
      if (implementer != null) {
        condition = AdaptationStateOB_.componentType
            .equals(componentType)
            .and(AdaptationStateOB_.implementer.equals(implementer))
            .and(AdaptationStateOB_.userId.equals(userId));
      } else {
        condition = AdaptationStateOB_.componentType
            .equals(componentType)
            .and(AdaptationStateOB_.implementer.isNull())
            .and(AdaptationStateOB_.userId.equals(userId));
      }
    } else {
      // No user filtering (shouldn't happen, but handle it)
      if (implementer != null) {
        condition = AdaptationStateOB_.componentType
            .equals(componentType)
            .and(AdaptationStateOB_.implementer.equals(implementer));
      } else {
        condition = AdaptationStateOB_.componentType
            .equals(componentType)
            .and(AdaptationStateOB_.implementer.isNull());
      }
    }

    final query = box.query(condition).build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  @override
  Future<List<AdaptationState>> findByComponentAndImplementer(
    String componentType, {
    required String? implementer,
  }) async {
    late Condition<AdaptationStateOB> condition;
    if (implementer != null) {
      condition = AdaptationStateOB_.componentType
          .equals(componentType)
          .and(AdaptationStateOB_.implementer.equals(implementer));
    } else {
      condition = AdaptationStateOB_.componentType
          .equals(componentType)
          .and(AdaptationStateOB_.implementer.isNull());
    }

    final query = box.query(condition).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<bool> updateWithVersion(AdaptationState state) async {
    // Optimistic locking: only update if version matches
    final existing = await findById(state.uuid);
    if (existing == null) {
      throw Exception(
        'AdaptationState ${state.uuid} not found for version update',
      );
    }
    if (existing.version != state.version) {
      return false; // Version conflict
    }

    // Increment version and save
    state.version++;
    await save(state);
    return true;
  }

  @override
  AdaptationState createDefault(
    String componentType, {
    required String? implementer,
    String? userId,
  }) {
    return AdaptationState(
      componentType: componentType,
      implementer: implementer,
      userId: userId,
    );
  }
}
