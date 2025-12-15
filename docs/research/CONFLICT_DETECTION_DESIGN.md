# Conflict Detection Strategy - Design Research

**Date:** December 2025
**Status:** Design Research (not yet implemented)
**Scope:** Multi-device offline sync conflict detection and resolution

---

## Problem Statement

When a Note is edited offline on two devices, then synced:

```
Device A: v5 → v6 (edits title)
Device B: v5 → v6 (edits content)
Both sync to server (server now at v7)
```

**Question:** What should happen?

1. Should conflicts be detected and reported to the app?
2. Should they auto-merge using a strategy?
3. Should the user manually resolve?

---

## Current Implementation Analysis

### What We Have
- **SyncService** (`lib/services/sync_service.dart`):
  - Last-Write-Wins (LWW) via `updated_at` timestamp
  - Manual conflict resolution via `resolveConflict(uuid, keepLocal: bool)`
  - No automatic conflict detection
  - Conflict status must be manually set by the app

- **VersionRepository** (`lib/core/version_repository.dart`):
  - RFC 6902 JSON Patch deltas stored per version
  - Field-level change tracking (`changedFields: List<String>`)
  - Periodic snapshots for reconstruction
  - Can determine exactly which fields changed at each step

### The Gap
**VersionRepository has all the data needed for conflict detection, but SyncService doesn't use it.**

Example: If Device A edits `title` and Device B edits `content`, we could **auto-merge** these non-overlapping changes. But currently, we only see the timestamps and don't detect the field-level differences.

---

## Recommended Approach: Version-Aware 3-Way Merge

### Strategy 1: Automatic Field-Level Merge (Recommended)

**When two devices edit at the same version number, detect the conflict early.**

```dart
// Pseudo-code
Future<SyncConflictResult> detectConflict(
  String entityUuid,
  int deviceExpectedVersion,
  Map<String, dynamic> deviceCurrentState,
) async {
  // Get the version both devices started from
  final baseVersion = await versionRepo.getVersion(entityUuid, deviceExpectedVersion);

  // Get what the server has now
  final remoteVersion = serverState.version;

  if (deviceExpectedVersion == remoteVersion) {
    // No conflict - remote hasn't changed since we started editing
    return SyncConflictResult.noConflict();
  }

  if (deviceExpectedVersion < remoteVersion) {
    // Remote has newer changes - potential conflict

    // Get the changed fields from each device
    final deviceChangedFields = getChangedFields(baseVersion, deviceCurrentState);
    final remoteChangedFields = await versionRepo.getChangedFields(
      entityUuid,
      from: deviceExpectedVersion,
      to: remoteVersion,
    );

    // Check for field-level overlap
    final overlap = deviceChangedFields.intersection(remoteChangedFields);

    if (overlap.isEmpty) {
      // No overlap - can auto-merge
      return SyncConflictResult.autoMerge(
        mergedState: mergeStates(baseVersion, deviceCurrentState, remoteState),
        mergeStrategy: 'field-level-union',
      );
    } else {
      // Overlap - need manual resolution or conflict strategy
      return SyncConflictResult.conflict(
        overlappingFields: overlap,
        deviceVersion: deviceExpectedVersion,
        remoteVersion: remoteVersion,
        suggestedStrategy: 'last-write-wins' or 'manual-resolution',
      );
    }
  }
}
```

### Strategy 2: Last-Write-Wins with Conflict Flag

If 3-way merge is too complex, improve LWW with better visibility:

```dart
// Current behavior: Silent override based on updated_at
// Proposed behavior: Detect and flag conflicts, then apply LWW

Future<SyncResult> syncEntity(String uuid) async {
  final localVersion = entity.version;
  final remoteVersion = remote.version;

  if (localVersion != remoteVersion) {
    // Conflict detected - flag it
    entity.syncStatus = SyncStatus.conflict;
    emit(ConflictDetected(
      uuid: uuid,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      strategy: 'will apply last-write-wins',
    ));

    // Then apply LWW silently
    if (entity.updatedAt > remote.updatedAt) {
      // Push local
    } else {
      // Pull remote
    }
  }
}
```

---

## Option Comparison

| Aspect | Auto-Merge | LWW + Detection | Manual Resolution |
|--------|-----------|-----------------|------------------|
| **Implementation** | Complex (3-way merge) | Simple (1 version check) | App-driven |
| **User Experience** | Best (no action needed) | Good (visible conflicts) | Worst (must decide) |
| **Data Loss** | Minimal (non-overlapping) | Some (overwrite loses data) | None (app controls) |
| **Testing** | Hard (all merge scenarios) | Easy (version comparison) | Depends on app |
| **When to Use** | Collaborative apps | General-purpose | High-stakes data |

---

## Proposed API Design (Version-Aware)

