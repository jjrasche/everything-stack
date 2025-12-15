# Ship Blockers: Two Fixes Required for Production Ready

**Status:** Both fixes are straightforward. Estimated: 1-2 hours total.

Once complete: Template is production-ready for handoff to coder. Then research items can proceed.

---

## Blocker 1: Cascade Delete for Edges (Estimated: 1 hour)

### Problem

When you delete an entity by UUID, edges referencing that entity (either as source or target) are NOT deleted. This causes:
- Orphaned edges pointing to deleted entities
- Data integrity issues
- Potential crashes when edge handler tries to load deleted entities

### Required Behavior

```dart
// When this executes:
await noteRepo.deleteByUuid(noteId);

// Then this MUST happen atomically (in same transaction):
// - Note entity deleted
// - All edges where source == noteId deleted
// - All edges where target == noteId deleted
// - All deletes rolled back if ANY fail
```

### Implementation Path

1. **Identify edge references**
   - Query EdgeRepository to find all edges where:
     - `source == entityId` OR
     - `target == entityId`

2. **Add to delete transaction**
   - Extend EntityRepository.deleteByUuid() to use TransactionManager
   - Inside transaction, delete entity first
   - Then delete all found edges (atomically)
   - All rolls back if any step fails

3. **Files to modify**
   - `lib/core/entity_repository.dart` - deleteByUuid() method
   - `lib/domain/edge_repository.dart` - May need delete helper
   - `lib/core/edge_repository.dart` - Might need `deleteInTx()` method

4. **Test coverage**
   - Delete entity with outbound edges → all edges deleted
   - Delete entity with inbound edges → all edges deleted
   - Delete entity with both inbound/outbound → all deleted
   - Cascade delete rollback (edge delete fails) → entity still exists

### Integration with Existing Code

- EntityRepository already has `transactionManager` field
- deleteByUuid() currently does non-transactional delete:
  ```dart
  Future<bool> deleteByUuid(String uuid) async {
    final entity = await findByUuid(uuid);
    if (entity == null) return false;

    for (final handler in handlers) {
      await handler.beforeDelete(entity);  // ← beforeDelete hooks exist
    }

    return adapter.deleteByUuid(uuid);  // ← Non-transactional
  }
  ```
- Need to wrap this in transaction, add edge cascade

---

## Blocker 2: Chunk Cleanup on Delete (Estimated: 1 hour)

### Problem

When you delete an entity, its semantic chunks are NOT deleted. This causes:
- Orphaned embeddings in the vector index
- Memory/storage waste
- Stale vectors in similarity search results

### Required Behavior

```dart
// When this executes:
await noteRepo.deleteByUuid(noteId);

// Then this MUST happen:
// - Note entity deleted
// - All chunks for that note deleted from index
// - All embeddings removed
// - Consistent state (no orphans)
```

### Implementation Path

The pattern already exists for save via handlers. Apply same pattern to delete:

1. **Extend handler lifecycle for delete**
   - Add `beforeDeleteInTransaction()` hook to RepositoryPatternHandler
   - SemanticIndexableHandler implements this hook
   - Hook runs inside transaction, same as save

2. **SemanticIndexableHandler.beforeDeleteInTransaction()**
   - Called before entity deletion (inside transaction)
   - Query for all chunks with `entityUuid == entity.uuid`
   - Delete each chunk from chunkingService
   - All cleanup rolls back if entity delete fails

3. **Files to modify**
   - `lib/core/repository_pattern_handler.dart` - Add beforeDeleteInTransaction() hook
   - `lib/core/handlers/semantic_indexable_handler.dart` - Implement cleanup
   - `lib/core/entity_repository.dart` - Call beforeDeleteInTransaction in delete transaction
   - `lib/services/chunking_service.dart` - May need deleteChunks(entityUuid) method

4. **Test coverage**
   - Delete SemanticIndexable entity → chunks deleted
   - Delete non-SemanticIndexable → no error
   - Delete rolls back → chunks still exist
   - Multiple chunks for one entity all deleted

### Integration with Existing Code

- Handler pattern already used for save lifecycle:
  ```dart
  // Handlers have these hooks:
  - beforeSave() / afterSave()
  - beforeSaveInTransaction() / afterSaveInTransaction()
  ```
- Add equivalent delete hooks:
  ```dart
  // New delete lifecycle hooks:
  - beforeDelete() / afterDelete()  [already exist in some handlers]
  - beforeDeleteInTransaction() / afterDeleteInTransaction()  [NEW]
  ```
