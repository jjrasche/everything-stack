import 'dart:indexed_db' as idb;
import '../../core/adaptation_state.dart';
import '../../core/adaptation_state_repository.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class AdaptationStateIndexedDBAdapter
    extends BaseIndexedDBAdapter<AdaptationState>
    implements AdaptationStateRepository {
  AdaptationStateIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.adaptation_state;

  @override
  AdaptationState fromJson(Map<String, dynamic> json) =>
      AdaptationState.fromJson(json);

  // ============ AdaptationStateRepository Implementation ============

  @override
  Future<AdaptationState?> getForComponent(
    String componentType, {
    required String? implementer,
    String? userId,
  }) async {
    // Query by (componentType, implementer, userId)
    final allItems = await findAll();
    return allItems.firstWhere(
      (item) =>
          item.componentType == componentType &&
          item.implementer == implementer &&
          item.userId == userId,
      orElse: () => null as dynamic,
    ) as AdaptationState?;
  }

  @override
  Future<List<AdaptationState>> findByComponentAndImplementer(
    String componentType, {
    required String? implementer,
  }) async {
    final allItems = await findAll();
    return allItems
        .where((item) =>
            item.componentType == componentType &&
            item.implementer == implementer)
        .toList();
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
