import 'dart:indexed_db' as idb;
import '../../domain/prompt_version.dart';
import '../../core/persistence/persistence_adapter.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class PromptVersionIndexedDBAdapter extends BaseIndexedDBAdapter<PromptVersion>
    implements PersistenceAdapter<PromptVersion> {
  PromptVersionIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.promptVersions;

  @override
  PromptVersion fromJson(Map<String, dynamic> json) =>
      PromptVersion.fromJson(json);

  Future<List<PromptVersion>> findByComponent(String componentType) async {
    final all = await findAll();
    return all
        .where((v) => v.componentType == componentType)
        .toList()
      ..sort((a, b) => b.version.compareTo(a.version));
  }

  Future<PromptVersion?> findActive(String componentType) async {
    final all = await findAll();
    for (final v in all) {
      if (v.componentType == componentType && v.isActive) return v;
    }
    return null;
  }
}
