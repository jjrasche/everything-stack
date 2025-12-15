# Schema Evolution - Design Research

**Date:** December 2025
**Status:** Design Research (not yet implemented)
**Scope:** Supporting app version changes with new/removed/modified entity fields

---

## Problem Statement

When you ship app v2 that adds a field to Note:

**Old snapshot (v1):** `{id, title, content, version}`
**New code (v2):** `{id, title, content, version, tags, priority}`

**Questions:**
1. Can you reconstruct v1 snapshot in v2 code?
2. What happens when loading old data without new fields?
3. Should old snapshots fail with exception or return null/default values?
4. Is this a "known limitation" or "fully supported"?

---

## Current Implementation Analysis

### 1. ObjectBox Migrations

**Current State: No version management**

ObjectBox schema is defined via annotations in model classes:
```dart
@Entity()
class Note {
  int id = 0;
  String title = '';
  String content = '';
  String? tags;  // New in v2
  // ...
}
```

**How ObjectBox handles schema changes:**
- No migration framework (not built into ObjectBox)
- Schema defined by code (annotations)
- `openStore()` auto-creates tables with latest schema
- **Problem:** No detection of backward/forward compatibility
- **Result:** If field is removed, old data is orphaned but not lost

**File references:**
- `lib/persistence/objectbox/wrappers/note_ob.dart` - ObjectBox-specific wrapper
- `lib/objectbox.g.dart` - Generated schema code

**Test coverage:** NONE for schema changes

### 2. IndexedDB Schema Changes

**Current State: Infrastructure exists, untested**

IndexedDB has built-in version management and upgrade callbacks:

**File: `lib/persistence/indexeddb/database_schema.dart`** (Schema definition)
```dart
const int SCHEMA_VERSION = 1;

/// Schema Version History:
/// v1 (2025-12-15): Initial schema with object stores
/// - notes: [keyPath: 'uuid', indexes: 'syncStatus', 'updatedAt']
/// - entityVersions: [keyPath: 'uuid', indexes: 'entityUuid', 'timestamp']
/// - edges: [keyPath: 'uuid']

class ObjectStores {
  static const String notes = 'notes';
  static const String entityVersions = 'entityVersions';
  static const String edges = 'edges';
}

class ObjectStoreIndexes {
  static const String notesSyncStatus = 'syncStatus';
  static const String notesUpdatedAt = 'updatedAt';
  // ... etc
}
```

**File: `lib/persistence/indexeddb/database_init.dart`** (Upgrade handler)
```dart
void _onUpgradeNeeded(VersionChangeEvent e) {
  final db = e.target.result as IdbDatabase;

  if (e.oldVersion == 0) {
    // Initial schema creation (v1)
    db.createObjectStore(ObjectStores.notes, keyPath: 'uuid');
    db.createObjectStore(ObjectStores.entityVersions, keyPath: 'uuid');
    db.createObjectStore(ObjectStores.edges, keyPath: 'uuid');
  }

  // Future version upgrades go here
  if (e.oldVersion < 2) {
    // Example upgrade: add field to notes
    // const noteStore = e.target.transaction!.objectStore(ObjectStores.notes);
    // Could add index, modify structure, etc.
  }
}
```

**Key capabilities:**
- IndexedDB version system is properly structured
- Upgrade callback is implemented
- Future upgrades have placeholder structure

**Test coverage:** NONE for schema upgrades

### 3. JSON Serialization & Deserialization

**File: `lib/domain/note.dart`** (Entity definition)
```dart
@JsonSerializable()
class Note extends BaseEntity with ... {
  String title = '';
  String content = '';
  List<String> tags = const [];  // New in v2
  String? priority;  // New in v2
}
```

**Generated code: `lib/domain/note.g.dart`** (JSON serialization)
```dart
Note _$NoteFromJson(Map<String, dynamic> json) => Note(
  title: json['title'] as String,
  content: json['content'] as String? ?? '',  // Default for missing
  tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],  // Default
  priority: json['priority'] as String?,  // Null OK
  // ...
);
```

**Forward compatibility mechanism:**
- Uses `??` operator to provide defaults for missing fields
- Optional fields can be null
- Required fields use default values if missing
- **Works automatically** when `json_serializable` generates code

**Example: Loading v1 snapshot in v2 code**
```json
{"id": 1, "title": "Task", "content": "Do stuff"}
```

