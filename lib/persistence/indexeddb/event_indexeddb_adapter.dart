/// # EventIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../domain/event.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class EventIndexedDBAdapter extends BaseIndexedDBAdapter<Event> {
  EventIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.events;

  @override
  Event fromJson(Map<String, dynamic> json) => Event.fromJson(json);
}
