/// # VersionPersistenceAdapter
///
/// ## What it does
/// Specialized persistence adapter interface for EntityVersion entities.
/// Extends base PersistenceAdapter with version-specific query methods.
///
/// ## What it enables
/// - VersionRepository can depend on interface, not concrete ObjectBox type
/// - Same VersionRepository works with ObjectBox and IndexedDB adapters
/// - Version-specific queries (by entity, time ranges) abstracted from implementation
///
/// ## Usage
/// ```dart
/// // ObjectBox implementation
/// final adapter = EntityVersionObjectBoxAdapter(store);
/// final repo = VersionRepository(adapter: adapter);
///
/// // Future: IndexedDB implementation
/// final adapter = EntityVersionIndexedDBAdapter(database);
/// final repo = VersionRepository(adapter: adapter);
/// ```

import 'persistence_adapter.dart';
import 'transaction_context.dart';
import '../entity_version.dart';

/// Persistence adapter interface for EntityVersion entities.
///
/// Adds version-specific query methods on top of base CRUD operations.
abstract class VersionPersistenceAdapter
    implements PersistenceAdapter<EntityVersion> {
  /// Get all versions for an entity, ordered by version number.
  Future<List<EntityVersion>> findByEntityUuid(String entityUuid);

  /// Get the latest version for an entity.
  Future<EntityVersion?> findLatestByEntityUuid(String entityUuid);

  /// Find versions up to a specific timestamp.
  Future<List<EntityVersion>> findByEntityUuidBeforeTimestamp(
    String entityUuid,
    DateTime timestamp,
  );

  /// Find versions in a time range.
  Future<List<EntityVersion>> findByEntityUuidBetween(
    String entityUuid,
    DateTime from,
    DateTime to,
  );

  /// Find unsynced versions for a specific entity.
  Future<List<EntityVersion>> findByEntityUuidUnsynced(String entityUuid);

  // ============ Transaction Operations ============
  // Version-specific queries that can be used within transactions

  /// Get the latest version for an entity (synchronous, for use in transactions).
  ///
  /// Must be called within TransactionManager.transaction() callback.
  EntityVersion? findLatestByEntityUuidInTx(
    TransactionContext ctx,
    String entityUuid,
  );
}