- ChunkingService already exists, may just need delete method:
  ```dart
  Future<void> deleteChunksForEntity(String entityUuid) async {
    final chunks = await chunkRepo.findByEntityUuid(entityUuid);
    for (final chunk in chunks) {
      await chunkRepo.delete(chunk.id);
    }
  }
  ```

---

## Combined Implementation

### Delete Flow (After Both Fixes)

```
EntityRepository.deleteByUuid(entityId)
  ↓
Phase 1: beforeDelete hooks (async, outside transaction)
  ↓
Phase 2: Start transaction
  ├─ Phase 2a: beforeDeleteInTransaction hooks (sync, inside tx)
  │   └─ SemanticIndexableHandler.beforeDeleteInTransaction()
  │       └─ Delete chunks for entity
  │
  ├─ Phase 2b: Delete entity from adapter
  │
  ├─ Phase 2c: Delete cascading edges
  │   └─ Query/delete all edges by source/target
  │
  └─ Phase 2d: afterDeleteInTransaction hooks (sync, inside tx)
      └─ (Optional - usually empty for delete)
  ↓
Phase 3: Commit transaction (ALL succeed or ALL rollback)
  ↓
Phase 4: afterDelete hooks (async, outside transaction)
```

### Expected Files Modified

**Core Files:**
- `lib/core/entity_repository.dart` - delete flow
- `lib/core/repository_pattern_handler.dart` - hook definitions
- `lib/core/edge_repository.dart` - cascade delete helper
- `lib/core/handlers/semantic_indexable_handler.dart` - chunk cleanup

**Optional:**
- `lib/services/chunking_service.dart` - helper method if needed
- Domain repos extending EntityRepository - override delete if needed

### Test Files to Add/Modify

- `test/persistence/entity_delete_cascade_test.dart` - Edge cascade
- `test/services/semantic_indexing_delete_test.dart` - Chunk cleanup
- `test/services/handler_edge_cases_test.dart` - Update with delete scenarios

---

## Why These Unblock Production

1. **Data Integrity:** No orphaned edges or chunks
2. **Resource Cleanup:** Vectors/chunks actually removed when entities deleted
3. **Consistency:** Delete is atomic (entity + edges + chunks or nothing)
4. **Pattern Completion:** Delete lifecycle mirrors save lifecycle

Once these work:
- Template passes all data integrity checks
- Cross-platform delete is atomic
- Ready for production use
- Coder has firm foundation for next features

---

## Handoff Checklist for Coder

- [ ] Implement cascade delete for edges
  - [ ] EntityRepository.deleteByUuid uses TransactionManager
  - [ ] Query edges by source/target
  - [ ] Delete edges inside transaction
  - [ ] Tests: outbound, inbound, both, rollback scenarios

- [ ] Implement chunk cleanup on delete
  - [ ] Add beforeDeleteInTransaction() to handler interface
  - [ ] SemanticIndexableHandler.beforeDeleteInTransaction() deletes chunks
  - [ ] EntityRepository calls hook in transaction
  - [ ] Tests: cleanup occurs, non-semantic unaffected, rollback works

- [ ] Integration
  - [ ] Both happen in same transaction
  - [ ] All rollback if any step fails
  - [ ] Handler tests updated with delete scenarios

- [ ] Verification
  - [ ] All tests pass (18+ transaction tests + new delete tests)
  - [ ] Cross-repository delete is atomic
  - [ ] No orphaned data on delete
  - [ ] Delete behavior documented

---

## Then: Research Items (After Ship Blockers)

Once these fixes land and tests pass:

1. **Conflict Detection Strategy** (affects sync design)
   - Operational transform vs CRDT vs last-write-wins
   - Impacts: Supabase sync, version recording, real-time collab

2. **Vector Index Staleness** (affects consistency guarantees)
   - How stale can embeddings be vs live data?
   - Impacts: Search accuracy after edits, background reindexing

3. **Schema Evolution** (affects upgrade path)
   - How to migrate entity structures without data loss?
   - Impacts: ObjectBox schema changes, version compatibility

These are architectural questions, not implementation blockers. Can research in parallel once delete works.

---

## Summary

**Ship Blockers:** 2 features, ~2 hours total
- Cascade delete for edges (1 hour)
- Chunk cleanup on delete (1 hour)

**After:** Template is production-ready
**Then:** Research items for next-phase features

Ready for handoff. 🚀
