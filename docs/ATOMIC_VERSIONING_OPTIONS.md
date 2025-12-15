# Atomic Versioning Options for Everything Stack

## Problem Statement

The handler pattern's VersionableHandler requires atomic transactions to ensure data consistency:
- Entity save and version recording must succeed or fail together
- Partial saves (entity without version) = data corruption

ObjectBox's `TransactionManager` has a limitation: it uses Dart isolates, which cannot serialize repository instances. This breaks when trying to use atomic versioning with ObjectBox.

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

### Option 2: Skip ObjectBox, Use Different Native Database ⚠️ POSSIBLE BUT NOT IMPLEMENTED

**Status:** Architectural option, not currently implemented

You could replace ObjectBox with another Dart database that supports proper transactions:

- **SQLite** (via `sqflite` or `sql` package)
- **Isar** (similar to ObjectBox but different transaction model)
- **Realm** (cross-platform, better transaction support)

You would need to:
1. Create new `*SqliteAdapter` classes (not huge - follows same pattern)
2. Create `SqliteTransactionManager`
3. Update bootstrap factories

**Current code structure makes this feasible** - the adapter pattern would handle it cleanly.

---

### Option 3: Accept Non-Atomic Versioning on ObjectBox ⚠️ LIVE WITH LIMITATION

**Status:** Current reality for ObjectBox on native

**What this means:**
- VersionableHandler doesn't record versions without TransactionManager
- Versionable entities are saved, but version history is empty
- Pattern composes correctly, just no version tracking

**When this is acceptable:**
- Demo/prototype with Versionable entities but no version UI
- Version tracking only for important entities (use conditional)
- Accept the limitation as product constraint

**Implementation:**
```dart
// Current behavior - skip transactionManager
final noteRepo = NoteRepository(
  adapter: noteAdapter,
  embeddingService: embeddingService,
  versionRepo: versionRepo,
  // Don't provide transactionManager = no atomic versioning
);
```

---

### Option 4: Implement Custom ObjectBox Transaction Wrapper ⚠️ COMPLEX, NOT RECOMMENDED

**Status:** Theoretically possible, high complexity

The core issue is that ObjectBox's lambda captures the repository. You could:

1. **Refactor handlers to not need repository reference**
   - Pass only necessary data (handlers list, adapter methods)
   - Avoid implicit `this` capture
   - Very complex change to handler architecture

2. **Create ObjectBox-specific VersionableHandler**
   - Doesn't use TransactionManager at all
   - Implements custom ObjectBox Store access
   - Breaks pattern abstraction

3. **Use Supabase sync as transaction boundary**
   - Record versions to Supabase atomically
   - Local ObjectBox saves separately
   - Complex, requires backend involvement

**Verdict:** Not worth the complexity. Use Option 1 or 2 instead.

---

## Recommendation by Use Case

### 🎯 Web-Only App
**→ Use Option 1: IndexedDB + IndexedDBTransactionManager**
- Works perfectly today
- No workarounds needed
- Atomic versioning guaranteed

### 🎯 Cross-Platform (Native + Web) WITHOUT Versioning
**→ Use Option 3: Skip TransactionManager**
- ObjectBox on native (without versioning)
- IndexedDB on web (with versioning)
- Simplest path forward

### 🎯 Cross-Platform WITH Atomic Versioning
**→ Option 2: Replace ObjectBox with SQLite/Realm**
- More effort, but cleanest long-term
- Version tracking works everywhere
- Better transaction model than ObjectBox

### 🎯 Production App Starting Today
**→ Use Option 1 (Web) or Option 3 (Native without versioning)**
- IndexedDB is proven, works, no issues
- ObjectBox works fine - just no atomic versioning
- Document the trade-off clearly

---

## Implementation Path: Switching to IndexedDB (Option 1)

If you want atomic versioning everywhere:

1. **Already exists in codebase:**
   ```
   ✓ lib/persistence/indexeddb/note_indexeddb_adapter.dart
   ✓ lib/persistence/indexeddb/entity_version_indexeddb_adapter.dart
   ✓ lib/core/persistence/indexeddb_transaction_manager.dart
   ```

2. **Use in your app:**
   ```dart
   // Instead of ObjectBox
   final db = await idbFactory.open('everything_stack');
   final txManager = IndexedDBTransactionManager(db);

   final noteRepo = NoteRepository(
     adapter: NoteIndexedDBAdapter(db),
     transactionManager: txManager,
     versionRepo: versionRepo,
   );
   ```

3. **Test coverage:**
   - `test/persistence/indexeddb_transaction_test.dart` exists
   - Handler edge cases already pass with this setup
   - No additional work needed

---

## Technical Details: Why ObjectBox Has This Issue

**Root Cause:** Dart's isolate model + ObjectBox's async implementation

```
ObjectBox.runInTransactionAsync uses isolates:
  - Spawns new isolate to execute work callback
  - Serializes all captured variables across boundary
  - Store cannot serialize (contains native pointers)
  - Repository holds Store reference
  - Any method call on Repository captures 'this'
  - Isolate serialization fails
```

**IndexedDB doesn't have this issue:**
```
IdbDatabase.transaction executes on same thread:
  - No isolate boundary to cross
  - All objects accessible directly
  - Work callback is async (but same thread)
  - No serialization needed
```

---

## Decision Framework

| Criteria | ObjectBox + No TX | IndexedDB | Alternative DB |
|----------|-------------------|-----------|-----------------|
| **Atomic versioning** | ❌ No | ✅ Yes | ✅ Yes |
| **Native platforms** | ✅ Yes | ❌ No | ✅ Yes |
| **Web platform** | ❌ No* | ✅ Yes | ✅ Yes |
| **Effort to implement** | ✅ 0 | ✅ 0 (exists) | ⚠️ High |
| **Production ready** | ✅ Yes | ✅ Yes | ⚠️ Maybe |
| **Cross-platform** | ❌ No | ❌ No | ✅ Yes |

*ObjectBox has no web support - platform-specific only

---

## Action Items

- [ ] **Immediate:** Document this in your architecture decision
- [ ] **If you need atomic versioning:** Use IndexedDB (already implemented)
- [ ] **If cross-platform matters:** Evaluate SQLite/Realm (Option 2)
- [ ] **If native-only:** ObjectBox without versioning is fine (Option 3)
- [ ] **Update integration tests:** Remove transactionManager OR use IndexedDB path

---

## Summary

| What You Get | ObjectBox (Native) | IndexedDB (Web) | Alternative DB |
|--------------|-------------------|-----------------|-----------------|
| **Atomic Versioning** | ❌ No | ✅ Yes | ✅ Yes |
| **Ready Today** | ✅ Yes | ✅ Yes | ❌ No |
| **Effort** | 0 | 0 | High |
| **Scalability** | Good | Good | Best |

**Best path forward depends on your constraints. Pick the option that matches your requirements.**
