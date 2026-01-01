/// # TurnIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../core/turn_repository.dart';
import '../../domain/turn.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class TurnIndexedDBAdapter extends BaseIndexedDBAdapter<Turn>
    implements TurnRepository {
  TurnIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.turns;

  @override
  Turn fromJson(Map<String, dynamic> json) => Turn.fromJson(json);

  // ============ TurnRepository Implementation ============

  @override
  Future<List<Turn>> findByConversation(String conversationId) async {
    final allTurns = await findAll();
    final filtered =
        allTurns.where((t) => t.conversationId == conversationId).toList();
    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
  }

  @override
  Future<List<Turn>> findMarkedForFeedbackByConversation(
      String conversationId) async {
    final allTurns = await findAll();
    final filtered = allTurns
        .where((t) => t.conversationId == conversationId && t.markedForFeedback)
        .toList();
    filtered.sort((a, b) {
      final aMarked = a.markedAt ?? DateTime.now();
      final bMarked = b.markedAt ?? DateTime.now();
      return bMarked.compareTo(aMarked); // descending
    });
    return filtered;
  }

  @override
  Future<Turn?> findByInvocationId(String invocationId) async {
    final allTurns = await findAll();
    return allTurns.firstWhere(
      (turn) => turn.getInvocationIds().contains(invocationId),
      orElse: () => null as dynamic,
    ) as Turn?;
  }

  @override
  Future<int> deleteByConversation(String conversationId) async {
    final allTurns = await findAll();
    final toDelete =
        allTurns.where((t) => t.conversationId == conversationId).toList();
    int deletedCount = 0;
    for (final turn in toDelete) {
      if (await delete(turn.uuid)) {
        deletedCount++;
      }
    }
    return deletedCount;
  }
}
