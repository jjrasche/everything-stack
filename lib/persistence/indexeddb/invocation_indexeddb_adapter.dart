/// # InvocationIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../domain/invocation.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class InvocationIndexedDBAdapter extends BaseIndexedDBAdapter<Invocation> {
  InvocationIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.invocations;

  @override
  Invocation fromJson(Map<String, dynamic> json) => Invocation.fromJson(json);
}
