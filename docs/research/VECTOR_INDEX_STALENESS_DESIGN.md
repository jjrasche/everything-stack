# Vector Index Staleness - Design Research

**Date:** December 2025
**Status:** Design Research (not yet implemented)
**Scope:** HNSW index consistency and stale index detection/recovery

---

## Problem Statement

Current assumption: Atomic saves = index always consistent

But consider this scenario:

```
1. Note saved ✅ (entity in ObjectBox/IndexedDB)
2. Chunks created ✅
3. Embeddings generated for chunks ✅
4. HNSW index updated with chunk vectors ✅
5. HnswIndexStore.save() called... ⚠️

If the process fails at step 5 (or between 4-5):
- Entity exists in persistence ✅
- Chunk IDs are tracked in entity ✅
- HNSW index has new vectors in memory ✅
- BUT: HnswIndexStore.save() never completed ❌
  └─ Old HNSW state is on disk (missing the new chunks)
  └─ Next app restart: loads stale index ❌
```

**Question:** How do we detect and fix this?

---

## Current Implementation Analysis

### Embedding/Indexing Lifecycle

**SemanticIndexableHandler** (`lib/core/handlers/semantic_indexable_handler.dart`):
```dart
// Before save (fail-fast)
Future<void> beforeSave(T entity) async {
  await chunkingService.deleteByEntityId(entity.uuid);  // ← Errors abort save
}

// After save (best-effort)
Future<void> afterSave(T entity) async {
  await chunkingService.indexEntity(entity);  // ← Errors logged, not thrown
}
```

**Key design decisions:**
1. Chunk deletion is **inside the transaction** (atomic with entity save)
2. Chunk creation/embedding is **outside the transaction** (best-effort)
3. **Rationale:** Chunks are ephemeral and can be rebuilt

### ChunkingService.indexEntity() Process

```dart
Future<void> indexEntity(T entity) async {
  if (entity is! SemanticIndexable) return;

  // 1. Extract chunkable text from entity
  final input = entity.toChunkableInput();

  // 2. Generate parent chunks (~200 tokens)
  final parentChunks = parentChunker.chunk(input);

  // 3. For each parent, generate child chunks (~25 tokens)
  final allChunks = [
    for (final parent in parentChunks) ...[
      parent,
      ...childChunker.chunk(parent.text),
    ]
  ];

  // 4. Generate embeddings for all chunks (batch)
  final embeddings = await embeddingService.generateBatch(
    allChunks.map((c) => c.text).toList()
  );  // ← FAILURE POINT: API timeout, rate limit, network error

  // 5. Insert chunks into HNSW index
  for (var i = 0; i < allChunks.length; i++) {
    index.insert(allChunks[i].id, embeddings[i]);
  }

  // 6. Persist index to Isar
  await indexStore.save(index);  // ← FAILURE POINT: Isar write error
}
```

**Failure Points:**
1. **EmbeddingService.generateBatch()** - Network/API errors
2. **HnswIndexStore.save()** - Isar write error or crash

### Index Persistence Model

**HnswIndexStore** (`lib/services/hnsw_index_store.dart`):
- Single row in Isar collection with key 'main'
- Stores serialized index bytes
- Updated after every embedding operation
- **Problem:** If save fails, old state remains on disk

---

## Risk Analysis

### Scenario 1: Embedding API Timeout

```timeline
1. Note saved, old chunks deleted
2. New chunks created, embeddings requested
3. API timeout after 2/10 chunks embedded
4. Exception thrown in afterSave
5. Entity is persisted, but only 2 chunks in index
6. Old index state still on disk (loaded on restart)

Result: Index missing 8 chunks, no way to detect
```

**Impact:** Semantic search returns incomplete results. Users see old chunks in searches.

### Scenario 2: App Crash During Index Save

```timeline
1. All embeddings generated ✅
2. All chunks inserted into HNSW ✅
3. HnswIndexStore.save() starts serialization
4. App crashes mid-serialization
5. Isar has half-written data
6. On restart: HnswIndex.fromBytes() fails to deserialize

Result: Index is corrupt, can't be loaded
```

