/// # VersionRepository
///
/// ## What it does
/// Manages EntityVersion records for all versioned entities.
/// Handles delta computation, snapshot creation, reconstruction, and pruning.
///
/// ## What it enables
/// - Record changes with automatic delta computation
/// - Retrieve version history for any entity
/// - Reconstruct entity state at any point in time
/// - Query changes in time ranges
/// - Prune old versions while keeping snapshots
///
/// ## Usage
/// ```dart
/// final adapter = EntityVersionObjectBoxAdapter(store);
/// final repo = VersionRepository(adapter: adapter);
///
/// // Record a change
/// await repo.recordChange(
///   entityUuid: note.uuid,
///   entityType: 'Note',
///   oldState: {'title': 'Old'},
///   newState: {'title': 'New'},
///   userId: currentUser.id,
///   snapshotFrequency: 20,
/// );
///
/// // Get history
/// final versions = await repo.getHistory(note.uuid);
///
/// // Reconstruct at timestamp
/// final state = await repo.reconstruct(note.uuid, targetTime);
/// ```
///
/// ## Testing approach
/// Integration tests cover:
/// - Recording first version creates snapshot
/// - Subsequent versions create deltas
/// - Periodic snapshots at frequency intervals
/// - Reconstruction from snapshots + deltas
/// - Time-range queries
/// - Pruning keeps snapshots

import 'dart:convert';
import 'package:rfc_6902/rfc_6902.dart';
import 'entity_version.dart';
import '../utils/json_diff.dart';
import 'base_entity.dart' show SyncStatus;
import 'persistence/version_persistence_adapter.dart';
import 'persistence/transaction_context.dart';

class VersionRepository {
  final VersionPersistenceAdapter _adapter;

  VersionRepository({required VersionPersistenceAdapter adapter})
      : _adapter = adapter;

  /// Record a change to an entity.
  ///
  /// - First change creates a snapshot (versionNumber = 1)
  /// - Subsequent changes store deltas
  /// - Periodic snapshots created every [snapshotFrequency] versions
  ///
  /// [snapshotFrequency] defaults to 20. Set to null to disable periodic snapshots.
  /// [previousJson] can be null for new entities (creates initial snapshot).
  /// [currentJson] should be entity.toJson() from a Versionable entity.
  Future<void> recordChange({
    required String entityUuid,
    required String entityType,
    required Map<String, dynamic>? previousJson,
    required Map<String, dynamic> currentJson,
    String? userId,
    String? changeDescription,
    int? snapshotFrequency = 20,
  }) async {
    final latestVersion = await getLatestVersionNumber(entityUuid);
    final newVersionNumber = latestVersion + 1;

    final isFirstVersion = newVersionNumber == 1;
    final isPeriodicSnapshot =
        snapshotFrequency != null && newVersionNumber % snapshotFrequency == 1;
    final shouldSnapshot = isFirstVersion || isPeriodicSnapshot;

    // Compute delta and changed fields
    final previousState = previousJson ?? {};
    final delta = JsonDiff.diff(previousState, currentJson);
    final deltaJson = jsonEncode(delta);
    final changedFields =
        JsonDiff.extractChangedFields(previousState, currentJson);

    final version = EntityVersion(
      entityType: entityType,
      entityUuid: entityUuid,
      timestamp: DateTime.now(),
      versionNumber: newVersionNumber,
      deltaJson: deltaJson,
      changedFields: changedFields,
      isSnapshot: shouldSnapshot,
      snapshotJson: shouldSnapshot ? jsonEncode(currentJson) : null,
      userId: userId,
      changeDescription: changeDescription,
    );

    await _adapter.save(version);
  }

  /// Get all versions for an entity, ordered by version number.
  Future<List<EntityVersion>> getHistory(String entityUuid) async {
    return _adapter.findByEntityUuid(entityUuid);
  }

  /// Get the latest version number for an entity.
  /// Returns 0 if entity has no versions.
  Future<int> getLatestVersionNumber(String entityUuid) async {
    final latest = await _adapter.findLatestByEntityUuid(entityUuid);
    return latest?.versionNumber ?? 0;
  }

