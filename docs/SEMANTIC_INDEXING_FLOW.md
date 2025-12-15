# Semantic Indexing Architecture & Flow

## Overview

Semantic indexing enables finding text fragments across entities by converting content into meaningful chunks and storing embeddings in an HNSW index. This document explains the complete flow and clarifies architectural decisions.

## Key Architectural Decision: ChunkingService is REQUIRED

**Answer: ChunkingService is REQUIRED (not optional).**

### Why Required?

Every `EntityRepository` needs `ChunkingService` because:
1. If entity is NOT `SemanticIndexable`: ChunkingService is never called (safe)
2. If entity IS `SemanticIndexable`: ChunkingService is automatically used
3. No confusion about whether semantic indexing happens or not

This is explicit and predictable:

```dart
abstract class EntityRepository<T extends BaseEntity> {
  final ChunkingService chunkingService;  // ← REQUIRED

  EntityRepository({
    required this.adapter,
    required this.chunkingService,  // ← Must be provided
    EmbeddingService? embeddingService,
  });
}
```

### The Decision Tree

When you save or delete an entity, the repository checks ONLY one thing:

```
┌──────────────────────────────┐
│ Does entity implement        │
│ SemanticIndexable?           │
└──────────────┬───────────────┘
               │
          ┌────┴────┐
          │         │
         NO        YES
          │         │
          │         │
          ▼         ▼
        [SKIP]    [INDEX]
```

That's it. ChunkingService is always there, always ready.

### Scenario 1: Entity Doesn't Implement SemanticIndexable

```dart
class SimpleNote extends BaseEntity {  // ← No "with SemanticIndexable"
  String title;
  String content;
}

// ChunkingService is required but doesn't get called
final noteRepository = NoteRepository(
  adapter: noteAdapter,
  chunkingService: chunkingService,  // ← Still required
);

await repository.save(simpleNote);  // → Saves entity, chunks NOT indexed
```

**What happens:**
- Entity is saved normally
- `chunkingService` is never invoked (not SemanticIndexable)
- No embeddings generated
- HNSW index untouched
- Cost: Zero (ChunkingService just sits there)

### Scenario 2: Entity Implements SemanticIndexable

```dart
class SemanticNote extends BaseEntity with SemanticIndexable {
  String title;
  String content;

  @override
  String toChunkableInput() => '$title\n$content';

  @override
  String getChunkingConfig() => 'parent';
}

final noteRepository = NoteRepository(
  adapter: noteAdapter,
  chunkingService: chunkingService,  // ← Required
);

await repository.save(semanticNote);  // → Saves entity AND indexes chunks
```

**What happens:**
1. Old chunks deleted (if updating)
2. Entity saved
3. `chunkingService.indexEntity(entity)` called:
   - Content is chunked into parent chunks (~200 tokens)
   - Each parent chunk is sub-chunked into child chunks (~25 tokens)
   - All chunks are embedded
   - All chunks are inserted into HNSW
4. Chunks tracked for later deletion

**Key insight:** Behavior is determined by entity implementation, not by repository configuration.

## Complete Lifecycle Flow

### Save Flow (with decision points)

```
repository.save(entity)
  │
  ├─1. Is entity SemanticIndexable? ──NO──→ [Skip to step 4]
  │   └─YES
  │
  ├─2. Delete old chunks (if updating)
  │   └─ chunkingService.deleteByEntityId(entity.uuid)
  │
  ├─3. Generate embedding (if Embeddable)
  │   └─ embeddingService.generate(toEmbeddingInput())
  │
  ├─4. Save entity to database
  │   └─ adapter.save(entity)
  │
  ├─5. Is entity SemanticIndexable? ──NO──→ [Done]
  │   └─YES
  │
  ├─6. Index new chunks
  │   └─ chunkingService.indexEntity(entity)
  │      └─ Chunks content via semantic chunker
  │      └─ Generates embeddings for each chunk
  │      └─ Inserts into HNSW (String UUID → embedding vector)
  │
  └─7. Return entity.id
```

### Delete Flow (with decision points)

```
repository.deleteByUuid(uuid)
  │
  ├─1. Remove chunks from HNSW
  │   └─ chunkingService.deleteByEntityId(uuid)
  │      └─ Removes ALL chunks for this entity (safe even if none exist)
  │
  ├─2. Delete entity from database
  │   └─ adapter.deleteByUuid(uuid)
  │
  └─3. Return success
```

## The Key Design Decision: Centralized Lifecycle Hooks

**Problem:** Without centralization, each repository (NoteRepository, ArticleRepository, DocumentRepository) would need to implement save/delete logic:

