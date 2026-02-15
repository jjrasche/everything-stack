/// Cascades edge deletion when an entity is deleted.
///
/// ## Why atomic deletion is required
/// Orphaned edges pointing to deleted entities cause data corruption.
/// All edges (inbound and outbound) are deleted in the same transaction as
/// the entity to maintain consistency.

import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import '../edge_repository.dart';
import '../repository_pattern_handler.dart';

/// Handler for cascading edge deletion.
///
/// Responsible for:
/// - Collecting edge IDs before transaction (beforeDelete, outside tx)
/// - Deleting collected edges atomically within delete transaction (beforeDeleteInTransaction, inside tx)
///
/// ARCHITECTURAL CONSTRAINT:
/// Edge cascade deletion REQUIRES EntityRepository to have:
/// 1. EdgeRepository injected (via setEdgeRepository or repository constructor)
/// 2. TransactionManager for atomicity
///
/// Without TransactionManager:
/// - beforeDelete collects and deletes edges (non-atomic fallback)
/// - beforeDeleteInTransaction is never called without a transaction
/// - Edge cascade delete still happens but without atomicity
/// - This is acceptable for entities where edges are optional
///
/// For entities that MUST cascade delete edges atomically (e.g., Note), ensure:
/// - EdgeRepository is set before deleting
/// - TransactionManager is provided to the repository
///
class EdgeCascadeDeleteHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final EdgeRepository edgeRepository;

  /// Cached edge UUIDs for the current delete operation.
  /// Set in beforeDelete, used in beforeDeleteInTransaction.
  List<String>? _edgeIdsToDelete;

  EdgeCascadeDeleteHandler({
    required this.edgeRepository,
  });

  /// Collect edge IDs before transaction (outside transaction, fail-fast).
  ///
  /// This runs before the delete transaction and collects all edge IDs
  /// that need to be deleted. If edge collection fails, delete is aborted.
  ///
  /// Fail-fast semantics ensure we don't start a transaction if we can't
  /// determine which edges to delete.
  @override
  Future<void> beforeDelete(T entity) async {
    _edgeIdsToDelete = await edgeRepository.getEdgeIdsForEntity(entity.uuid);
  }

  /// Delete collected edges within transaction (atomic with entity delete).
  ///
  /// Called BEFORE entity is deleted, within the delete transaction.
  /// Uses pre-collected edge IDs from beforeDelete.
  ///
  /// This ensures that if edge deletion fails, the transaction rolls back
  /// and the entity is not deleted.
  ///
  /// Only called when TransactionManager is provided.
  @override
  void beforeDeleteInTransaction(TransactionContext ctx, T entity) {
    final edgeIds = _edgeIdsToDelete ?? [];
    if (edgeIds.isEmpty) return;

    edgeRepository.deleteEdgesInTx(ctx, edgeIds);

    _edgeIdsToDelete = null;
  }
}
