/// # TurnObjectBoxAdapter Stub for Web Platform
///
/// This file is a stub for Web platform where ObjectBox is not available.
/// Real implementation uses ObjectBox on native platforms.

library;

import '../../bootstrap/objectbox_stub.dart' if (dart.library.io) 'package:objectbox/objectbox.dart';
import '../../core/turn_repository.dart';
import '../../domain/turn.dart';

/// Stub TurnObjectBoxAdapter for Web platform
class TurnObjectBoxAdapter implements TurnRepository {
  final Store store;

  TurnObjectBoxAdapter(this.store);

  @override
  Future<Turn?> findById(String id) async => null;

  @override
  Future<List<Turn>> findByConversation(String conversationId) async => [];

  @override
  Future<List<Turn>> findMarkedForFeedbackByConversation(String conversationId) async => [];

  @override
  Future<Turn?> findByInvocationId(String invocationId) async => null;

  @override
  Future<Turn> save(Turn turn) async => turn;

  @override
  Future<bool> delete(String id) async => false;

  @override
  Future<int> deleteByConversation(String conversationId) async => 0;
}
