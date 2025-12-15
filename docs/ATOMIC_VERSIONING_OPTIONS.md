# Atomic Versioning Options for Everything Stack

## Problem Statement - RESOLVED ✅

The handler pattern's VersionableHandler requires atomic transactions to ensure data consistency:
- Entity save and version recording must succeed or fail together
- Partial saves (entity without version) = data corruption

**Status:** ObjectBox now works perfectly for atomic versioning!

Previously, ObjectBoxTransactionManager used `runInTransactionAsync()` which caused isolate serialization failures. This has been fixed by using `runInTransaction()` instead. See [OBJECTBOX_TRANSACTION_FIX.md](./OBJECTBOX_TRANSACTION_FIX.md) for details.

## Your Options

### Option 1: Use IndexedDB (Web Platform) ✅ RECOMMENDED FOR WEB

**Status:** Fully supported, no workarounds needed

IndexedDBTransactionManager works perfectly with the handler pattern:

```dart
// Web setup - works atomically
final db = await idbFactory.open('my_database');
final txManager = IndexedDBTransactionManager(db);

final noteRepo = NoteRepository(
  adapter: NoteIndexedDBAdapter(db),
  transactionManager: txManager,  // ✅ Works perfectly - no isolate issues
  versionRepo: versionRepo,
);

// Atomic versioning works out of the box
await noteRepo.save(note);  // Entity + version recorded atomically
```

**Why this works:**
- IndexedDB transactions don't use isolates
- Work callback is async (can use await)
- All operations happen on same thread
- VersionableHandler's `beforeSaveInTransaction` executes correctly

**Trade-off:** Web platform only (no native apps)

---

### Option 2: ObjectBox on Native Platforms ✅ NOW WORKING

**Status:** Fixed! ObjectBox now supports atomic versioning perfectly.

The issue was using `Store.runInTransactionAsync()` for synchronous operations. This has been fixed by switching to `Store.runInTransaction()`.

```dart
// Native setup - works atomically now
final store = await openStore();
final txManager = ObjectBoxTransactionManager(store);

final noteRepo = NoteRepository(
  adapter: NoteObjectBoxAdapter(store),
  transactionManager: txManager,  // ✅ Works perfectly - no isolate issues
  versionRepo: versionRepo,
);

// Atomic versioning works on native platforms
await noteRepo.save(note);  // Entity + version recorded atomically
```

**Why this works:**
- Uses `runInTransaction()` (synchronous variant)
- No isolate spawning = no serialization issues
- Repository references work directly
- VersionableHandler's `beforeSaveInTransaction` executes correctly
- All tests pass

See [OBJECTBOX_TRANSACTION_FIX.md](./OBJECTBOX_TRANSACTION_FIX.md) for technical details.

### Option 3 (Deprecated): Use Different Native Database ⚠️ NO LONGER NEEDED

**Status:** Deprecated - ObjectBox now works perfectly

Previously, you could replace ObjectBox with SQLite/Realm, but this is no longer necessary since ObjectBox atomic versioning now works correctly.

---

### Option 3: Accept Non-Atomic Versioning (OPTIONAL - Only If You Don't Want Versioning)

**Status:** Optional - only use if you explicitly don't need version tracking

If you choose not to enable atomic versioning (perhaps versioning is not a requirement for your use case):

**What this means:**
- Don't provide TransactionManager to the repository
- Versionable entities are saved, but version history is not recorded
- Pattern composes correctly, versioning is just skipped

**When to use this:**
- Versionable entities are not needed for your app
- Version tracking is not a feature you want

**Implementation:**
```dart
// Skip transactionManager if you don't want atomic versioning
final noteRepo = NoteRepository(
  adapter: noteAdapter,
  embeddingService: embeddingService,
  versionRepo: versionRepo,
  // Don't provide transactionManager = no version recording
);
```

**Recommendation:** Now that ObjectBox atomic versioning works, you should provide TransactionManager and get version tracking automatically.

---

### Option 4 (Deprecated): Custom ObjectBox Transaction Wrapper ⚠️ NO LONGER NEEDED

**Status:** Deprecated - ObjectBox atomic versioning now works correctly

This option was previously suggested as a workaround but is no longer needed since the fix uses the correct ObjectBox API. Option 2 (ObjectBox with correct API) now provides atomic versioning without any workarounds.

---

## Recommendation by Use Case

### 🎯 Native App (Android, iOS, macOS, Windows, Linux)
**→ Use Option 2: ObjectBox + ObjectBoxTransactionManager**
- ✅ Works perfectly - atomic versioning guaranteed
- ✅ No workarounds needed
- ✅ All tests pass
- ✅ Recommended

### 🎯 Web App
**→ Use Option 1: IndexedDB + IndexedDBTransactionManager**
- ✅ Works perfectly - atomic versioning guaranteed
- ✅ No workarounds needed
- ✅ Recommended

### 🎯 Cross-Platform (Native + Web) WITH Atomic Versioning
**→ Use Option 2 (Native) + Option 1 (Web)**
- ObjectBox on native platforms (with TransactionManager)
- IndexedDB on web
- Atomic versioning everywhere
- **Recommended**

