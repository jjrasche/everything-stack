/// # EventIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../domain/event.dart' as domain_event;
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class EventIndexedDBAdapter extends BaseIndexedDBAdapter<domain_event.Event> {
  EventIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.events;

  @override
  domain_event.Event fromJson(Map<String, dynamic> json) =>
      domain_event.Event.fromJson(json);
}
