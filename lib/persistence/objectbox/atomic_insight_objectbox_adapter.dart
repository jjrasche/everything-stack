/// # AtomicInsightObjectBoxAdapter
///
/// ObjectBox implementation of PersistenceAdapter for AtomicInsight.
/// Converts between domain AtomicInsight and AtomicInsightOB wrapper.

import 'package:objectbox/objectbox.dart';
import '../../domain/atomic_insight.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/atomic_insight_ob.dart';

class AtomicInsightObjectBoxAdapter
    extends BaseObjectBoxAdapter<AtomicInsight, AtomicInsightOB>
    implements PersistenceAdapter<AtomicInsight> {
  AtomicInsightObjectBoxAdapter(Store store) : super(store);

  @override
  AtomicInsightOB toOB(AtomicInsight entity) =>
      AtomicInsightOB.fromAtomicInsight(entity);

  @override
  AtomicInsight fromOB(AtomicInsightOB ob) => ob.toAtomicInsight();

  @override
  Condition<AtomicInsightOB> uuidEqualsCondition(String uuid) =>
      AtomicInsightOB_.uuid.equals(uuid);

  @override
  Condition<AtomicInsightOB> syncStatusLocalCondition() =>
      AtomicInsightOB_.syncStatus.notEquals(0);

  // ============ Custom Queries ============

  /// Find insights by scope (session, day, week, project, life)
  Future<List<AtomicInsight>> findByScope(String scope,
      {bool includeArchived = false}) async {
    final queryBuilder = box.query(AtomicInsightOB_.scope.equals(scope));
    if (!includeArchived) {
      queryBuilder.and(AtomicInsightOB_.isArchived.equals(false));
    }
    final query = queryBuilder.order(AtomicInsightOB_.updatedAt,
        flags: Order.descending).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find insights by project ID
  Future<List<AtomicInsight>> findByProject(String projectId,
      {bool includeArchived = false}) async {
    final queryBuilder = box.query(AtomicInsightOB_.projectId.equals(projectId));
    if (!includeArchived) {
      queryBuilder.and(AtomicInsightOB_.isArchived.equals(false));
    }
    final query = queryBuilder.order(AtomicInsightOB_.updatedAt,
        flags: Order.descending).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find insights by type (learning, project, exploration)
  Future<List<AtomicInsight>> findByType(String type,
      {String? scope, bool includeArchived = false}) async {
    final queryBuilder = box.query(AtomicInsightOB_.type.equals(type));
    if (scope != null) {
      queryBuilder.and(AtomicInsightOB_.scope.equals(scope));
    }
    if (!includeArchived) {
      queryBuilder.and(AtomicInsightOB_.isArchived.equals(false));
    }
    final query = queryBuilder.order(AtomicInsightOB_.updatedAt,
        flags: Order.descending).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find insights with embeddings (for semantic search)
  Future<List<AtomicInsight>> findWithEmbeddings(
      {bool includeArchived = false}) async {
    final queryBuilder = box.query(AtomicInsightOB_.embedding.notNull());
    if (!includeArchived) {
      queryBuilder.and(AtomicInsightOB_.isArchived.equals(false));
    }
    final query = queryBuilder.build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }
}
