# API Mismatch Analysis

**Why the benchmark code didn't compile:** I made incorrect assumptions about repository APIs based on EntityRepository, but EdgeRepository and VersionRepository have different interfaces.

---

## Issue 1: Note Deletion ✅ FIXED

### What I Wrote:
```dart
await noteRepo.delete(note.uuid);  // Wrong: passing String to int parameter
```

### Actual API (lib/core/entity_repository.dart):
```dart
Future<bool> delete(int id) async           // Takes integer ID
Future<bool> deleteByUuid(String uuid) async  // Takes UUID string
```

### Fix:
```dart
await noteRepo.deleteByUuid(note.uuid);  // Correct
```

**Status:** ✅ Fixed in most places, one instance remains at line 117

---

## Issue 2: Semantic Search Method Name ✅ FIXED

### What I Wrote:
```dart
await noteRepo.searchSimilar('query', limit: 10);  // Wrong method name
```

### Actual API (lib/core/entity_repository.dart:248):
```dart
Future<List<T>> semanticSearch(
  String query,
  {int limit = 10, double minSimilarity = 0.0}
) async
```

### Fix:
```dart
await noteRepo.semanticSearch('query', limit: 10);  // Correct
```

**Status:** ✅ Already fixed

---

## Issue 3: EdgeRepository Cleanup ❌ BLOCKED

### What I Wrote:
```dart
final edges = await edgeRepo.findAll();  // Doesn't exist!
for (final edge in edges) {
  await edgeRepo.deleteEdge(edge.sourceUuid, edge.targetUuid, edge.edgeType);
}
```

### Actual API (lib/core/edge_repository.dart):
```dart
// NO findAll() method exists!
// Available methods:
Future<List<Edge>> findBySource(String sourceUuid)
Future<List<Edge>> findByTarget(String targetUuid)
Future<List<Edge>> findBetween(String sourceUuid, String targetUuid)
Future<List<Edge>> findByType(String edgeType)
Future<List<Edge>> findUnsynced()
Future<bool> deleteEdge(String sourceUuid, String targetUuid, String edgeType)
```

### Problem:
EdgeRepository intentionally has NO `findAll()` method. This is a design decision - edges are queried by relationship, not bulk retrieved.

### Workaround Options:
1. **Don't clean up edges in tearDown** - let test isolation handle it
2. **Track created edges manually** - store UUIDs during setup, delete specific ones
3. **Use adapter directly** - bypass repository (breaks abstraction)
4. **Add findAll() to EdgeRepository** - violates design intent

**Recommendation:** Track edges manually during setup

---

## Issue 4: VersionRepository Cleanup ❌ BLOCKED

### What I Wrote:
```dart
final versions = await versionRepo.findAll();  // Doesn't exist!
for (final version in versions) {
  await versionRepo.deleteByUuid(version.uuid);  // Doesn't exist!
}
```

### Actual API (lib/core/version_repository.dart):
```dart
// NO findAll() method!
// NO delete() or deleteByUuid() methods!
// Available methods:
Future<List<EntityVersion>> getHistory(String entityUuid)
Future<List<EntityVersion>> findUnsynced()
Future<List<EntityVersion>> findByEntityUuidUnsynced(String entityUuid)
Future<void> prune(String entityUuid, {required int keepSnapshots})
```

### Problem:
VersionRepository has NO bulk query and NO delete methods. Versions are:
- Queried by entity UUID only
- Cleaned up via `prune()` which keeps snapshots

### Workaround Options:
1. **Don't clean up versions** - let test DB be ephemeral
2. **Use prune()** - `await versionRepo.prune(testNoteUuid, keepSnapshots: 0)`
3. **Use adapter directly** - bypass repository

**Recommendation:** Use `prune(entityUuid, keepSnapshots: 0)` to remove all versions

---

## Issue 5: Version Reconstruction Signature ❌ BLOCKED

### What I Wrote:
```dart
await versionRepo.reconstruct<Note>(
  testNoteUuid,
  'Note',
  midpoint,
  (json) => Note.fromJson(json),
);
```

### Actual API (lib/core/version_repository.dart:128):
```dart
Future<Map<String, dynamic>?> reconstruct(
  String entityUuid,
  DateTime targetTimestamp,
) async
```

### Problem:
- Returns raw JSON map, not typed entity
- Takes only 2 parameters (UUID + timestamp), not 4
- No type parameter, no factory function

### Fix:
```dart
final json = await versionRepo.reconstruct(testNoteUuid, midpoint);
if (json != null) {
  final note = Note.fromJson(json);
  // use note...
}
```

**Status:** Needs rewrite

---

## Root Cause: Wrong Assumptions

I assumed EdgeRepository and VersionRepository would:
1. Extend EntityRepository (they don't)
2. Have `findAll()` methods (they don't - by design)
3. Have `delete()` methods (VersionRepository doesn't)
4. Follow same patterns as EntityRepository (they're specialized)

**Reality:** These are specialized repositories with constrained APIs:
- **EdgeRepository:** Query by relationship only
- **VersionRepository:** Query by entity UUID only, no deletion, use prune()

---

## Fix Complexity Assessment

| Issue | Complexity | Est. Changes |
|-------|-----------|--------------|
| 1. Note deletion | Trivial | 1 line |
| 2. Search method | Trivial | Already done |
| 3. Edge cleanup | Medium | 10-15 lines (track manually) |
| 4. Version cleanup | Easy | 2 lines (use prune) |
| 5. Reconstruct signature | Medium | 5-10 lines (rewrite logic) |

**Total:** ~20-30 lines of changes, all straightforward

**Time estimate:** 10-15 minutes to fix all issues
