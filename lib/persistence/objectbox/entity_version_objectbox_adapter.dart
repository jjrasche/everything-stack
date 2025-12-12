/// # EntityVersionObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for EntityVersion entities.
/// Handles CRUD operations for version tracking records.
///
/// ## Note on semantic search
/// EntityVersion records don't have embeddings, so semantic search methods
/// return empty results. This is expected behavior.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = EntityVersionObjectBoxAdapter(store);
/// final repo = VersionRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import 'base_objectbox_adapter.dart';
import '../../core/base_entity.dart';
import '../../core/persistence/version_persistence_adapter.dart';
import '../../core/persistence/transaction_context.dart';
import '../../core/persistence/objectbox_tx_context.dart';
import '../../core/entity_version.dart';
import '../../objectbox.g.dart';

class EntityVersionObjectBoxAdapter extends BaseObjectBoxAdapter<EntityVersion>
    implements VersionPersistenceAdapter {
  EntityVersionObjectBoxAdapter(Store store) : super(store);

  // ============ Entity-Specific Query Conditions ============

  @override
  Condition<EntityVersion> uuidEqualsCondition(String uuid) =>
      EntityVersion_.uuid.equals(uuid);

  @override
  Condition<EntityVersion> syncStatusLocalCondition() =>
      EntityVersion_.dbSyncStatus.equals(SyncStatus.local.index);

  // ============ EntityVersion-Specific Behavior ============

  /// Versions are immutable - don't touch() them
  @override
  bool get shouldTouchOnSave => false;

  // ============ Version-specific queries ============
  // These are used by VersionRepository for version management

  @override
  Future<List<EntityVersion>> findByEntityUuid(String entityUuid) async {
    final query = box
        .query(EntityVersion_.entityUuid.equals(entityUuid))
        .order(EntityVersion_.versionNumber)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<EntityVersion?> findLatestByEntityUuid(String entityUuid) async {
    final query = box
        .query(EntityVersion_.entityUuid.equals(entityUuid))
        .order(EntityVersion_.versionNumber, flags: Order.descending)
        .build();
    try {
      return query.findFirst();
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
    final txBox = obCtx.store.box<EntityVersion>();
    final query = txBox
        .query(EntityVersion_.entityUuid.equals(entityUuid))
        .order(EntityVersion_.versionNumber, flags: Order.descending)
        .build();
    try {
      return query.findFirst();
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
        .query(EntityVersion_.entityUuid
            .equals(entityUuid)
            .and(EntityVersion_.createdAt.lessThan(timestampMs)))
        .order(EntityVersion_.versionNumber)
        .build();
    try {
      return query.find();
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
        .query(EntityVersion_.entityUuid
            .equals(entityUuid)
            .and(EntityVersion_.createdAt.between(fromMs, toMs)))
        .order(EntityVersion_.versionNumber)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EntityVersion>> findByEntityUuidUnsynced(
      String entityUuid) async {
    final query = box
        .query(EntityVersion_.entityUuid
            .equals(entityUuid)
            .and(EntityVersion_.dbSyncStatus.equals(SyncStatus.local.index)))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}
