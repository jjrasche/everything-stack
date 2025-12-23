/// # EntityVersionOB (ObjectBox Wrapper)
///
/// ObjectBox-specific wrapper for EntityVersion entity.
/// Anti-Corruption Layer pattern.

import 'package:objectbox/objectbox.dart';
import '../../../core/entity_version.dart';

@Entity()
class EntityVersionOB {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // EntityVersion fields
  @Index()
  String entityType = '';

  @Index()
  String entityUuid = '';

  int versionNumber = 0;
  String deltaJson = '';
  String dbChangedFields = ''; // Comma-separated
  bool isSnapshot = false;
  String? snapshotJson;
  String? userId;
  String? changeDescription;

  int dbSyncStatus = 0; // SyncStatus.index

  // ============ Conversion Methods ============

  static EntityVersionOB fromEntityVersion(EntityVersion version) {
    return EntityVersionOB()
      ..id = version.id
      ..uuid = version.uuid
      ..createdAt = version.createdAt
      ..updatedAt = version.updatedAt
      ..syncId = version.syncId
      ..entityType = version.entityType
      ..entityUuid = version.entityUuid
      ..versionNumber = version.versionNumber
      ..deltaJson = version.deltaJson
      ..dbChangedFields = version.dbChangedFields
      ..isSnapshot = version.isSnapshot
      ..snapshotJson = version.snapshotJson
      ..userId = version.userId
      ..changeDescription = version.changeDescription
      ..dbSyncStatus = version.dbSyncStatus;
  }

  EntityVersion toEntityVersion() {
    final version = EntityVersion(
      entityType: entityType,
      entityUuid: entityUuid,
      timestamp: createdAt,
      versionNumber: versionNumber,
      deltaJson: deltaJson,
      changedFields: dbChangedFields.isEmpty ? [] : dbChangedFields.split(','),
      isSnapshot: isSnapshot,
      snapshotJson: snapshotJson,
      userId: userId,
      changeDescription: changeDescription,
    );

    version.id = id;
    version.uuid = uuid;
    version.syncId = syncId;
    version.dbSyncStatus = dbSyncStatus;

    return version;
  }
}
