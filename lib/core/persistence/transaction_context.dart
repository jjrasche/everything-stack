/// Platform-agnostic marker interface for transaction contexts.
///
/// ## Why adapters cast to platform type
/// Adapters cast TransactionContext to their platform-specific subclass
/// (ObjectBoxTxContext, IndexedDBTxContext) to access the underlying
/// transaction primitives. This keeps PersistenceAdapter generic while
/// enabling cross-adapter atomic operations.

/// Marker interface for platform-specific transaction contexts.
///
/// Do not implement this directly. Use platform-specific subclasses:
/// - ObjectBoxTxContext for ObjectBox transactions
/// - IndexedDBTxContext for IndexedDB transactions
abstract class TransactionContext {
  // Marker interface - no methods
  // Platform implementations provide their specific transaction primitives
}