```dart
// ❌ BAD: Scattered logic
class NoteRepository extends EntityRepository<Note> {
  @override
  Future<int> save(Note entity) async {
    if (entity is SemanticIndexable && chunkingService != null) {
      await chunkingService!.deleteByEntityId(entity.uuid);
    }
    final id = await super.save(entity);
    if (entity is SemanticIndexable && chunkingService != null) {
      await chunkingService!.indexEntity(entity);
    }
    return id;
  }
}

class ArticleRepository extends EntityRepository<Article> {
  @override
  Future<int> save(Article entity) async {
    if (entity is SemanticIndexable && chunkingService != null) {
      await chunkingService!.deleteByEntityId(entity.uuid);  // Duplicate!
    }
    // ... same code repeated ...
  }
}
```

**Solution:** Lifecycle hooks in base class (EntityRepository):

```dart
// ✅ GOOD: Centralized, inherited by ALL repositories
abstract class EntityRepository<T extends BaseEntity> {
  final ChunkingService? chunkingService;

  Future<int> save(T entity) async {
    // All SemanticIndexable entities automatically get chunking
    if (chunkingService != null && entity is SemanticIndexable) {
      await chunkingService!.deleteByEntityId(entity.uuid);
    }
    final saved = await adapter.save(entity);
    if (chunkingService != null && entity is SemanticIndexable) {
      await chunkingService!.indexEntity(entity);
    }
    return saved.id;
  }
}

class NoteRepository extends EntityRepository<Note> {
  // Nothing - semantic indexing happens automatically!
}

class ArticleRepository extends EntityRepository<Article> {
  // Nothing - semantic indexing happens automatically!
}
```

**Benefit:** Any new entity type that implements `SemanticIndexable` automatically gets semantic indexing without writing any repository code.

## Entity Interface: SemanticIndexable

```dart
mixin SemanticIndexable {
  /// Return text to be chunked (e.g., title + content)
  String toChunkableInput();

  /// Return chunking config: 'parent' or 'child'
  String getChunkingConfig();
}

// Usage:
class Note extends BaseEntity with SemanticIndexable {
  String title;
  String content;

  @override
  String toChunkableInput() {
    return '$title\n$content';  // Combine fields for chunking
  }

  @override
  String getChunkingConfig() {
    return 'parent';  // Use parent-level chunking config
  }
}
```

## Chunk Model (Lightweight, No Full Text)

Chunks are stored with metadata but NOT the full text:

```dart
class Chunk {
  String id;                    // UUID in HNSW
  String sourceEntityId;        // Which entity this chunk came from
  String sourceEntityType;      // Type name for entity loader routing
  int startToken;               // Position in original text
  int endToken;                 // Position in original text
  String config;                // 'parent' or 'child'

  // Text is reconstructed from sourceEntity + token positions
  // This saves space and keeps chunks independent of entity structure
}
```

**Why no full text?**
- Chunks are immutable once indexed
- If entity text changes, chunks are deleted and recreated
- Reduces storage overhead (metadata only)
- Keeps entity and chunks loosely coupled

## Two-Level Chunking Strategy

### Parent Chunks (~200 tokens, AI context-window size)

```
"Machine Learning Fundamentals"
"Machine learning is a subset of artificial intelligence that focuses..."
[200 more tokens...]
```

- Generated by `parentChunker` (ChunkingConfig.parent)
- Suitable for embedding generation
- Indexed in HNSW
- Provides full context

### Child Chunks (~25 tokens, human-readable snippets)

```
"Machine Learning Fundamentals"
"Machine learning is a subset of..."

"artificial intelligence that..."
"focuses on enabling systems..."
[etc., each ~25 tokens]
```

- Generated by `childChunker` from each parent chunk
- Also indexed in HNSW
- More granular for precise retrieval
- Easier to understand in results

### Both Levels in Same Index

All chunks (parent + child) are inserted into the HNSW index:

```
HNSW Index (Single Vector Space)
├─ parent-chunk-1 → [0.5, 0.2, 0.8, ...]  (200 tokens)
├─ child-chunk-1  → [0.51, 0.19, 0.81, ...] (25 tokens, child of parent-1)
├─ child-chunk-2  → [0.52, 0.18, 0.82, ...] (25 tokens, child of parent-1)
├─ parent-chunk-2 → [0.3, 0.7, 0.1, ...]  (200 tokens)
└─ child-chunk-3  → [0.31, 0.71, 0.11, ...] (25 tokens, child of parent-2)
```

**Search behavior:**
- Query: "What is machine learning?" → Embedding
- HNSW finds similar chunks at any level
- Results could be parent chunks (broad context) or child chunks (specific snippets)

## Example: Complete Entity Lifecycle

### 1. Create Entity

```dart
var note = Note(
  title: 'Python Basics',
  content: 'Python is a programming language... ' + moreText,
);
note.uuid = 'note-1';
```

### 2. Save Entity

```dart
// Assuming:
// - NoteRepository has ChunkingService
// - Note implements SemanticIndexable
// - toChunkableInput() returns "Python Basics\nPython is..."

await noteRepository.save(note);
```

**What happens internally:**