When deserialized with v2 code:
```dart
Note note = Note.fromJson(json);
// title = "Task" ✓
// content = "Do stuff" ✓
// tags = [] ✓ (default from ??)
// priority = null ✓ (optional)
```

**Reverse compatibility (loading new snapshot in old code):**
- `json_serializable` ignores extra fields
- v1 code ignores `tags` and `priority` fields
- Data loss: new fields are silently dropped

**Test coverage:** NONE for schema evolution scenarios

### 4. EntityVersion Reconstruction

**File: `lib/core/version_repository.dart`** (Version tracking)

Currently well-tested for **time-based reconstruction**:
```dart
// Get entity state at a specific point in time
final oldState = await versionRepo.reconstruct(entityUuid, targetTime: DateTime.now().subtract(Duration(days: 7)));
```

**How it works:**
1. Find nearest snapshot before/at target time
2. Apply RFC 6902 JSON Patch deltas forward to target
3. Return reconstructed state

**Test file: `test/domain/version_repository_test.dart`** (245 lines)
```dart
test('reconstructs entity state at target timestamp', () async {
  // Create entity at time T1
  // Modify at T2
  // Reconstruct at T1.5
  // Should get state between T1 and T2
});

test('applies deltas forward from snapshot', () async {
  // Create snapshot at v5
  // Apply deltas 6, 7, 8
  // Should get correct state at v8
});
```

**Gap:** No tests for schema evolution with reconstruction
- What if v1 snapshot has `{title, content}`
- But v2 code adds `tags` field?
- Reconstruction returns old state without `tags`
- Should this fail or succeed?

### 5. JSON Diff & Delta Generation

**File: `lib/utils/json_diff.dart`** (RFC 6902 implementation)

Properly handles field changes:
```dart
final delta = JsonDiff.diff(
  {'title': 'Old', 'content': 'Old content'},
  {'title': 'New', 'content': 'Old content', 'tags': ['new', 'tag']},
);

// Result:
// [
//   {op: 'replace', path: '/title', value: 'New'},
//   {op: 'add', path: '/tags', value: ['new', 'tag']},
// ]
```

**Test file: `test/utils/json_diff_test.dart`** (comprehensive)
- Tests for add, remove, replace operations
- Tests for nested objects and arrays
- Tests for null values

**Capability:** Detects added/removed fields automatically

**Gap:** No tests for applying deltas to schemas with missing/new fields

---

## Test Coverage Analysis

### What's Well Tested
- ✅ Version recording and snapshot/delta logic
- ✅ Time-based reconstruction
- ✅ JSON diff generation (RFC 6902)
- ✅ Basic CRUD and serialization
- ✅ Note entity CRUD and version tracking

### What's NOT Tested
- ❌ Adding a new field to an entity (schema evolution)
- ❌ Removing a field from an entity
- ❌ Loading old snapshots without new fields
- ❌ Changing field types in snapshots
- ❌ ObjectBox migrations/schema changes
- ❌ IndexedDB schema upgrades
- ❌ Forward/backward compatibility
- ❌ Reconstruction with schema mismatch

---

## Schema Evolution Scenarios

### Scenario 1: Add Optional Field (Safe)

**v1 code:**
```dart
class Note {
  String title;
  String content;
}
```

**v2 code:**
```dart
class Note {
  String title;
  String content;
  List<String>? tags;  // New, optional
}
```

**What happens:**
- v1 snapshot: `{title: 'Task', content: 'Do'}`
- v2 loads it: `title='Task'`, `content='Do'`, `tags=null` ✅
- v2 creates new snapshot: `{title: 'Task', content: 'Do', tags: null}`
- v1 loads it: `title='Task'`, `content='Do'` (tags ignored) ✅

**Verdict:** SAFE - works both directions

---

### Scenario 2: Add Required Field with Default (Safe)

**v1 code:**
```dart
class Note {
  String title;
  String content;
}
```

**v2 code:**
```dart
class Note {
  String title;
  String content;
  String priority = 'normal';  // New, but has default
}
```

**What happens:**
- v1 snapshot: `{title: 'Task', content: 'Do'}`
- v2 loads it: `title='Task'`, `content='Do'`, `priority='normal'` (default) ✅
- v2 can save with explicit priority: `{title: 'Task', content: 'Do', priority: 'high'}`
- v1 loads it: `title='Task'`, `content='Do'` (priority ignored) ✅

**Verdict:** SAFE - forward/backward compatible

