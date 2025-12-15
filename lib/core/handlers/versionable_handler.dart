/// # VersionableHandler
///
/// ## What it does
/// Orchestrates version history recording for Versionable entities.
/// Records changes atomically within entity save transaction.
///
/// ## Pattern
/// Entities that implement Versionable opt-in to change tracking.
/// Each save records entity changes in VersionRepository with delta.
///
/// ## Lifecycle
/// beforeSaveInTransaction: Record version inside entity save transaction (atomic)
/// afterSaveInTransaction: No-op (all work done in beforeSaveInTransaction)
///
/// ## Error Semantics
/// Atomic: Version recording happens inside same transaction as entity save.
/// If version recording fails, both version and entity save are rolled back.
///
/// Rationale: Version history must be atomic with entity. Entity without
/// version history would be corruption. Must use transactional hooks.

import 'dart:convert';

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/entity_version.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import 'package:everything_stack_template/patterns/versionable.dart';
import 'package:everything_stack_template/utils/json_diff.dart';
import '../repository_pattern_handler.dart';

/// Handler for Versionable pattern.
///
/// Responsible for:
/// - Recording entity version within save transaction (atomic)
///
/// Why transactional?
/// Version history must be atomic with entity save. An entity without
/// its version history is a data corruption. This handler uses
/// beforeSaveInTransaction to record version inside the same transaction
/// as the entity save.
class VersionableHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final dynamic versionRepository;
  final T? Function(TransactionContext ctx, String uuid) findByUuidSync;
  final int Function(TransactionContext ctx, String entityUuid)
      getLatestVersionNumberSync;

  VersionableHandler({
    required this.versionRepository,
    required this.findByUuidSync,
    required this.getLatestVersionNumberSync,
  });

  /// Record version within transaction BEFORE entity is persisted (atomic path).
  ///
  /// This is the critical piece: version recording happens inside the
  /// same transaction as entity persistence. If either fails, both
  /// are rolled back together.
  ///
  /// Only called when TransactionManager is provided.
  @override
  void beforeSaveInTransaction(TransactionContext ctx, T entity) {
    if (entity is! Versionable) return;
    if (versionRepository == null) return;

    // Build version record synchronously within transaction
    final version = _buildVersionSync(ctx, entity as Versionable);

    // Save version first, then entity save follows
    versionRepository.saveInTx(ctx, version);
  }

  /// Record version AFTER entity is persisted (fallback for non-transactional saves).
  ///
  /// When TransactionManager is not provided, version recording falls back to
  /// this async method called after the entity is persisted.
  ///
  /// Note: This is NOT atomic - if it fails, entity is already persisted.
  /// Best-effort semantics: log errors but don't propagate them.
  @override
  Future<void> afterSave(T entity) async {
    if (entity is! Versionable) return;
    if (versionRepository == null) return;

    try {
      // For non-transactional saves, record version asynchronously after save
      final previousEntity = await versionRepository.findByUuid(entity.uuid);
      final previousJson = (previousEntity is Versionable)
          ? (previousEntity as dynamic).toJson() as Map<String, dynamic>?
          : null;

      final currentJson = (entity as dynamic).toJson() as Map<String, dynamic>;

      // Calculate version number
      final latestVersion = await versionRepository.getLatestVersionNumber(entity.uuid);
      final newVersionNumber = latestVersion + 1;

      // Compute delta
      final previousState = previousJson ?? {};
      final delta = JsonDiff.diff(previousState, currentJson);
      final deltaJson = jsonEncode(delta);
      final changedFields = JsonDiff.extractChangedFields(previousState, currentJson);

      final versionableEntity = entity as Versionable;
      final isFirstVersion = newVersionNumber == 1;
      final isPeriodicSnapshot = versionableEntity.snapshotFrequency != null &&
          newVersionNumber % versionableEntity.snapshotFrequency! == 1;
      final shouldSnapshot = isFirstVersion || isPeriodicSnapshot;

      final version = EntityVersion(
        entityType: T.toString(),
        entityUuid: entity.uuid,
        timestamp: DateTime.now(),
        versionNumber: newVersionNumber,
        deltaJson: deltaJson,
        changedFields: changedFields,
        isSnapshot: shouldSnapshot,
        snapshotJson: shouldSnapshot ? jsonEncode(currentJson) : null,
        userId: (entity as dynamic).lastModifiedBy as String?,
      );

      await versionRepository.save(version);
    } catch (e) {
      // Best-effort: log but don't propagate
      // Version recording failure should not fail the entity save
      // ignore: avoid_print
      print('Warning: Version recording failed for entity ${entity.uuid}: $e');
    }
  }

  /// Build version record synchronously for transaction.
  ///
  /// Synchronous because it happens inside a transaction and must
  /// complete before entity save.
  EntityVersion _buildVersionSync(
    TransactionContext ctx,
    Versionable entity,
  ) {
    // Fetch previous state synchronously within transaction
    final previousEntity = findByUuidSync(ctx, (entity as BaseEntity).uuid);
    final previousJson = (previousEntity is Versionable)
        ? (previousEntity as dynamic).toJson() as Map<String, dynamic>?
        : null;

    final currentJson = (entity as dynamic).toJson() as Map<String, dynamic>;

    // Calculate version number
    final latestVersion =
        getLatestVersionNumberSync(ctx, (entity as BaseEntity).uuid);
    final newVersionNumber = latestVersion + 1;

    // Compute delta
    final previousState = previousJson ?? {};
    final delta = JsonDiff.diff(previousState, currentJson);
    final deltaJson = jsonEncode(delta);
    final changedFields =
        JsonDiff.extractChangedFields(previousState, currentJson);

    final isFirstVersion = newVersionNumber == 1;
    final isPeriodicSnapshot = entity.snapshotFrequency != null &&
        newVersionNumber % entity.snapshotFrequency! == 1;
    final shouldSnapshot = isFirstVersion || isPeriodicSnapshot;

    return EntityVersion(
      entityType: T.toString(),
      entityUuid: (entity as BaseEntity).uuid,
      timestamp: DateTime.now(),
      versionNumber: newVersionNumber,
      deltaJson: deltaJson,
      changedFields: changedFields,
      isSnapshot: shouldSnapshot,
      snapshotJson: shouldSnapshot ? jsonEncode(currentJson) : null,
      userId: (entity as dynamic).lastModifiedBy as String?,
    );
  }
}