**Impact:** Semantic search broken until index is rebuilt. What triggers rebuild?

### Scenario 3: Sync Service Incomplete Rebuild

Current assumption in SemanticIndexableHandler:
```dart
/// SyncService will rebuild the index if needed on next run.
```

**But:** There is no implemented index rebuild logic in SyncService.

---

## Severity Assessment

### How Often Does This Happen?

| Scenario | Frequency | Severity | Current Handling |
|----------|-----------|----------|------------------|
| Embedding API error | Medium (1 in 100 batches) | High (lost chunks) | Silent failure |
| Network timeout | Medium (intermittent) | High (incomplete index) | Silent failure |
| App crash mid-save | Low (but possible) | Critical (index corrupt) | Unhandled |
| Isar write error | Low (storage full, permissions) | High (index not updated) | Silent failure |

**Current problem:** All failures are silent. No detection, no logging, no recovery.

---

## Consistency Models: How Others Handle This

### Approach 1: Pessimistic Locking (PostgreSQL/MySQL)

```sql
BEGIN TRANSACTION;
UPDATE entities SET indexed = false WHERE id = 123;
COMMIT;
-- Insert into search index
-- If index fails, re-run index job
```

**How it works:**
- Mark entity as "pending indexing" in database
- Try to index
- If fails, retry job later
- If succeeds, mark as "indexed"

**Pros:** Guaranteed consistency, automatic retry
**Cons:** Requires database transaction, adds complexity

### Approach 2: Verification + Rebuild (Elasticsearch)

```
// Build index in background
// Keep old index live
// When new index ready, atomic switch
```

**How it works:**
- Maintain shadow index (new)
- Old index still live
- If new index incomplete, switch never happens
- Old index unchanged

**Pros:** No downtime, incremental building
**Cons:** 2x memory for dual indexes

### Approach 3: Checksum/Count Verification (Meilisearch)

```python
# Every search:
if index.doc_count != database.doc_count:
    # Index is stale
    print("Index behind by", database.doc_count - index.doc_count, "documents")
```

**How it works:**
- Track document count in index
- Track document count in entity repository
- On app startup, compare counts
- If mismatch: rebuild index

**Pros:** Simple, detects staleness immediately
**Cons:** False positives if partial updates

### Approach 4: Version Numbers (Pinecone/Qdrant)

```
Entity v3 + chunks v2 = stale
```

**How it works:**
- Each entity has version number
- Each chunk has entity_version reference
- On search, verify chunk.entity_version matches entity.version
- If mismatch: regenerate chunks

**Pros:** Fine-grained, handles partial updates
**Cons:** Requires tracking per-chunk

### Approach 5: Timestamp-Based Rebuild (Solr/Lucene)

```
if (index.lastUpdated < entity.updatedAt) {
    // Index is stale, rebuild from entity
}
```

**How it works:**
- Track last update time in index metadata
- Track last update time in entity
- On startup/periodic, compare timestamps
- If index older, rebuild

**Pros:** Simple, doesn't require counters
**Cons:** May false-trigger on timezone issues

---

## Recommended Approach: Count Verification + Versioning

### Phase 1: Detection (Immediate)

Add consistency verification at app startup:

```dart
// App initialization
Future<void> initializeIndexing() async {
  final entityCount = await entityRepository.countSemanticIndexable();
  final indexSize = hnswIndex.size;

  if (indexSize < entityCount) {
    logger.warn(
      'Index staleness detected: '
      'entities=$entityCount, index=$indexSize '
      '(${entityCount - indexSize} missing)'
    );

    // Decide: auto-rebuild or alert user
    if (autoRebuildOnDetection) {
      await rebuildIndex();
    } else {
      semanticSearchAvailable = false;
    }
  }
}
```

### Phase 2: Tracking Version Numbers

Add `chunkVersion` field to track entity version at time of chunking:

