/// IndexedDB implementation of TransactionManager.
///
/// ## Why object stores must be declared upfront
/// IndexedDB requires declaring all object stores at transaction creation time
/// (unlike ObjectBox which ignores this parameter). The objectStores parameter
/// on transaction() exists specifically for this IndexedDB requirement.

import 'dart:indexed_db' as idb;
import 'transaction_context.dart';
import 'indexeddb_tx_context.dart';
import 'transaction_manager.dart';

/// IndexedDB transaction coordinator.
///
/// Provides ACID transactions using IndexedDB Database.transaction.
class IndexedDBTransactionManager implements TransactionManager {
  final Database _db;

  IndexedDBTransactionManager(this._db);

  @override
  Future<R> transaction<R>(
    R Function(TransactionContext ctx) work, {
    List<String> objectStores = const [],
  }) async {
    if (objectStores.isEmpty) {
      throw ArgumentError(
        'IndexedDB requires object stores to be declared upfront. '
        'Pass objectStores parameter to transaction().',
      );
    }

    final txn = _db.transaction(objectStores, idbModeReadWrite);
    final ctx = IndexedDBTxContext(txn);

    try {
      final result = work(ctx);

      await txn.completed;

      return result;
    } catch (error) {
      // Transaction auto-aborts on error
      // Try to abort explicitly if not already aborted
      try {
        txn.abort();
      } catch (_) {
        // Already aborted or completed
      }
      rethrow;
    }
  }
}
