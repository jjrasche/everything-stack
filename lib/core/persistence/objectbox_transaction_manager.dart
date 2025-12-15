/// # ObjectBoxTransactionManager
///
/// ## What it does
/// ObjectBox implementation of TransactionManager.
/// Wraps Store.runInTransaction to provide platform-agnostic transaction API.
///
/// ## What it enables
/// - ACID transactions using ObjectBox native transaction support
/// - Automatic rollback on exception
/// - Cross-box atomic operations (Note + EntityVersion in one transaction)
/// - VersionableHandler works atomically (Repository references serializable in same thread)
///
/// ## How it works
/// Uses Store.runInTransaction (synchronous variant) with write mode.
/// The work callback executes synchronously within the transaction on the same thread.
/// All box operations (put, get, query) are atomic.
///
/// Why runInTransaction (not runInTransactionAsync)?
/// - Work callback is synchronous (no await needed)
/// - No isolate spawning required (no serialization issues)
/// - Repository references accessible directly (fixes VersionableHandler)
/// - Simpler, cleaner code matching the callback interface contract
/// - Same thread = no "callback across isolate boundary" problem
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
/// Provides ACID transactions using ObjectBox Store.runInTransaction (synchronous).
/// This is the correct variant for synchronous callbacks - no isolate spawning needed.
class ObjectBoxTransactionManager implements TransactionManager {
  final Store _store;

  ObjectBoxTransactionManager(this._store);

  @override
  Future<R> transaction<R>(
    R Function(TransactionContext ctx) work, {
    List<String> objectStores = const [],  // Ignored by ObjectBox
  }) async {
    return _store.runInTransaction<R>(
      TxMode.write,
      () {
        final ctx = ObjectBoxTxContext(_store);
        return work(ctx);
      },
    );
  }
}
