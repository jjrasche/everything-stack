import 'dart:indexed_db' as idb;
import '../../domain/atomic_insight.dart';
import '../../core/persistence/persistence_adapter.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';

class AtomicInsightIndexedDBAdapter extends BaseIndexedDBAdapter<AtomicInsight>
    implements PersistenceAdapter<AtomicInsight> {
  AtomicInsightIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.atomicInsights;

  @override
  AtomicInsight fromJson(Map<String, dynamic> json) =>
      AtomicInsight.fromJson(json);

  // ============ Custom Queries ============

  /// Find insights by scope (session, day, week, project, life)
  Future<List<AtomicInsight>> findByScope(String scope,
      {bool includeArchived = false}) async {
    final allInsights = await findAll();
    return allInsights
        .where((insight) =>
            insight.scope == scope &&
            (includeArchived || !insight.isArchived))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Find insights by project ID
  Future<List<AtomicInsight>> findByProject(String projectId,
      {bool includeArchived = false}) async {
    final allInsights = await findAll();
    return allInsights
        .where((insight) =>
            insight.projectId == projectId &&
            (includeArchived || !insight.isArchived))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Find insights by type (learning, project, exploration)
  Future<List<AtomicInsight>> findByType(String type,
      {String? scope, bool includeArchived = false}) async {
    final allInsights = await findAll();
    return allInsights
        .where((insight) =>
            insight.type == type &&
            (scope == null || insight.scope == scope) &&
            (includeArchived || !insight.isArchived))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Find insights with embeddings (for semantic search)
  Future<List<AtomicInsight>> findWithEmbeddings(
      {bool includeArchived = false}) async {
    final allInsights = await findAll();
    return allInsights
        .where((insight) =>
            insight.embedding != null &&
            insight.embedding!.isNotEmpty &&
            (includeArchived || !insight.isArchived))
        .toList();
  }
}
