/// ObjectBox implementation of TransactionManager.
///
/// ## Why runInTransaction (not runInTransactionAsync)
/// Uses synchronous variant because work callbacks are synchronous (no await needed),
/// repository references are accessible directly on the same thread (no isolate
/// boundary issues), and it avoids serialization problems with VersionableHandler.

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
    List<String> objectStores = const [], // Ignored by ObjectBox
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
