/// # AdaptationStateIndexedDBAdapter

import 'package:idb_shim/idb.dart';
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
    final allItems = await findAll();
    return allItems.firstWhere(
      (item) =>
          item.componentType == componentType &&
          item.scope == 'user' &&
          item.userId == userId,
      orElse: () => null as dynamic,
    ) as AdaptationState?;
  }

  @override
  Future<AdaptationState?> getGlobal(String componentType) async {
    final allItems = await findAll();
    return allItems.firstWhere(
      (item) =>
          item.componentType == componentType && item.scope == 'global',
      orElse: () => null as dynamic,
    ) as AdaptationState?;
  }

  @override
  Future<List<AdaptationState>> findByComponent(String componentType) async {
    final allItems = await findAll();
    return allItems.where((item) => item.componentType == componentType).toList();
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
    final allItems = await findAll();
    final filtered = allItems
        .where((item) => item.componentType == componentType)
        .toList();
    filtered.sort((a, b) => a.version.compareTo(b.version));
    return filtered;
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
