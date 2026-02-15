/// Platform-agnostic interface for executing database transactions.
/// Coordinates atomic operations across multiple adapters.

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
