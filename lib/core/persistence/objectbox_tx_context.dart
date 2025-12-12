/// # ObjectBoxTxContext
///
/// ## What it does
/// ObjectBox-specific implementation of TransactionContext.
/// Wraps an ObjectBox Store to provide access to boxes within a transaction.
///
/// ## Usage
/// ```dart
/// class NoteObjectBoxAdapter implements PersistenceAdapter<Note> {
///   @override
///   Note saveInTx(TransactionContext ctx, Note entity) {
///     final obCtx = ctx as ObjectBoxTxContext;
///     entity.touch();
///     obCtx.store.box<Note>().put(entity);
///     return entity;
///   }
/// }
/// ```

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
