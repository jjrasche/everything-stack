/// # ObjectBoxTransactionManager
///
/// ## What it does
/// ObjectBox implementation of TransactionManager.
/// Wraps Store.runInTransactionAsync to provide platform-agnostic transaction API.
///
/// ## What it enables
/// - ACID transactions using ObjectBox native transaction support
/// - Automatic rollback on exception
/// - Cross-box atomic operations (Note + EntityVersion in one transaction)
///
/// ## How it works
/// Uses Store.runInTransactionAsync with write mode.
/// The work callback executes synchronously within the transaction.
/// All box operations (put, get, query) are atomic.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final txManager = ObjectBoxTransactionManager(store);
///
/// final repo = NoteRepository(
///   adapter: NoteObjectBoxAdapter(store),
///   transactionManager: txManager,
/// );
/// ```
///
/// ## Limitations
/// - Work callback must be synchronous (no await inside)
/// - Nested transactions not supported
/// - ObjectBox-specific (not cross-platform)
///
/// ## Testing approach
/// Verified in test/persistence/objectbox_transaction_test.dart
/// and test/persistence/cross_repository_transaction_test.dart

import 'package:objectbox/objectbox.dart';
import 'transaction_context.dart';
import 'objectbox_tx_context.dart';
import 'transaction_manager.dart';

/// ObjectBox transaction coordinator.
///
/// Provides ACID transactions using ObjectBox Store.runInTransactionAsync.
class ObjectBoxTransactionManager implements TransactionManager {
  final Store _store;

  ObjectBoxTransactionManager(this._store);

  @override
  Future<R> transaction<R>(
    R Function(TransactionContext ctx) work, {
    List<String> objectStores = const [],  // Ignored by ObjectBox
  }) async {
    return await _store.runInTransactionAsync<R, void>(
      TxMode.write,
      (txStore, _) {
        final ctx = ObjectBoxTxContext(txStore);
        return work(ctx);
      },
      null,
    );
  }
}
