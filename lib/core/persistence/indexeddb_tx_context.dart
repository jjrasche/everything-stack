/// # IndexedDBTxContext
///
/// ## What it does
/// IndexedDB-specific implementation of TransactionContext.
/// Wraps an IndexedDB Transaction to provide access to object stores within a transaction.
///
/// ## Usage
/// ```dart
/// class NoteIndexedDBAdapter implements PersistenceAdapter<Note> {
///   @override
///   Future<Note> saveInTx(TransactionContext ctx, Note entity) async {
///     final idbCtx = ctx as IndexedDBTxContext;
///     entity.touch();
///     final store = idbCtx.objectStore('notes');
///     await store.put(entity.toJson(), entity.uuid);
///     return entity;
///   }
/// }
/// ```

import 'package:idb_shim/idb.dart';
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
