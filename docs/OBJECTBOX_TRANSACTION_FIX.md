# ObjectBox Transaction API Fix: runInTransaction vs runInTransactionAsync

## Executive Summary

**Status:** ✅ Fixed

The codebase was using `Store.runInTransactionAsync()` for synchronous database operations. This caused isolate serialization failures that prevented VersionableHandler from accessing Repository references.

**Solution:** Use `Store.runInTransaction()` (synchronous variant) instead.

**Impact:**
- ✅ VersionableHandler now works atomically with ObjectBox
- ✅ Atomic version recording for all Versionable entities
- ✅ No isolate overhead for synchronous operations
- ✅ All integration tests pass

---

## The Problem

### What Was Happening

```dart
// OLD: ObjectBoxTransactionManager (WRONG)
return await _store.runInTransactionAsync<R, void>(
  TxMode.write,
  (txStore, _) {  // ← Isolate boundary - causes serialization failure
    final ctx = ObjectBoxTxContext(txStore);
    return work(ctx);
  },
  null,  // ← Parameters passed via isolate
);
```

The callback was **100% synchronous** (no `await` anywhere), but we used the async API which:
1. Spawns a new isolate
2. Tries to serialize all parameters across the isolate boundary
3. Store reference can't serialize (contains native pointers)
4. Any Repository reference captured in `work` callback can't serialize
5. **Isolate serialization fails** → VersionableHandler can't call `versionRepository.saveInTx(ctx, ...)`

### Why This Mattered

VersionableHandler needs to record versions atomically within the entity save transaction:

```dart
// VersionableHandler.dart
void beforeSaveInTransaction(TransactionContext ctx, T entity) {
  if (entity is! Versionable) return;
  if (versionRepository == null) return;

  final version = _buildVersionSync(ctx, entity as Versionable);

  // THIS FAILS with runInTransactionAsync:
  // versionRepository reference can't serialize across isolate boundary
  versionRepository.saveInTx(ctx, version);  // ← Isolate serialization error
}
```

Without atomic versioning, entities save but versions don't get recorded → data integrity issue.

---

## The Solution

### What Changed

```dart
// NEW: ObjectBoxTransactionManager (CORRECT)
return _store.runInTransaction<R>(
  TxMode.write,
  () {
    final ctx = ObjectBoxTxContext(_store);
    return work(ctx);  // ← Same thread, no isolate boundary
  },
);
```

**Three differences:**
1. `runInTransactionAsync` → `runInTransaction`
2. No `await` (returns directly)
3. Callback is `() { }` not `(txStore, _) { }`

### Why This Is Right

The ObjectBox API provides two variants for exactly this use case:

| Method | Callback Type | Threading | Best For |
|--------|--------------|-----------|----------|
| `runInTransaction()` | Synchronous: `R fn()` | Same thread | Sync operations (no isolate needed) |
| `runInTransactionAsync()` | Async callback in isolate | Separate thread | When you need actual async work |

**Our callback is synchronous**, so `runInTransaction()` is the correct choice:

```dart
// EntityRepository._saveWithHandlersInTransaction() is SYNCHRONOUS
int _saveWithHandlersInTransaction(TransactionContext ctx, T entity) {
  // Phase 2: beforeSaveInTransaction (sync)
  for (final handler in handlers) {
    handler.beforeSaveInTransaction(ctx, entity);  // ← No await
  }

  // Phase 3: Persist entity (sync)
  final saved = adapter.saveInTx(ctx, entity);  // ← No await

  // Phase 4: afterSaveInTransaction (sync)
  for (final handler in handlers) {
    handler.afterSaveInTransaction(ctx, entity);  // ← No await
  }

  return saved.id;  // ← Returns directly
}
```

And the TransactionManager interface explicitly documents (line 52-54):
```dart
/// [work] - Synchronous callback that performs database operations.
///          Must complete synchronously (no await inside).
```

---

## Test Results

### All Transaction Tests Pass ✅

**ObjectBox Transaction Support (4/4)**
- ✅ runInTransaction executes atomically
- ✅ runInTransaction rolls back on exception
- ✅ runInTransaction with synchronous adapter pattern
- ✅ verify Box operations are synchronous

