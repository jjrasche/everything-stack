/// # FeedbackObjectBoxAdapter Stub for Web Platform
///
/// This file is a stub for Web platform where ObjectBox is not available.
/// Real implementation uses ObjectBox on native platforms.

library;

import '../../bootstrap/objectbox_stub.dart' if (dart.library.io) 'package:objectbox/objectbox.dart';
import '../../core/feedback_repository.dart';
import '../../domain/feedback.dart';

/// Stub FeedbackObjectBoxAdapter for Web platform
class FeedbackObjectBoxAdapter implements FeedbackRepository {
  final Store store;

  FeedbackObjectBoxAdapter(this.store);

  @override
  Future<List<Feedback>> findByInvocationId(String invocationId) async => [];

  @override
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds) async => [];

  @override
  Future<List<Feedback>> findByTurn(String turnId) async => [];

  @override
  Future<List<Feedback>> findByTurnAndComponent(String turnId, String componentType) async => [];

  @override
  Future<List<Feedback>> findByContextType(String contextType) async => [];

  @override
  Future<List<Feedback>> findAllConversational() async => [];

  @override
  Future<List<Feedback>> findAllBackground() async => [];

  @override
  Future<Feedback> save(Feedback feedback) async => feedback;

  @override
  Future<bool> delete(String id) async => false;

  @override
  Future<int> deleteByTurn(String turnId) async => 0;
}
