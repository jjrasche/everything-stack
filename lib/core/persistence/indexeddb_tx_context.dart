/// IndexedDB-specific TransactionContext wrapping a Transaction for object store access.

import 'dart:indexed_db' as idb;
import 'transaction_context.dart';

/// IndexedDB transaction context.
///
/// Provides access to the Transaction instance within a transaction.
/// Adapters use this to get object stores and perform async operations.
class IndexedDBTxContext implements TransactionContext {
  /// The IndexedDB Transaction for this transaction.
  /// Use transaction.objectStore(name) to access object stores.
  final Transaction transaction;

  IndexedDBTxContext(this.transaction);

  /// Get an object store by name.
  /// Convenience method to avoid direct access to transaction.
  ObjectStore objectStore(String name) {
    return transaction.objectStore(name);
  }
}
