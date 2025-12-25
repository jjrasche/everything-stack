/// # AdaptationStateIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../domain/adaptation_state_generic.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class AdaptationStateIndexedDBAdapter
    extends BaseIndexedDBAdapter<AdaptationState> {
  AdaptationStateIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.adaptation_state;

  @override
  AdaptationState fromJson(Map<String, dynamic> json) =>
      AdaptationState.fromJson(json);
}
