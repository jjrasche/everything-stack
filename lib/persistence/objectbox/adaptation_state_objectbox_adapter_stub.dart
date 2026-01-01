/// # AdaptationStateObjectBoxAdapter Stub for Web Platform
///
/// This file is a stub for Web platform where ObjectBox is not available.
/// Real implementation uses ObjectBox on native platforms.

library;

import '../../bootstrap/objectbox_stub.dart' if (dart.library.io) 'package:objectbox/objectbox.dart';
import '../../core/adaptation_state.dart';
import '../../core/adaptation_state_repository.dart';

/// Stub AdaptationStateObjectBoxAdapter for Web platform
class AdaptationStateObjectBoxAdapter implements AdaptationStateRepository {
  final Store store;

  AdaptationStateObjectBoxAdapter(this.store);

  @override
  Future<AdaptationState> getForComponent(String componentType, {String? userId}) async =>
      createDefault(componentType, userId: userId);

  @override
  Future<AdaptationState> getCurrent({String? componentType, String? userId}) async =>
      createDefault(componentType ?? 'global', userId: userId);

  @override
  Future<AdaptationState?> getUserState(String componentType, String userId) async => null;

  @override
  Future<AdaptationState?> getGlobal(String componentType) async => null;

  @override
  Future<List<AdaptationState>> findByComponent(String componentType) async => [];

  @override
  Future<bool> updateWithVersion(AdaptationState state) async => false;

  @override
  Future<AdaptationState> save(AdaptationState state) async => state;

  @override
  Future<List<AdaptationState>> getHistory(String componentType) async => [];

  @override
  Future<bool> delete(String id) async => false;

  @override
  AdaptationState createDefault(String componentType, {String scope = 'global', String? userId}) =>
      AdaptationState(
        componentType: componentType,
        scope: scope,
        userId: userId,
        data: {},
      );
}
