/// # FeedbackIndexedDBAdapter

import 'package:idb_shim/idb.dart';
import '../../domain/feedback.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class FeedbackIndexedDBAdapter extends BaseIndexedDBAdapter<Feedback> {
  FeedbackIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.feedback;

  @override
  Feedback fromJson(Map<String, dynamic> json) => Feedback.fromJson(json);
}
