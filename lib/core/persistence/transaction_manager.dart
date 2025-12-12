/// # TransactionManager
///
/// ## What it does
/// Platform-agnostic interface for executing database transactions.
/// Coordinates atomic operations across multiple adapters.
///
/// ## What it enables
/// - Atomic multi-entity operations (save note + version together)
/// - Cross-repository transactions (note + edges + versions)
/// - Platform-specific transaction implementations
/// - Repository code independent of persistence backend
///
/// ## How it works
/// Implementations wrap platform-specific transaction APIs:
/// - ObjectBoxTransactionManager: Uses Store.runInTransactionAsync
/// - IndexedDBTransactionManager: Uses IdbDatabase.transaction
///
/// The work callback receives a TransactionContext for accessing
/// platform-specific transaction primitives.
///
/// ## Usage
/// ```dart
/// // In EntityRepository
/// await transactionManager.transaction(
///   (ctx) {
///     // All operations are atomic
///     versionAdapter.saveInTx(ctx, version);
///     return adapter.saveInTx(ctx, entity).id;
///   },
///   objectStores: ['notes', 'entity_versions'],  // For IndexedDB
/// );
/// ```
///
/// ## Platform implementations
/// - ObjectBoxTransactionManager: lib/core/persistence/objectbox_transaction_manager.dart
/// - IndexedDBTransactionManager: (future)
///
/// ## Testing approach
/// Test through repositories. Verify:
/// - Multi-entity saves are atomic (both succeed or both rollback)
/// - Exceptions trigger rollback
/// - Read-your-writes consistency within transaction

import 'transaction_context.dart';

/// Platform-agnostic transaction coordinator.
///
/// Executes work within a database transaction, ensuring ACID properties.
abstract class TransactionManager {
  /// Execute work within a transaction.
  ///
  /// [work] - Synchronous callback that performs database operations.
  ///          Receives a TransactionContext for accessing platform primitives.
  ///          Must complete synchronously (no await inside).
  ///          Returns result of type R.
  ///
  /// [objectStores] - Object stores to access (IndexedDB requirement).
  ///                  ObjectBox ignores this parameter.
  ///                  IndexedDB requires declaring stores upfront.
  ///
  /// Returns the result of the work callback.
  ///
  /// Throws any exception from the work callback after rolling back the transaction.
  ///
  /// Example:
  /// ```dart
  /// final noteId = await txManager.transaction(
  ///   (ctx) {
  ///     versionAdapter.saveInTx(ctx, version);
  ///     return noteAdapter.saveInTx(ctx, note).id;
  ///   },
  ///   objectStores: ['notes', 'entity_versions'],
  /// );
  /// ```
  Future<R> transaction<R>(
    R Function(TransactionContext ctx) work, {
    List<String> objectStores = const [],
  });
}