**Implementation:** Generated code already does this via `??` operator

---

### Scenario 3: Add Required Field WITHOUT Default (BREAKING)

**v1 code:**
```dart
class Note {
  String title;
  String content;
}
```

**v2 code:**
```dart
class Note {
  String title;
  String content;
  required String ownerId;  // New, required, no default
}
```

**What happens:**
- v1 snapshot: `{title: 'Task', content: 'Do'}`
- v2 loads it: **ERROR** - missing required field `ownerId` ❌

**Verdict:** BREAKING - will crash on old data

**Fix options:**
1. Make it optional: `String? ownerId`
2. Add default: `String ownerId = ''`
3. Migrate old data before loading (complex)

---

### Scenario 4: Remove a Field (Backward Compatible)

**v1 code:**
```dart
class Note {
  String title;
  String content;
  String? description;  // Rarely used
}
```

**v2 code:**
```dart
class Note {
  String title;
  String content;
  // description removed
}
```

**What happens:**
- v1 snapshot: `{title: 'Task', content: 'Do', description: 'Details'}`
- v2 loads it: `title='Task'`, `content='Do'` (description ignored) ✅
- v2 creates new snapshot without description: `{title: 'Task', content: 'Do'}`
- v1 loads it: `title='Task'`, `content='Do'` (description is null) ✅

**Verdict:** SAFE - data is preserved (in EntityVersion history)

---

### Scenario 5: Change Field Type (BREAKING)

**v1 code:**
```dart
class Note {
  int version = 1;  // Integer
}
```

**v2 code:**
```dart
class Note {
  String version = '1.0';  // String (changed type)
}
```

**What happens:**
- v1 snapshot: `{version: 5}`
- v2 loads it: **ERROR** - type mismatch ❌
- v2 try: `String.fromInt(json['version'])` - JSON deserialization fails

**Verdict:** BREAKING - runtime error

**Fix:** Never change field types. Add migration logic if needed.

---

## Recommended Approach: Graceful Degradation

### Philosophy

**Build for forward compatibility:**
1. Always add fields with defaults or as optional
2. Never remove required fields (make optional first, then remove in next major version)
3. Never change field types
4. Keep comprehensive version history for recovery

### Design Principles

**Principle 1: New fields are always optional or have defaults**
```dart
// Good
List<String> tags = const [];  // Default value
String? priority;  // Optional
String owner = 'unknown';  // Default value

// Bad
required String ownerId;  // No default - will break old data
```

**Principle 2: Use nullable types for optional fields**
```dart
// Good
String? description;  // Can be null from old snapshots

// Bad
String description = '';  // Empty string hides missing data
```

**Principle 3: Keep field history in EntityVersion**
```dart
// All changes tracked in EntityVersion
// Can reconstruct any previous state
// Even if entity schema changes
```

**Principle 4: Use patch migrations for breaking changes**
```dart
// If you MUST add required field:
// 1. Add field with default in schema
// 2. Create migration task to backfill values
// 3. In migration, update all old snapshots
// 4. Once complete, make field required in next version
```

---

## Implementation Plan

### Phase 1: Documentation (Immediate)

**Create guidelines for app developers:**
1. Field addition rules (always optional/default)
2. What breaking changes are not allowed
3. How to support multiple app versions
4. Example: "Adding tags field to Note"

**Files to create:**
- `docs/patterns/SCHEMA_EVOLUTION_GUIDE.md` - Best practices
- `docs/examples/FIELD_MIGRATION_EXAMPLE.md` - Step-by-step example

### Phase 2: Test Suite (Next)

**Create comprehensive test cases:**

