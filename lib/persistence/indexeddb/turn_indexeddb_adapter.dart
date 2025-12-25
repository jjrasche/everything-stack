/// # TurnIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../domain/turn.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class TurnIndexedDBAdapter extends BaseIndexedDBAdapter<Turn> {
  TurnIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.turns;

  @override
  Turn fromJson(Map<String, dynamic> json) => Turn.fromJson(json);
}
