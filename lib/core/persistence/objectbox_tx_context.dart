/// ObjectBox-specific TransactionContext wrapping a Store for box access within transactions.

import 'package:objectbox/objectbox.dart';
import 'transaction_context.dart';

/// ObjectBox transaction context.
///
/// Provides access to the Store instance within a transaction.
/// Adapters use this to get boxes and perform synchronous operations.
class ObjectBoxTxContext implements TransactionContext {
  /// The ObjectBox Store for this transaction.
  /// Use store.box<T>() to access entity boxes.
  final Store store;

  ObjectBoxTxContext(this.store);
}