### 🎯 If You Don't Need Version Tracking
**→ Use Option 3: Skip TransactionManager**
- Works on any platform
- No version history recorded
- Simpler if versioning is not needed

---

## Implementation Path: Cross-Platform with Atomic Versioning

For native + web apps with atomic versioning everywhere:

### On Native Platforms (ObjectBox)

1. **Already implemented and fixed:**
   - `lib/core/persistence/objectbox_transaction_manager.dart` - Uses correct API
   - `lib/persistence/objectbox/*adapter.dart` - All adapters ready
   - Full test coverage with all tests passing

2. **Use in your app:**
   ```dart
   final store = await openStore();
   final txManager = ObjectBoxTransactionManager(store);

   final noteRepo = NoteRepository(
     adapter: NoteObjectBoxAdapter(store),
     transactionManager: txManager,
     versionRepo: versionRepo,
   );
   ```

3. **Test coverage:**
   - `test/persistence/objectbox_transaction_test.dart` - 4/4 passing
   - `test/persistence/cross_repository_transaction_test.dart` - 4/4 passing
   - `test/services/handler_edge_cases_test.dart` - 10/10 passing

### On Web (IndexedDB)

1. **Already exists in codebase:**
   ```
   ✓ lib/persistence/indexeddb/note_indexeddb_adapter.dart
   ✓ lib/persistence/indexeddb/entity_version_indexeddb_adapter.dart
   ✓ lib/core/persistence/indexeddb_transaction_manager.dart
   ```

2. **Use in your app:**
   ```dart
   final db = await idbFactory.open('everything_stack');
   final txManager = IndexedDBTransactionManager(db);

   final noteRepo = NoteRepository(
     adapter: NoteIndexedDBAdapter(db),
     transactionManager: txManager,
     versionRepo: versionRepo,
   );
   ```

3. **Test coverage:**
   - IndexedDB transaction tests pass
   - Handler edge cases already pass with this setup

---

## Technical Details: The Fix

**Previous Implementation (WRONG):**
```
Used: Store.runInTransactionAsync() - Spawns isolate
  - Isolate spawning for synchronous callback (unnecessary)
  - Serialization attempts fail (Store has native pointers)
  - Repository references can't serialize across boundary
  - VersionableHandler fails when calling versionRepository
```

**Current Implementation (CORRECT):**
```
Uses: Store.runInTransaction() - Same thread
  - Synchronous callback on same thread (no isolate)
  - No serialization needed
  - Direct Repository reference access
  - VersionableHandler works atomically
```

**Why ObjectBox Has Both APIs:**
- `runInTransaction()` - For synchronous operations (no isolate overhead)
- `runInTransactionAsync()` - For when you need async work inside transaction

**Key Insight:** Our code is 100% synchronous, so using the async API was a mismatch. Using the sync API eliminates the isolate serialization problem entirely.

---

## Decision Framework

| Criteria | ObjectBox (Fixed) | IndexedDB | Alternative DB |
|----------|------------------|-----------|-----------------|
| **Atomic versioning** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Native platforms** | ✅ Yes | ❌ No* | ✅ Yes |
| **Web platform** | ❌ No* | ✅ Yes | ✅ Yes |
| **Effort to implement** | ✅ 0 (done) | ✅ 0 (exists) | ⚠️ High |
| **Production ready** | ✅ Yes | ✅ Yes | ⚠️ Maybe |
| **Cross-platform** | ⚠️ Mixed** | ⚠️ Mixed** | ✅ Yes |
| **Recommended** | ✅ YES (native) | ✅ YES (web) | ❌ Not needed |

*ObjectBox has no web support - platform-specific only
**Use ObjectBox on native, IndexedDB on web for atomic versioning everywhere

---

## Action Items

- [x] **✅ DONE:** Fix ObjectBoxTransactionManager to use `runInTransaction()`
- [x] **✅ DONE:** All integration tests passing (18/18)
- [x] **✅ DONE:** Update documentation
- [ ] **For new projects:** Enable TransactionManager for atomic versioning
- [ ] **For existing projects:** No changes needed - use the fixed TransactionManager

---

## Summary

| What You Get | ObjectBox (Native) | IndexedDB (Web) | Alternative DB |
|--------------|-------------------|-----------------|-----------------|
| **Atomic Versioning** | ✅ Yes (FIXED!) | ✅ Yes | ✅ Yes |
| **Ready Today** | ✅ Yes | ✅ Yes | ❌ No |
| **Effort** | 0 (already done) | 0 (already done) | High |
| **Scalability** | Good | Good | Best |
| **Recommended** | ✅ YES (native) | ✅ YES (web) | ❌ Not needed |

**Best path forward:**
- **Native apps (Android, iOS, desktop):** Use ObjectBox + ObjectBoxTransactionManager → ✅ Atomic versioning works
- **Web apps:** Use IndexedDB + IndexedDBTransactionManager → ✅ Atomic versioning works
- **Cross-platform:** Use ObjectBox on native + IndexedDB on web → ✅ Atomic versioning everywhere

**No workarounds needed anymore. The fix is complete and all tests pass.**