```dart
class SemanticIndexable {
  String uuid;
  int version;  // Entity version
  int chunkVersion;  // Version when chunks were last created
  List<String> chunkIds;  // IDs of chunks
}
```

On save:
```dart
Future<void> afterSave(SemanticIndexable entity) async {
  await chunkingService.indexEntity(entity);
  // After indexing succeeds:
  entity.chunkVersion = entity.version;
  await persistence.save(entity);  // Update metadata
}
```

On load:
```dart
SemanticIndexable loadEntity(uuid) {
  final entity = persistence.load(uuid);
  if (entity.chunkVersion != entity.version) {
    logger.warn('$uuid: chunks out of sync, will rebuild on next edit');
    indexAvailable = false;
  }
  return entity;
}
```

### Phase 3: Automatic Rebuild

Add rebuild endpoint:

```dart
class HnswIndexStore {
  /// Rebuild index from all semantic entities
  /// Used when index is detected as stale or corrupt
  Future<void> rebuild(EntityRepository repo) async {
    final index = HnswIndex(dimension: EmbeddingService.dimension);

    // Get all semantic-indexable entities
    final entities = await repo.getAllSemanticIndexable();

    for (final entity in entities) {
      try {
        final chunks = await chunkingService.chunkEntity(entity);
        final embeddings = await embeddingService.generateBatch(
          chunks.map((c) => c.text).toList()
        );

        for (var i = 0; i < chunks.length; i++) {
          index.insert(chunks[i].id, embeddings[i]);
        }
      } catch (e) {
        logger.error('Failed to index $entity: $e');
        // Continue with other entities
      }
    }

    // Replace old index atomically
    await save(index);
  }
}
```

### Phase 4: Trigger Rebuild

Rebuild can be triggered by:

**Automatic (on startup):**
```dart
if (!indexConsistent) {
  await hnswIndexStore.rebuild(repository);
}
```

**Manual (via app settings):**
```dart
Future<void> rebuildSearchIndex() async {
  showProgressDialog('Rebuilding search index...');
  await hnswIndexStore.rebuild(repository);
  await hnswIndexStore.save(index);
}
```

**Scheduled (background job):**
```dart
Timer.periodic(Duration(days: 1), (_) async {
  if (!indexConsistent) {
    await hnswIndexStore.rebuild(repository);
  }
});
```

---

## API Design Proposal

### Add to HnswIndexStore

```dart
class HnswIndexStore {
  /// Check if index is consistent with entity repository
  /// Returns number of missing chunks
  Future<int> verifyConsistency(EntityRepository repo) async {
    final entityCount = await repo.countSemanticIndexable();
    final indexCount = (await load())?.size ?? 0;
    return (entityCount * estimatedChunksPerEntity) - indexCount;
  }

  /// Rebuild entire index from all semantic entities
  /// Safe to call while other operations are pending
  /// Returns true if rebuild successful, false if partial
  Future<bool> rebuild(
    EntityRepository repo,
    EmbeddingService embeddingService,
    ChunkingService chunkingService,
  ) async {
    // Implementation above
  }

  /// Get metadata about index
  Future<IndexMetadata?> getMetadata() async {
    final data = await load();
    if (data == null) return null;
    return IndexMetadata(
      vectorCount: data.vectorCount,
      lastUpdated: data.updatedAt,
      isConsistent: (await verifyConsistency(repo)) == 0,
    );
  }
}

class IndexMetadata {
  final int vectorCount;
  final DateTime lastUpdated;
  final bool isConsistent;
}
```

### Add to SyncService

```dart
abstract class SyncService {
  /// Check if semantic index is stale
  Future<bool> isIndexStale() async {
    final missing = await hnswIndexStore.verifyConsistency(repo);
    return missing > 0;
  }

  /// Rebuild search index (long-running operation)
  /// Can be called periodically or on-demand
  Future<void> rebuildSearchIndex() async {
    await hnswIndexStore.rebuild(repo, embeddingService, chunkingService);
  }
}
```