### New Types in SyncService

```dart
/// Result of conflict detection
enum ConflictResolution {
  noConflict,        // No conflict detected
  autoMerged,        // Successfully auto-merged
  needsResolution,   // Manual resolution required
  applyingLWW,       // Applying last-write-wins
}

/// Details about a detected conflict
class ConflictInfo {
  final String entityUuid;
  final int localVersion;
  final int remoteVersion;
  final List<String>? overlappingFields;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;
  final ConflictResolution resolution;
}

/// Sync result with optional conflict info
class SyncResult {
  final SyncStatus finalStatus;
  final ConflictInfo? conflict;
  final String? mergeStrategy;
}
```

### Enhanced SyncService API

```dart
abstract class SyncService {
  /// Sync with automatic conflict detection
  /// Returns conflict info if detected, null if clean
  Future<ConflictInfo?> syncEntityWithDetection(String uuid);

  /// Get all current conflicts
  Future<List<ConflictInfo>> getConflicts();

  /// Resolve conflict with strategy
  Future<void> resolveConflict(
    String uuid, {
    required ConflictResolution strategy,
    Map<String, dynamic>? manualMerge,
  });

  /// Get conflict history for audit trail
  Future<List<ConflictInfo>> getConflictHistory(String uuid);

  /// Stream of conflict events
  Stream<ConflictEvent> get onConflictDetected;
}

class ConflictEvent {
  final String entityUuid;
  final ConflictInfo info;
  final DateTime timestamp;
}
```

---

## Example Scenarios

### Scenario 1: Non-Overlapping Edits (Auto-Merge)

```
Device A (offline):
- v1: {title: "Task", content: "Do stuff"}
- Edit: Changes title to "Important Task"
- v2 (local): {title: "Important Task", content: "Do stuff"}

Device B (offline):
- v1: {title: "Task", content: "Do stuff"}
- Edit: Changes content to "Do important stuff"
- v2 (local): {title: "Task", content: "Do important stuff"}

Sync order:
1. Device A syncs first → Server at v2 with title change
2. Device B tries to sync:
   - Detects: local v1 → v2 (changed: content)
   - Remote v1 → v2 (changed: title)
   - No overlap ✓
   - Auto-merge: {title: "Important Task", content: "Do important stuff"}
   - Result: v3 on server with both changes
```

### Scenario 2: Overlapping Edits (Conflict)

```
Device A (offline):
- v1: {title: "Task"}
- Edit: Changes title to "High Priority Task"
- v2 (local): {title: "High Priority Task"}

Device B (offline):
- v1: {title: "Task"}
- Edit: Changes title to "URGENT: Task"
- v2 (local): {title: "URGENT: Task"}

Sync order:
1. Device A syncs → Server at v2: {title: "High Priority Task"}
2. Device B tries to sync:
   - Detects: local v1 → v2 (changed: title)
   - Remote v1 → v2 (changed: title)
   - Overlap on 'title' ✗
   - Conflict detected
   - Apply LWW: Remote updated_at is newer → pull remote
   - OR: App resolves manually
```

### Scenario 3: Server-Side Changes

```
Device A (offline):
- v1 → v2: edits locally
- Tries to sync

Server:
- v1 → v2 → v3 (another user edited)

Sync:
1. Device A detects: expected v1, got v3
2. Does 3-way merge from v1 → (DeviceA v2 vs Server v3)
3. If no field overlap: auto-merge to v4
4. If overlap: conflict
```

---

## Implementation Approach

### Phase 1: Detection (No Merge)
- Add version comparison to SyncService.syncEntity()
- Expose `ConflictInfo` when versions diverge
- Emit `onConflictDetected` events
- Apps can see conflicts but not auto-resolve yet

### Phase 2: Auto-Merge (Optional)
- Integrate VersionRepository.getChangedFields()
- Implement 3-way merge algorithm
- Auto-resolve non-overlapping changes
- Fall back to LWW for overlaps

### Phase 3: Manual Resolution UI
- Provide conflict UI components
- Show both versions side-by-side
- Allow field-by-field selection
- Track resolution in audit trail

---

## Comparison with Other Systems

### Git (3-Way Merge)
- **Approach:** Detects conflicts at the line level
- **Handles:** Non-overlapping changes auto-merge
- **When blocked:** Manual conflict markers
- **Best for:** Code (high precision needed)

### Operational Transform (Google Docs)
- **Approach:** Transforms operations to resolve order dependency
- **Handles:** Concurrent edits in real-time
- **When blocked:** Never (no concurrent editing)
- **Best for:** Collaborative editing (requires server)

### CRDT (Conflict-free)
- **Approach:** Uses unique identifiers per change, no conflicts by design
- **Handles:** All concurrent edits without conflict
- **When blocked:** Never (mathematically impossible)
- **Best for:** P2P sync without central server

