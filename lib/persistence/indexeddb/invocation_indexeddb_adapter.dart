import 'dart:indexed_db' as idb;
import '../../core/invocation_repository.dart';
import '../../core/invocation.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class InvocationIndexedDBAdapter extends BaseIndexedDBAdapter<Invocation>
    implements InvocationRepository<Invocation> {
  InvocationIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.invocations;

  @override
  Invocation fromJson(Map<String, dynamic> json) => Invocation.fromJson(json);

  // ============ InvocationRepository Implementation ============

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
}
