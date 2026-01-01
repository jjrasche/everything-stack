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
  Future<AdaptationState> getForComponent(
    String componentType, {
    String? userId,
  }) async {
    // Try user-scoped first if userId provided
    if (userId != null) {
      final userState = await getUserState(componentType, userId);
      if (userState != null) return userState;
    }

    // Fall back to global
    final globalState = await getGlobal(componentType);
    if (globalState != null) return globalState;

    // Create default
    return createDefault(componentType, userId: userId);
  }

  @override
  Future<AdaptationState?> getUserState(
    String componentType,
    String userId,
  ) async {
    final query = box
        .query(AdaptationStateOB_.componentType
            .equals(componentType)
            .and(AdaptationStateOB_.scope.equals('user'))
            .and(AdaptationStateOB_.userId.equals(userId)))
        .build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  @override
  Future<AdaptationState?> getGlobal(String componentType) async {
    final query = box
        .query(AdaptationStateOB_.componentType
            .equals(componentType)
            .and(AdaptationStateOB_.scope.equals('global')))
        .build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  @override
  Future<List<AdaptationState>> findByComponent(String componentType) async {
    final query = box
        .query(AdaptationStateOB_.componentType.equals(componentType))
        .build();
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
  Future<List<AdaptationState>> getHistory(String componentType) async {
    final query = box
        .query(AdaptationStateOB_.componentType.equals(componentType))
        .order(AdaptationStateOB_.version)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  AdaptationState createDefault(
    String componentType, {
    String scope = 'global',
    String? userId,
  }) {
    return AdaptationState(
      componentType: componentType,
      scope: scope,
      userId: userId,
    );
  }

  @override
  Future<AdaptationState> getCurrent({
    String? componentType,
    String? userId,
  }) async {
    // If no componentType specified, use 'global'
    final type = componentType ?? 'global';
    return getForComponent(type, userId: userId);
  }
}
