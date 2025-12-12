/// # EdgeOB (ObjectBox Wrapper)
///
/// ObjectBox-specific wrapper for Edge entity.
/// Anti-Corruption Layer pattern.

import 'package:objectbox/objectbox.dart';
import '../../../core/edge.dart';
import '../../../core/base_entity.dart' show SyncStatus;

@Entity()
class EdgeOB {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // Edge fields
  String sourceType = '';

  @Index()
  String sourceUuid = '';

  String targetType = '';

  @Index()
  String targetUuid = '';

  @Index()
  String edgeType = '';

  String? metadata;
  String? createdBy;

  int dbSyncStatus = 0; // SyncStatus.index

  // ============ Conversion Methods ============

  static EdgeOB fromEdge(Edge edge) {
    return EdgeOB()
      ..id = edge.id
      ..uuid = edge.uuid
      ..createdAt = edge.createdAt
      ..updatedAt = edge.updatedAt
      ..syncId = edge.syncId
      ..sourceType = edge.sourceType
      ..sourceUuid = edge.sourceUuid
      ..targetType = edge.targetType
      ..targetUuid = edge.targetUuid
      ..edgeType = edge.edgeType
      ..metadata = edge.metadata
      ..createdBy = edge.createdBy
      ..dbSyncStatus = edge.dbSyncStatus;
  }

  Edge toEdge() {
    final edge = Edge(
      sourceType: sourceType,
      sourceUuid: sourceUuid,
      targetType: targetType,
      targetUuid: targetUuid,
      edgeType: edgeType,
      metadata: metadata,
      createdBy: createdBy,
    );

    edge.id = id;
    edge.uuid = uuid;
    edge.createdAt = createdAt;
    edge.updatedAt = updatedAt;
    edge.syncId = syncId;
    edge.dbSyncStatus = dbSyncStatus;

    return edge;
  }
}
