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
/// - Recording entity version atomically within save transaction
///
/// ARCHITECTURAL CONSTRAINT:
/// Version recording REQUIRES TransactionManager. This is a hard requirement
/// because version history must be atomic with entity save - an entity without
/// its version history is data corruption.
///
/// Without TransactionManager:
/// - VersionableHandler only records versions in beforeSaveInTransaction
/// - beforeSaveInTransaction is never called without a transaction
/// - Versionable entities are saved WITHOUT version history
/// - This matches pre-handler behavior when transactionManager is not provided
///
/// Production systems using Versionable entities MUST provide TransactionManager.
/// For ObjectBox on native platforms, use ObjectBoxTransactionManager(store).
/// For Web with IndexedDB, transaction support is built into IndexedDB.
///
/// This is not a limitation of the handler pattern - it's a fundamental
/// requirement of reliable version tracking.
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