### Last-Write-Wins (LWW)
- **Approach:** Timestamp-based, simple
- **Handles:** Simple conflicts
- **When blocked:** Any overlapping edits
- **Best for:** Immutable data, non-collaborative

### Recommended: Git-Like Approach
For this template, **Git's 3-way merge** is the best fit:
- Works offline (no server needed during merge)
- Handles non-overlapping changes automatically
- Shows conflicts only when necessary
- Well-understood algorithm
- Can implement locally in device storage

---

## Testing Strategy

### Unit Tests
```dart
test('detects no conflict when versions match', () async {
  final result = await syncService.detectConflict(uuid, version: 2);
  expect(result.resolution, ConflictResolution.noConflict);
});

test('detects conflict when version numbers differ', () async {
  final result = await syncService.detectConflict(uuid, version: 1); // server at 3
  expect(result.resolution, ConflictResolution.needsResolution);
});

test('auto-merges non-overlapping field changes', () async {
  // Device A: changed fields [title]
  // Device B: changed fields [content]
  final result = await syncService.detectConflict(uuid, version: 1);
  expect(result.resolution, ConflictResolution.autoMerged);
});

test('reports conflict on overlapping field changes', () async {
  // Device A: changed fields [title]
  // Device B: changed fields [title]
  final result = await syncService.detectConflict(uuid, version: 1);
  expect(result.resolution, ConflictResolution.needsResolution);
  expect(result.overlappingFields, ['title']);
});
```

### Integration Tests
```dart
test('end-to-end: Device A and B edit offline, merge on sync', () async {
  // 1. Create entity at v1
  // 2. Device A edits title, saves locally (v2)
  // 3. Device B edits content, saves locally (v2)
  // 4. Device A syncs → server v3
  // 5. Device B syncs → auto-merge with Device A changes
  // 6. Verify final state has both changes
});
```

### Scenario Tests (BDD)
```gherkin
Scenario: Non-overlapping edits auto-merge
  Given a Note at version 1 with title "Task" and content "Do stuff"
  When Device A edits the title to "Important Task" and goes offline
  And Device B edits the content to "Do important stuff" and goes offline
  And Device A syncs
  And Device B syncs
  Then both edits should be present in the final state
  And no conflict should be reported
  And the final version should be 3

Scenario: Overlapping edits create conflict
  Given a Note at version 1 with title "Task"
  When Device A changes title to "High Priority"
  And Device B changes title to "URGENT"
  And Device A syncs
  And Device B tries to sync
  Then a conflict should be detected
  And the app should be notified via onConflictDetected
```

---

## Decision: What to Implement First

**Recommendation: Start with Phase 1 (Detection Only)**

1. **Why Phase 1 first:**
   - Lowest risk (no data loss, just reporting)
   - Apps can immediately see when conflicts occur
   - Gives users visibility before auto-merge
   - Testing is simpler

2. **Success criteria:**
   - ✅ Conflicts detected before sync
   - ✅ App notified with overlapping fields
   - ✅ LWW applied silently or shown to user
   - ✅ Tests pass for all scenarios

3. **Defer Phase 2 (Auto-Merge) until:**
   - Apps successfully handle conflict notifications
   - 3-way merge algorithm design is approved
   - Testing strategy for all merge scenarios is defined

4. **Defer Phase 3 (UI) until:**
   - Core merge engine is stable
   - Apps request conflict resolution UI

---

## Open Questions

1. **Should conflicts block the sync or continue with LWW?**
   - Block: User must explicitly resolve (safer)
   - Continue: Apply LWW automatically (faster)

2. **Should conflict history be persisted?**
   - Yes: Audit trail for reconciliation
   - No: Conflicts are transient, forget after resolution

3. **Should the app be required to handle conflicts?**
   - Yes: Opt-in conflict detection API
   - No: Silent LWW with optional conflict stream

4. **Should deleted entities be handled differently?**
   - If Device A deletes but Device B edits: what happens?
   - Current: LWW wins
   - Better: Flag as "delete-edit" conflict (special case)

---

## Summary

| Aspect | Decision |
|--------|----------|
| **Detection Strategy** | Version-aware (compare version numbers) |
| **Field-Level Analysis** | Use VersionRepository.changedFields |
| **Auto-Merge Scope** | Non-overlapping changes only |
| **Overlapping Conflicts** | Report to app, apply LWW if not resolved |
| **API** | Expose ConflictInfo with overlappingFields |
| **Phase 1 (Now)** | Detection only, LWW applied silently |
| **Phase 2 (Later)** | Auto-merge non-overlapping changes |
| **Phase 3 (Later)** | Conflict resolution UI components |
