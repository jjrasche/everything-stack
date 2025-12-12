/// # EdgeObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of EdgePersistenceAdapter.
/// Uses EdgeOB wrapper (Anti-Corruption Layer) to keep domain entities clean.

import 'package:objectbox/objectbox.dart';
import 'base_objectbox_adapter.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/edge_persistence_adapter.dart';
import '../../core/edge.dart';
import 'wrappers/edge_ob.dart';
import '../../objectbox.g.dart';

class EdgeObjectBoxAdapter extends BaseObjectBoxAdapter<Edge, EdgeOB>
    implements EdgePersistenceAdapter {
  EdgeObjectBoxAdapter(Store store) : super(store);

  // ============ Abstract Method Implementations ============

  @override
  EdgeOB toOB(Edge entity) => EdgeOB.fromEdge(entity);

  @override
  Edge fromOB(EdgeOB ob) => ob.toEdge();

  @override
  Condition<EdgeOB> uuidEqualsCondition(String uuid) =>
      EdgeOB_.uuid.equals(uuid);

  @override
  Condition<EdgeOB> syncStatusLocalCondition() =>
      EdgeOB_.dbSyncStatus.equals(SyncStatus.local.index);

  // ============ Entity-Specific Methods (Edge Queries) ============

  @override
  Future<List<Edge>> findBySource(String sourceUuid) async {
    final query = box.query(EdgeOB_.sourceUuid.equals(sourceUuid)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Edge>> findByTarget(String targetUuid) async {
    final query = box.query(EdgeOB_.targetUuid.equals(targetUuid)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Edge>> findByType(String edgeType) async {
    final query = box.query(EdgeOB_.edgeType.equals(edgeType)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }
}