```dart
// test/schema_evolution/schema_evolution_test.dart

group('Schema Evolution', () {
  group('Adding fields', () {
    test('add optional field - reconstruct old snapshot', () {
      // Load v1 snapshot in v2 code
      // Verify old fields are preserved
      // Verify new field has default value
    });

    test('add required field with default', () {
      // Load v1 snapshot (missing new field)
      // Verify default value applied
      // Verify reconstruction works
    });

    test('add required field WITHOUT default - throws', () {
      // Load v1 snapshot (missing required field)
      // Verify exception or proper error handling
    });
  });

  group('Removing fields', () {
    test('remove optional field - backward compatible', () {
      // Create v1 entity with removed field
      // Load in v2 code
      // Verify other fields preserved
      // Verify removed field ignored
    });

    test('remove required field - data loss', () {
      // Create v1 entity with required field
      // Load in v2 code (field removed)
      // Verify: data is silently lost (expected)
      // Check EntityVersion has full history
    });
  });

  group('Note field evolution', () {
    test('add tags field to Note', () {
      // Load Note without tags (v1)
      // Verify tags defaults to []
      // Verify reconstruction works
    });

    test('add priority field to Note', () {
      // Load Note without priority (v1)
      // Verify priority defaults to 'normal'
      // Verify reconstruction works
    });

    test('change Note field type - should fail', () {
      // Create Note with field as int
      // Attempt to deserialize as String
      // Verify error handling
    });
  });

  group('IndexedDB upgrades', () {
    test('upgrade from v1 to v2 schema', () {
      // Create IndexedDB v1
      // Add object store in v2
      // Verify upgrade handler called
      // Verify old data accessible
    });

    test('add index to object store', () {
      // Create v1 with notes object store
      // Upgrade to v2 with new index
      // Verify queries use new index
    });
  });

  group('ObjectBox migrations', () {
    test('detect schema changes', () {
      // Create ObjectBox with v1 schema
      // Add field to model
      // Open with v2 code
      // Verify: can we detect the change?
    });

    test('add column to ObjectBox entity', () {
      // v1 entity: {id, title, content}
      // v2 entity: {id, title, content, tags}
      // Load old data in v2
      // Verify: old records have null/default for tags
    });
  });
});
```

### Phase 3: ObjectBox Migration Support

**Current state:** No migration framework
**Decision:** Do we need one?

**Option A: Let ObjectBox auto-migrate (Lazy)**
- Pros: Simple, automatic
- Cons: Limited control, no validation
- Works for: Adding optional/default fields

**Option B: Build migration layer (Complex)**
- Pros: Full control, validation
- Cons: More code, maintenance burden
- Works for: Complex migrations

**Recommendation:** Start with Option A (auto-migrate)
- ObjectBox auto-creates new columns with null/default
- Existing code already handles missing fields
- Test with Note entity to verify

### Phase 4: IndexedDB Schema Versioning

**Current state:** Infrastructure exists, untested
**What to do:** Implement and test version upgrades

**File: `lib/persistence/indexeddb/database_init.dart`**
```dart
void _onUpgradeNeeded(VersionChangeEvent e) {
  final db = e.target.result as IdbDatabase;

  if (e.oldVersion == 0) {
    // v1 creation
  }

  if (e.oldVersion < 2) {
    // v2: Add tagsIndex to notes
    // const noteStore = e.target.transaction!.objectStore(ObjectStores.notes);
    // noteStore.createIndex('tags', 'tags', multiEntry: true);
  }

  if (e.oldVersion < 3) {
    // v3: Add new object store
    // db.createObjectStore(ObjectStores.newStore);
  }
}
```

**Test to verify:**
- Upgrade from v1 → v2
- Verify old data still accessible
- Verify new indexes/stores created
- Verify queries work with new schema

---

## Testing Strategy

### Unit Tests (Low-level)

```dart
test('json_serializable handles missing fields', () {
  final json = {'title': 'Task', 'content': 'Do'};
  final note = Note.fromJson(json);

  expect(note.title, 'Task');
  expect(note.tags, const []);  // Default from annotation
});

test('json_serializable ignores extra fields', () {
  final json = {'title': 'Task', 'content': 'Do', 'futureField': 'value'};
  final note = Note.fromJson(json);

  expect(note.title, 'Task');
  // futureField is ignored
});
```

### Integration Tests

```dart
test('load v1 snapshot in v2 code', () async {
  // Create v1 snapshot in test data
  final v1Snapshot = {'title': 'Task', 'content': 'Do'};

  // Deserialize with v2 code (has tags field)
  final note = Note.fromJson(v1Snapshot);

  // Verify fields are populated correctly
  expect(note.title, 'Task');
  expect(note.content, 'Do');
  expect(note.tags, const []);  // New field has default
});

test('reconstruct v1 entity from version history', () async {
  // Get v1 snapshot from EntityVersion
  final snapshot = await versionRepo.reconstruct(noteUuid, targetTime);

  // Load as Note (v2 schema)
  final note = Note.fromJson(json.decode(snapshot));

  // Verify reconstruction works despite schema mismatch
  expect(note != null, true);
  expect(note.tags, const []);  // New field filled with default
});
```

