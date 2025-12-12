/// # IndexedDBTransactionManager
///
/// ## What it does
/// IndexedDB implementation of TransactionManager.
/// Wraps IdbDatabase.transaction to provide platform-agnostic transaction API.
///
/// ## What it enables
/// - ACID transactions using IndexedDB native transaction support
/// - Automatic rollback on exception
/// - Cross-store atomic operations (Note + EntityVersion in one transaction)
///
/// ## How it works
/// Uses Database.transaction with readwrite mode.
/// The work callback executes asynchronously within the transaction.
/// All object store operations (put, get, query) are atomic.
///
/// ## Important differences from ObjectBox
/// - Must declare object stores upfront via objectStores parameter
/// - Work callback is async (can use await inside)
/// - Transaction auto-commits when all promises complete
/// - Transaction auto-aborts on uncaught exception
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final txManager = IndexedDBTransactionManager(db);
///
/// final repo = NoteRepository(
///   adapter: NoteIndexedDBAdapter(db),
///   transactionManager: txManager,
/// );
///
/// // Must specify object stores
/// await repo.save(note);  // Internally: objectStores: ['notes', 'entity_versions']
/// ```
///
/// ## Limitations
/// - Must know all object stores upfront (IndexedDB requirement)
/// - Nested transactions not supported
/// - IndexedDB-specific (not cross-platform)
///
/// ## Testing approach
/// Verified in test/persistence/indexeddb_transaction_test.dart
/// and test/persistence/cross_repository_transaction_test.dart

import 'package:idb_shim/idb.dart';
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

    // Create transaction with readwrite mode
    final txn = _db.transaction(objectStores, idbModeReadWrite);
    final ctx = IndexedDBTxContext(txn);

    try {
      // Execute work callback
      final result = work(ctx);

      // Wait for transaction to complete
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