**Cross-Repository Transactions (4/4)**
- ✅ save entity + version atomically using adapters
- ✅ rollback works for entity + version
- ✅ partial failure rolls back everything
- ✅ multiple entities + versions in single transaction

**Handler Edge Cases (10/10)**
- ✅ beforeSave failure aborts save (fail-fast)
- ✅ afterSave failure does not abort save (best-effort)
- ✅ handler failure with multiple patterns does not skip remaining
- ✅ Multi-pattern save executes all handlers in order
- ✅ Multi-pattern delete executes beforeDelete hooks
- ✅ saveAll applies handlers to each entity
- ✅ saveAll continues on handler failure per entity
- ✅ delete non-existent entity returns false
- ✅ delete with handler failure aborts deletion

---

## Benefits

### 1. Atomic Versioning Works

```dart
// Now this works correctly:
final repo = NoteRepository(
  adapter: noteAdapter,
  versionRepository: versionRepo,
  transactionManager: ObjectBoxTransactionManager(store),  // ✅ Works now
);

await repo.save(note);  // Entity + version saved atomically
```

### 2. No Isolate Overhead

- ✅ No isolate spawning for every transaction
- ✅ No serialization overhead
- ✅ Same thread execution = direct Repository access
- ✅ Simpler, clearer code

### 3. Matches API Contract

The TransactionManager interface specifies synchronous callbacks. Using `runInTransaction()` aligns with that contract perfectly.

### 4. Better Performance

Eliminating isolate spawning removes unnecessary threading overhead for single-threaded operations.

---

## When This Was Used

The async approach was likely chosen without realizing the sync variant exists and is the right fit for synchronous work. This is a common mistake when first encountering ObjectBox's API.

**Indicators it was a default choice:**
- No batch/bulk operations utilizing async parallelism
- No performance-tuning documentation
- Sequential `saveAll()` implementation (each entity gets own transaction)
- Explicit "must be synchronous" documentation in the callback interface
- No evidence of throughput optimization attempting to justify async

---

## Related Patterns

### Bulk Save Optimization (Future)

The current `saveAll()` uses sequential saves (each with own transaction):

```dart
// Current: Sequential saves
Future<void> saveAll(List<T> entities) async {
  for (final entity in entities) {
    await save(entity);  // N entities = N transactions
  }
}
```

For future optimization with high-throughput scenarios (hundreds of writes/sec), you could batch them:

```dart
// Future optimization: Bulk transaction
Future<void> saveAll(List<T> entities) async {
  await transactionManager!.transaction(
    (ctx) {
      for (final entity in entities) {
        adapter.saveInTx(ctx, entity);
      }
      return null;
    },
    objectStores: transactionStores,
  );
}
```

But this is **optional** - current sequential approach works fine for typical usage patterns.

---

## Documentation References

### ObjectBox API

- [ObjectBox Store.runInTransaction() documentation](https://pub.dev/documentation/objectbox/latest/objectbox/Store-class.html)
- [ObjectBox Transactions](https://docs.objectbox.io/transactions)
- [Why Different APIs](https://objectbox.io/flutter-database-2-0/)

### Codebase

- `lib/core/persistence/objectbox_transaction_manager.dart` - Implementation
- `lib/core/handlers/versionable_handler.dart` - Uses atomic transactions
- `test/persistence/objectbox_transaction_test.dart` - Integration tests
- `test/persistence/cross_repository_transaction_test.dart` - Cross-entity atomicity
- `test/services/handler_edge_cases_test.dart` - Handler lifecycle tests

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| **API Used** | `runInTransactionAsync()` | `runInTransaction()` |
| **Callback Type** | Async (in isolate) | Sync (same thread) |
| **Serialization** | Yes (causes failure) | No |
| **VersionableHandler Works** | ❌ No | ✅ Yes |
| **Isolate Overhead** | Yes (unnecessary) | No |
| **Atomicity** | ❌ Partial (entity without version) | ✅ Full (entity + version) |
| **Test Status** | N/A | ✅ All pass |

**Conclusion:** Using the synchronous transaction variant aligns with the synchronous callback contract, eliminates isolate serialization failures, and enables atomic version recording for all Versionable entities.