```
1. EntityRepository.save() called
   ↓
2. Check: Is entity SemanticIndexable? YES
   Check: Is ChunkingService provided? YES
   ↓
3. Delete old chunks (none, new entity)
   ↓
4. adapter.save(note) → note saved to database
   ↓
5. chunkingService.indexEntity(note)
   ├─ Extract: "Python Basics\nPython is..."
   ├─ Generate parent chunks (~200 tokens each):
   │  ├─ parent-chunk-1: "Python Basics\nPython is..." (200 tokens)
   │  ├─ parent-chunk-2: "...more content..." (150 tokens)
   │  └─ parent-chunk-3: "...even more..." (80 tokens)
   ├─ For each parent chunk, generate child chunks (~25 tokens):
   │  ├─ From parent-1:
   │  │  ├─ child-1: "Python Basics"
   │  │  ├─ child-2: "Python is a programming..."
   │  │  ├─ child-3: "Python emphasizes..."
   │  │  └─ [more children]
   │  ├─ From parent-2: [similar children]
   │  └─ From parent-3: [similar children]
   ├─ Generate embeddings for ALL chunks (batch)
   ├─ Insert all chunks into HNSW:
   │  ├─ HNSW[parent-chunk-1] = [0.1, 0.2, 0.3, ...] (384 dims)
   │  ├─ HNSW[child-1] = [0.11, 0.21, 0.31, ...]
   │  ├─ HNSW[child-2] = [0.12, 0.22, 0.32, ...]
   │  └─ [more inserts]
   └─ Track chunk IDs: _chunkRegistry['note-1'] = [parent-1, child-1, child-2, ...]

6. Return note.id
```

**Result:** Note is saved AND fully indexed for semantic search.

### 3. Update Entity

```dart
note.content = 'Python is an interpreted, high-level programming language...';
await noteRepository.save(note);  // Same save() method
```

**What happens:**

```
1. EntityRepository.save() called
   ↓
2. Check: Is entity SemanticIndexable? YES
   Check: Is ChunkingService provided? YES
   ↓
3. DELETE old chunks (critical for updates!)
   chunkingService.deleteByEntityId('note-1')
   ├─ Find chunks: [parent-1, child-1, child-2, parent-2, child-3, ...]
   ├─ Remove from HNSW: HNSW.delete(parent-1), HNSW.delete(child-1), ...
   └─ Clear registry: _chunkRegistry.remove('note-1')
   ↓
4. adapter.save(note) → Updated note saved
   ↓
5. INDEX new chunks (same as step 2.5 above)
   ↓
6. Result: Old chunks gone, new chunks indexed
```

**Why delete first?** Otherwise, old chunks remain in HNSW forever, and you get stale results in searches.

### 4. Search Semantically

```dart
final results = await noteRepository.semanticSearch('python basics');
```

**What happens:**

```
1. Generate embedding for "python basics"
   ↓
2. HNSW.search(queryEmbedding, k=10)
   ├─ Find 10 most similar chunks by cosine similarity
   ├─ Might return: [child-1 (0.95), parent-1 (0.92), child-2 (0.89), ...]
   └─ Retrieve sourceEntityId from each chunk
   ↓
3. Load entities from sourceEntityIds
   └─ noteRepository.adapter.findByUuid('note-1') → Full Note object
   ↓
4. Return SemanticSearchResults with chunks + entities
```

### 5. Delete Entity

```dart
await noteRepository.deleteByUuid('note-1');
```

**What happens:**

```
1. EntityRepository.deleteByUuid() called
   ↓
2. Check: Is ChunkingService provided? YES
   ↓
3. DELETE from HNSW
   chunkingService.deleteByEntityId('note-1')
   ├─ Find chunks: [parent-1, child-1, child-2, ...]
   ├─ Remove from HNSW: HNSW.delete(parent-1), ...
   └─ Clear registry
   ↓
4. adapter.deleteByUuid('note-1') → Delete from database
   ↓
5. Result: Entity gone, chunks gone, clean state
```

## Summary: One Decision Point

| Question | Answer | Result |
|----------|--------|--------|
| Does entity implement `SemanticIndexable`? | YES | Full semantic indexing (chunks + HNSW) |
| Does entity implement `SemanticIndexable`? | NO | Regular save (chunks skipped) |

**The beauty:** ChunkingService is ALWAYS provided. The behavior is determined by the entity:

```dart
// All repositories have ChunkingService
final repo = NoteRepository(
  adapter: adapter,
  chunkingService: chunkingService,  // ← REQUIRED, always provided
);

// SemanticIndexable entities are automatically indexed
class SemanticNote extends BaseEntity with SemanticIndexable { /* ... */ }
await repo.save(semanticNote);  // → Chunks created, indexed in HNSW

// Non-SemanticIndexable entities are NOT indexed
class SimpleNote extends BaseEntity { /* ... */ }
await repo.save(simpleNote);  // → Chunks skipped, HNSW untouched

// Same repository, same ChunkingService, different behavior based on entity type
```
