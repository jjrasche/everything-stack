/// # TransactionContext
///
/// ## What it does
/// Platform-agnostic marker interface for transaction contexts.
/// Allows adapters to participate in transactions without knowing
/// the specific platform (ObjectBox, IndexedDB, etc.).
///
/// ## What it enables
/// - Cross-adapter atomic operations (save entity + version together)
/// - Platform-specific transaction implementations
/// - Adapter code stays generic (PersistenceAdapter interface)
///
/// ## How it works
/// Platform-specific implementations provide their transaction primitives:
/// - ObjectBoxTxContext wraps Store (for accessing boxes)
/// - IndexedDBTxContext wraps IdbTransaction (for accessing object stores)
///
/// Adapters cast to their platform type to access the underlying transaction.
///
/// ## Usage
/// ```dart
/// // In adapter implementation
/// @override
/// Note saveInTx(TransactionContext ctx, Note entity) {
///   final obCtx = ctx as ObjectBoxTxContext;  // Platform-specific cast
///   entity.touch();
///   obCtx.store.box<Note>().put(entity);
///   return entity;
/// }
/// ```
///
/// ## Platform implementations
/// - ObjectBoxTxContext: lib/core/persistence/objectbox_tx_context.dart
/// - IndexedDBTxContext: (future) lib/core/persistence/indexeddb_tx_context.dart

/// Marker interface for platform-specific transaction contexts.
///
/// Do not implement this directly. Use platform-specific subclasses:
/// - ObjectBoxTxContext for ObjectBox transactions
/// - IndexedDBTxContext for IndexedDB transactions
abstract class TransactionContext {
  // Marker interface - no methods
  // Platform implementations provide their specific transaction primitives
}
