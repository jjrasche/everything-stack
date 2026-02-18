import 'dart:indexed_db' as idb;
import '../../domain/proposition.dart';
import '../../core/persistence/persistence_adapter.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class PropositionIndexedDBAdapter extends BaseIndexedDBAdapter<Proposition>
    implements PersistenceAdapter<Proposition> {
  PropositionIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.propositions;

  @override
  Proposition fromJson(Map<String, dynamic> json) =>
      Proposition.fromJson(json);

  Future<List<Proposition>> findByEpisode(String episodeId) async {
    final all = await findAll();
    return all
        .where((p) => p.sourceEpisodeId == episodeId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<List<Proposition>> findActive() async {
    final all = await findAll();
    return all
        .where((p) => p.status == 'active')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Proposition>> findByStatus(String status) async {
    final all = await findAll();
    return all
        .where((p) => p.status == status)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<Proposition>> findSuperseded() async {
    return findByStatus('superseded');
  }
}
