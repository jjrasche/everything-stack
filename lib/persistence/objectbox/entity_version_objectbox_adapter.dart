/// # EntityVersionObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of VersionPersistenceAdapter.
/// Uses EntityVersionOB wrapper (Anti-Corruption Layer) to keep domain entities clean.

import 'package:objectbox/objectbox.dart';
import 'base_objectbox_adapter.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/version_persistence_adapter.dart';
import '../../core/persistence/transaction_context.dart';
import '../../core/persistence/objectbox_tx_context.dart';
import '../../core/entity_version.dart';
import 'wrappers/entity_version_ob.dart';
import '../../objectbox.g.dart';

class EntityVersionObjectBoxAdapter
    extends BaseObjectBoxAdapter<EntityVersion, EntityVersionOB>
    implements VersionPersistenceAdapter {
  EntityVersionObjectBoxAdapter(Store store) : super(store);

  // ============ Abstract Method Implementations ============

  @override
  EntityVersionOB toOB(EntityVersion entity) =>
      EntityVersionOB.fromEntityVersion(entity);

  @override
  EntityVersion fromOB(EntityVersionOB ob) => ob.toEntityVersion();

  @override
  Condition<EntityVersionOB> uuidEqualsCondition(String uuid) =>
      EntityVersionOB_.uuid.equals(uuid);

  @override
  Condition<EntityVersionOB> syncStatusLocalCondition() =>
      EntityVersionOB_.dbSyncStatus.equals(SyncStatus.local.index);

  /// Versions are immutable - don't touch() them
  @override
  bool get shouldTouchOnSave => false;

  // ============ Entity-Specific Methods (Version Queries) ============

  @override
  Future<List<EntityVersion>> findByEntityUuid(String entityUuid) async {
    final query = box
        .query(EntityVersionOB_.entityUuid.equals(entityUuid))
        .order(EntityVersionOB_.versionNumber)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<EntityVersion?> findLatestByEntityUuid(String entityUuid) async {
    final query = box
        .query(EntityVersionOB_.entityUuid.equals(entityUuid))
        .order(EntityVersionOB_.versionNumber, flags: Order.descending)
        .build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  @override
  EntityVersion? findLatestByEntityUuidInTx(
    TransactionContext ctx,
    String entityUuid,
  ) {
    final obCtx = ctx as ObjectBoxTxContext;
    final txBox = obCtx.store.box<EntityVersionOB>();
    final query = txBox
        .query(EntityVersionOB_.entityUuid.equals(entityUuid))
        .order(EntityVersionOB_.versionNumber, flags: Order.descending)
        .build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidBeforeTimestamp(
    String entityUuid,
    DateTime timestamp,
  ) async {
    final timestampMs =
        timestamp.add(const Duration(milliseconds: 1)).millisecondsSinceEpoch;
    final query = box
        .query(EntityVersionOB_.entityUuid
            .equals(entityUuid)
            .and(EntityVersionOB_.createdAt.lessThan(timestampMs)))
        .order(EntityVersionOB_.versionNumber)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidBetween(
    String entityUuid,
    DateTime from,
    DateTime to,
  ) async {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final query = box
        .query(EntityVersionOB_.entityUuid
            .equals(entityUuid)
            .and(EntityVersionOB_.createdAt.between(fromMs, toMs)))
        .order(EntityVersionOB_.versionNumber)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidUnsynced(
      String entityUuid) async {
    final query = box
        .query(EntityVersionOB_.entityUuid
            .equals(entityUuid)
            .and(EntityVersionOB_.dbSyncStatus.equals(SyncStatus.local.index)))
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }
}