---

## Implementation Plan

### Priority: High (affects core search functionality)

1. **Phase 1 (Immediate):** Count verification
   - Add startup check
   - Log staleness detection
   - Disable search if stale (safe mode)

2. **Phase 2 (Next):** Version tracking
   - Add `chunkVersion` field to SemanticIndexable
   - Track on save/load
   - Log mismatches

3. **Phase 3 (After Phase 2):** Rebuild implementation
   - Implement `HnswIndexStore.rebuild()`
   - Add rebuild endpoint
   - Handle errors gracefully (don't lose data)

4. **Phase 4 (Polish):** UI/Settings
   - Add "Rebuild Search Index" button to app settings
   - Show index health in UI
   - Manual trigger for users

---

## Testing Strategy

### Unit Tests

```dart
test('detects index staleness when chunk count mismatch', () async {
  // Create 10 entities with chunks
  // Delete 3 from index manually
  final missing = await store.verifyConsistency(repo);
  expect(missing, greaterThan(0));
});

test('rebuild succeeds even if embedding fails for one entity', () async {
  // Make one embedding request fail
  final success = await store.rebuild(repo, embeddingService, chunkingService);
  expect(success, true);  // Partial success, not failure
});

test('index still searchable after partial rebuild', () async {
  // Rebuild with one entity failing
  final results = await repo.semanticSearch('test');
  expect(results.isNotEmpty, true);
});
```

### Integration Tests

```dart
test('app restart after embedding failure loads old index', () async {
  // 1. Save entity, start embedding
  // 2. Crash app mid-embedding
  // 3. Restart app
  // 4. Verify: index is loaded, startup check detects staleness
});

test('rebuild fixes index consistency', () async {
  // 1. Corrupt index (save with wrong vector count)
  // 2. On startup, consistency check fails
  // 3. Rebuild triggered
  // 4. Index is fixed
});
```

### Scenario Tests

```gherkin
Scenario: Index becomes stale during embedding
  Given 10 entities with chunks
  When one embedding fails mid-process
  And app restarts
  Then startup check should detect staleness
  And search should be disabled until rebuild
  And rebuild button should be available
  And rebuild should succeed

Scenario: Manual rebuild completes successfully
  Given an app with stale index
  When user taps "Rebuild Index" button
  Then progress should be shown
  And search should be disabled during rebuild
  And search should re-enable when complete
  And index should be consistent
```

---

## Open Questions

1. **How frequently should automatic rebuilds run?**
   - Every app startup? (safest, but slow)
   - Daily? (background, user won't notice)
   - Only on detection? (lazy, might miss issues)

2. **Should we hide search during rebuild or return partial results?**
   - Hide: Guaranteed consistency, but poor UX
   - Partial: Search works, but might miss recent chunks

3. **Should old entities automatically rebuild chunks on edit?**
   - Yes: Chunks stay fresh
   - No: Only rebuild on startup (faster, but search is stale)

4. **What's the estimated chunk count per entity?**
   - Used for consistency verification
   - Could vary: 1-100 chunks per entity
   - Should this be tracked per-entity?

5. **Should we support index versioning/migrations?**
   - Different embedding models over time
   - Different chunking strategies
   - Rebuild needed when model changes

---

## Summary

| Aspect | Decision |
|--------|----------|
| **Detection** | Count verification + version tracking |
| **Repair** | Full rebuild from scratch (safest) |
| **Trigger** | Startup check + manual rebuild button |
| **Automation** | Lazy (rebuild only if detected stale) |
| **Fallback** | Disable search, show message to user |
| **Phase 1** | Verification + logging |
| **Phase 2** | Version tracking |
| **Phase 3** | Rebuild implementation |
| **Phase 4** | UI + settings integration |

The key insight: **Chunks are ephemeral** (can be rebuilt from entity text), so an incomplete index is not a data loss issue—it's a functionality issue. Build conservatively (detect early, rebuild completely) rather than trying to maintain consistency incrementally.