  /// Reconstruct entity state at a specific timestamp.
  ///
  /// Algorithm:
  /// 1. Find nearest snapshot before or at target timestamp
  /// 2. Apply deltas forward until reaching target timestamp
  /// 3. Return reconstructed state
  ///
  /// Returns null if timestamp is before first version.
  Future<Map<String, dynamic>?> reconstruct(
    String entityUuid,
    DateTime targetTimestamp,
  ) async {
    // Get all versions up to target timestamp
    final versions = await _adapter.findByEntityUuidBeforeTimestamp(
        entityUuid, targetTimestamp);

    if (versions.isEmpty) {
      return null; // No versions before target
    }

    // Find nearest snapshot before target
    EntityVersion? baseSnapshot;
    int startIndex = 0;

    for (int i = versions.length - 1; i >= 0; i--) {
      if (versions[i].isSnapshot) {
        baseSnapshot = versions[i];
        startIndex = i;
        break;
      }
    }

    if (baseSnapshot == null) {
      return null; // No snapshot found (shouldn't happen if first version is snapshot)
    }

    // Start with snapshot state
    Map<String, dynamic> state = jsonDecode(baseSnapshot.snapshotJson!);

    // Apply deltas forward from snapshot to target
    for (int i = startIndex + 1; i < versions.length; i++) {
      final delta = jsonDecode(versions[i].deltaJson) as List;
      final patch = JsonPatch(delta);
      final result = patch.applyTo(state);
      state = Map<String, dynamic>.from(result as Map);
    }

    return state;
  }

  /// Get versions between two timestamps.
  Future<List<EntityVersion>> getChangesBetween(
    String entityUuid,
    DateTime from,
    DateTime to,
  ) async {
    return _adapter.findByEntityUuidBetween(entityUuid, from, to);
  }

  /// Prune old versions while keeping recent snapshots.
  ///
  /// Strategy:
  /// - Keep N most recent snapshots
  /// - Keep all versions after oldest kept snapshot
  /// - Delete everything older
  Future<void> prune(String entityUuid, {required int keepSnapshots}) async {
    final allVersions = await getHistory(entityUuid);

    if (allVersions.isEmpty) return;

    // Find snapshots
    final snapshots = allVersions.where((v) => v.isSnapshot).toList();

    if (snapshots.length <= keepSnapshots) {
      return; // Nothing to prune
    }

    // Keep N most recent snapshots
    final snapshotsToKeep = snapshots.sublist(snapshots.length - keepSnapshots);
    final oldestKeptSnapshot = snapshotsToKeep.first;

    // Delete all versions older than oldest kept snapshot
    final uuidsToDelete = allVersions
        .where((v) => v.versionNumber < oldestKeptSnapshot.versionNumber)
        .map((v) => v.uuid)
        .toList();
    await _adapter.deleteAll(uuidsToDelete);
  }

  // ============ Sync Methods ============

  /// Find all unsynced versions (for sync service)
  Future<List<EntityVersion>> findUnsynced() async {
    return _adapter.findUnsynced();
  }

  /// Find unsynced versions for a specific entity
  Future<List<EntityVersion>> findByEntityUuidUnsynced(
      String entityUuid) async {
    return _adapter.findByEntityUuidUnsynced(entityUuid);
  }

  /// Mark version as synced (for sync service)
  Future<void> markSynced(String uuid) async {
    final version = await _adapter.findById(uuid);
    if (version != null) {
      version.syncStatus = SyncStatus.synced;
      await _adapter.save(version);
    }
  }

  // ============ Transaction Methods ============

  /// Get latest version number synchronously within transaction.
  ///
  /// Must be called within TransactionManager.transaction() callback.
  /// Returns 0 if entity has no versions.
  int getLatestVersionNumberInTx(TransactionContext ctx, String entityUuid) {
    final latest = _adapter.findLatestByEntityUuidInTx(ctx, entityUuid);
    return latest?.versionNumber ?? 0;
  }
}
