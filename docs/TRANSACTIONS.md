# Transaction Support

## Overview

The persistence layer provides atomic transaction support for multi-entity operations. This ensures that operations like "save entity + record version" succeed or fail together - no partial updates.

## Architecture

### Components

**TransactionContext** - Platform-agnostic marker interface
- `ObjectBoxTxContext` wraps ObjectBox Store
- `IndexedDBTxContext` (future) wraps IndexedDB IdbTransaction

**TransactionManager** - Coordinates atomic operations
- `ObjectBoxTransactionManager` uses `Store.runInTransactionAsync`
- Platform-specific implementations handle their transaction APIs

**PersistenceAdapter** - Dual API for normal and transactional operations
- Async methods (`save`, `delete`) for standalone operations
- Sync methods (`saveInTx`, `deleteInTx`) for use within transactions
- Adapters cast TransactionContext to their platform type

### Transaction Flow

```dart
// 1. Repository receives TransactionManager
final txManager = ObjectBoxTransactionManager(store);
final repo = NoteRepository(
  adapter: NoteObjectBoxAdapter(store),
  transactionManager: txManager,
);

// 2. Save triggers transaction
await repo.save(note);  // For Versionable entities

// 3. Inside transaction (synchronous callback)
txManager.transaction((ctx) {
  // Build version
  final version = _buildVersion(ctx, note);

  // Save version
  versionAdapter.saveInTx(ctx, version);

  // Save entity
  return noteAdapter.saveInTx(ctx, note).id;
});
```

## What's Atomic

✅ **Save Versionable Entity**
- Entity save + version record (both succeed or both rollback)

✅ **Batch Save Versionable Entities**
- All entities + all versions (future)

✅ **Delete with Cleanup** (future)
- Delete entity + delete edges + delete versions

❌ **What's NOT Atomic**
- Embedding generation (happens before transaction)
- Operations without TransactionManager
- Cross-platform operations (ObjectBox + Web Storage)

## Platform Semantics

### ObjectBox

**Transaction API**: `Store.runInTransactionAsync<R>(TxMode, callback, param)`

**Behavior**:
- ACID-compliant write transactions
- Runs on worker isolate
- Callback must be synchronous (no `await`)
- Automatic rollback on exception
- Sequential execution (one write transaction at a time)

**Limitations**:
- No nested transactions
- Callback receives synchronous Store instance
- All box operations must complete in callback

### IndexedDB (Future)

**Transaction API**: `IdbDatabase.transaction(objectStores, mode)`

**Behavior**:
- ACID-compliant transactions
- Must declare object stores upfront
- Auto-commits after microtask queue empties
- No async operations (fetch, setTimeout) mid-transaction

**Limitations**:
- Must know all object stores before creating transaction
- Auto-commit on microtask completion
- Cannot span async boundaries

## Implementation Guide

### For Entity Repositories

Repositories declare which object stores they access:

```dart
class NoteRepository extends EntityRepository<Note> {
  @override
  List<String> get transactionStores => [
    'notes',
    if (versionRepository != null) 'entity_versions',
  ];
}
```

For complex transaction logic, override in concrete repository:

```dart
@override
Future<int> save(Note entity) async {
  if (entity is Versionable && transactionManager != null) {
    // Custom transaction logic
    return await transactionManager!.transaction((ctx) {
      // ... entity-specific logic
    }, objectStores: transactionStores);
  }
  return super.save(entity);
}
```

### For Adapters

Implement both async and sync APIs:

```dart
class NoteObjectBoxAdapter implements PersistenceAdapter<Note> {
  // Async for normal use
  @override
  Future<Note> save(Note entity) async {
    entity.touch();
    _box.put(entity);
    return entity;
  }

  // Sync for transactions
  @override
  Note saveInTx(TransactionContext ctx, Note entity) {
    final obCtx = ctx as ObjectBoxTxContext;
    entity.touch();
    obCtx.store.box<Note>().put(entity);
    return entity;
  }
}
```

## Testing

Transaction atomicity is verified in:
- `test/persistence/objectbox_transaction_test.dart` - Basic transaction behavior
- `test/persistence/cross_repository_transaction_test.dart` - Cross-entity atomicity

Tests verify:
- ✅ Multi-entity operations are atomic
- ✅ Exceptions trigger rollback
- ✅ Partial failures rollback everything
- ✅ Read-your-writes consistency

## Known Limitations

1. **Generic EntityRepository transaction logic is limited**
   - Cannot do entity-specific queries generically
   - Concrete repositories override for complex transactions

2. **Embedding generation not atomic**
   - Generated before transaction (async operation)
   - Transaction only covers save + version

3. **No cross-platform atomicity**
   - ObjectBox and IndexedDB cannot share transactions
   - Platform choice determines transaction boundary

4. **Version querying in transactions**
   - Need synchronous version lookup
   - Currently returning default version number (will be fixed)

## Future Enhancements

- [ ] Add sync query methods to VersionRepository
- [ ] Implement saveAll with transactions
- [ ] Add delete with cleanup transactions
- [ ] IndexedDB transaction support
- [ ] Expose transaction API to domain code for custom use cases