### Schema-specific Tests

```dart
test('add required field - old snapshots fail without default', () {
  // Create entity without new required field
  final json = {'title': 'Task', 'content': 'Do'};

  // v2 code has: required String status;
  // Should fail because no default
  expect(
    () => Note.fromJson(json),
    throwsException,  // Missing required field
  );
});

test('add optional field - backward compatible', () {
  final json = {'title': 'Task', 'content': 'Do'};

  // v2 code has: String? status;
  // Should succeed because optional
  final note = Note.fromJson(json);
  expect(note.status, null);  // Optional field is null
});
```

### Scenario Tests (BDD)

```gherkin
Scenario: App v2 reads v1 snapshots
  Given a Note entity stored in v1 format: {title, content}
  When app v2 starts and loads the snapshot
  Then the Note should load successfully
  And new fields should have default values
  And the entity should be fully functional

Scenario: Schema evolution with field addition
  Given a Note in v1: {title: "Task", content: "Do"}
  When app v2 adds a tags field with default []
  And loads the old snapshot
  Then tags should be []
  And other fields should be unchanged
  And v1 snapshots should still be loadable

Scenario: Breaking change - add required field without default
  Given a Note in v1: {title, content}
  When app v2 adds required field status
  And loads the v1 snapshot
  Then it should fail with clear error
  Or migrate should be attempted automatically
```

---

## Migration Strategies for Breaking Changes

### Strategy 1: Backfill Before Release

```dart
// Before shipping v2 with required field:
Future<void> migrate() async {
  // 1. Add field with default first (v2 upgrade)
  // 2. Backfill all old data with values
  // 3. In v3, make field required (no default)

  final allNotes = await repo.getAll();
  for (final note in allNotes) {
    if (note.ownerId == null) {
      note.ownerId = 'system';
      await repo.save(note);
    }
  }
}
```

### Strategy 2: Lazy Migration on Load

```dart
// On-demand migration:
Note loadNote(uuid) {
  var note = repo.load(uuid);

  if (note.version < 2) {
    // Migrate v1 to v2 on load
    note.tags = note.tags ?? [];
    note.priority = note.priority ?? 'normal';
    note.version = 2;
    repo.save(note);  // Update in DB
  }

  return note;
}
```

### Strategy 3: Guided User Migration

```dart
// On app startup:
// If any entities need migration:
// - Show "Upgrading your data..." dialog
// - Batch update all entities
// - Show progress
// - Complete before app is usable
```

---

## Open Questions

1. **Should ObjectBox schema changes be automatic or explicit?**
   - Automatic: Simple, but less control
   - Explicit: Migrations defined in code, more control

2. **How to handle required fields added to existing entities?**
   - Always add as optional first, make required later?
   - Require migration script?
   - Backfill in background?

3. **Should we version entity schemas separately from app versions?**
   - Yes: More flexibility, complex
   - No: Simpler, tied to app releases

4. **How to document schema evolution for app developers?**
   - Living document?
   - Migration guides per version?
   - Automated schema diff tools?

5. **Should we support schema rollback?**
   - Yes: Load newer snapshots in older code
   - No: One-way forward evolution

---

## Summary

| Aspect | Decision |
|--------|----------|
| **Approach** | Forward-compatible defaults + version history |
| **Required fields** | Avoid adding to existing entities |
| **Optional fields** | Safe to add anytime (backward compatible) |
| **Field removal** | Safe (data preserved in EntityVersion) |
| **Type changes** | Not allowed (use separate field) |
| **ObjectBox** | Auto-migration (simple, works for safe changes) |
| **IndexedDB** | Versioned upgrades (infrastructure exists) |
| **Reconstruction** | Use EntityVersion for time-based rollback |
| **Testing** | Test all schema evolution scenarios |
| **Documentation** | Create best practices guide |

### Implementation Priority

1. **Phase 1 (Now):** Write schema evolution guide + test suite
2. **Phase 2 (Next):** Add ObjectBox migration detection
3. **Phase 3 (After):** Implement IndexedDB version upgrades
4. **Phase 4 (Polish):** Developer documentation + examples

The key insight: **JSON serialization already supports forward/backward compatibility**. The `json_serializable` package handles missing fields with defaults. We just need to:
1. Document the pattern clearly
2. Test it thoroughly
3. Guide app developers on safe schema changes
4. Use EntityVersion as the safety net for complex migrations
