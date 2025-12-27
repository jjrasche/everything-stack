/// # InvocationIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../core/invocation_repository.dart';
import '../../domain/invocation.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class InvocationIndexedDBAdapter extends BaseIndexedDBAdapter<Invocation>
    implements InvocationRepository<Invocation> {
  InvocationIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.invocations;

  @override
  Invocation fromJson(Map<String, dynamic> json) =>
      Invocation.fromJson(json);

  // ============ InvocationRepository Implementation ============

  @override
  Future<List<Invocation>> findByTurn(String turnId) async {
    final allInvocations = await findAll();
    return allInvocations
        .where((inv) => inv.turnId == turnId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<List<Invocation>> findByContextType(String contextType) async {
    final allInvocations = await findAll();
    return allInvocations
        .where((inv) => inv.componentType == contextType)
        .toList();
  }

  @override
  Future<List<Invocation>> findByIds(List<String> ids) async {
    final allInvocations = await findAll();
    return allInvocations.where((inv) => ids.contains(inv.uuid)).toList();
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final allInvocations = await findAll();
    final toDelete =
        allInvocations.where((inv) => inv.turnId == turnId).toList();
    int deletedCount = 0;
    for (final inv in toDelete) {
      if (await delete(inv.uuid)) {
        deletedCount++;
      }
    }
    return deletedCount;
  }
}
