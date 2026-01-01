/// # FeedbackIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../core/feedback_repository.dart';
import '../../domain/feedback.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class FeedbackIndexedDBAdapter extends BaseIndexedDBAdapter<Feedback>
    implements FeedbackRepository {
  FeedbackIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.feedback;

  @override
  Feedback fromJson(Map<String, dynamic> json) => Feedback.fromJson(json);

  // ============ FeedbackRepository Implementation ============

  @override
  Future<List<Feedback>> findByInvocationId(String invocationId) async {
    final allFeedback = await findAll();
    return allFeedback.where((f) => f.invocationId == invocationId).toList();
  }

  @override
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds) async {
    final allFeedback = await findAll();
    return allFeedback
        .where((f) => invocationIds.contains(f.invocationId))
        .toList();
  }

  @override
  Future<List<Feedback>> findByTurn(String turnId) async {
    final allFeedback = await findAll();
    return allFeedback.where((f) => f.turnId == turnId).toList();
  }

  @override
  Future<List<Feedback>> findByTurnAndComponent(
    String turnId,
    String componentType,
  ) async {
    final allFeedback = await findAll();
    return allFeedback
        .where((f) => f.turnId == turnId && f.componentType == componentType)
        .toList();
  }

  @override
  Future<List<Feedback>> findByContextType(String contextType) async {
    final allFeedback = await findAll();
    return allFeedback.where((f) => f.componentType == contextType).toList();
  }

  @override
  Future<List<Feedback>> findAllConversational() async {
    final allFeedback = await findAll();
    return allFeedback.where((f) => f.turnId != null).toList();
  }

  @override
  Future<List<Feedback>> findAllBackground() async {
    final allFeedback = await findAll();
    return allFeedback.where((f) => f.turnId == null).toList();
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final allFeedback = await findAll();
    final toDelete = allFeedback.where((f) => f.turnId == turnId).toList();
    int deletedCount = 0;
    for (final f in toDelete) {
      if (await delete(f.uuid)) {
        deletedCount++;
      }
    }
    return deletedCount;
  }
}
