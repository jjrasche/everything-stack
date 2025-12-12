# Exception Handling Guide

## Platform-Agnostic Exception Hierarchy

All persistence exceptions extend `PersistenceException` and are platform-agnostic. Application code catches typed exceptions, never platform-specific errors.

```
PersistenceException (base)
├── EntityNotFoundException
├── DuplicateEntityException
├── QueryException
├── TransactionException
├── ConcurrencyException (reserved)
└── StorageLimitException
```

---

## Exception Types and When They're Thrown

### 1. EntityNotFoundException

**Thrown by:** Strict lookup methods (`getById`, `getByUuid`)
**NOT thrown by:** Optional methods (`findById`, `findByUuid`)

#### Usage Pattern

```dart
// ✅ Optional lookup - returns null if not found
final task = await adapter.findById(123);
if (task == null) {
  print('Task not found');
  return;
}

// ✅ Required lookup - throws if not found
try {
  final task = await adapter.getById(123);  // Must exist
  task.status = TaskStatus.completed;
  await adapter.save(task);
} on EntityNotFoundException catch (e) {
  print('Task ${e.id} was deleted by another process');
}
```

#### When to Use Which

| Scenario | Use |
|----------|-----|
| Loading for display (optional) | `findById()` / `findByUuid()` |
| Loading for update (must exist) | `getById()` / `getByUuid()` |
| Background processing (optional) | `findById()` / `findByUuid()` |
| Form edit (must exist) | `getById()` / `getByUuid()` |

**Rule of thumb:** If the entity not existing is an error condition, use `get*()`. If it's acceptable, use `find*()`.

---

### 2. DuplicateEntityException

**Thrown by:** Save operations that violate unique constraints

#### ObjectBox Triggers

- Composite key violation (Edge: sourceUuid+targetUuid+edgeType)
- UUID collision (extremely rare)
- Custom `@Unique()` annotations

#### Usage Pattern

```dart
try {
  final edge = Edge(
    sourceUuid: 'note-1',
    targetUuid: 'note-2',
    edgeType: 'links_to',
  );
  await edgeRepository.save(edge);
} on DuplicateEntityException catch (e) {
  print('Edge already exists: ${e.entityType}.${e.fieldName} = ${e.fieldValue}');
  // UI: "This connection already exists"
}
```

#### IndexedDB Triggers (Future)

- Same - any unique constraint violation
- Platform-agnostic handling

---

### 3. QueryException

**Thrown by:** Malformed queries, overflow, non-unique results

#### ObjectBox Triggers

- `NonUniqueResultException` - Query returned multiple when expecting one
- `NumericOverflowException` - Aggregate function overflow

#### Usage Pattern

```dart
try {
  final total = await repository.sumPrices();
} on QueryException catch (e) {
  print('Query failed: ${e.message}');
  if (e.query != null) {
    print('Query: ${e.query}');
  }
}
```

---

### 4. TransactionException

**Thrown by:** Transaction failures, rollbacks

#### ObjectBox Triggers

- Exception in transaction callback
- Nested transaction attempt (not supported)
- Platform rollback

#### Usage Pattern

```dart
try {
  await txManager.transaction((ctx) {
    noteAdapter.saveInTx(ctx, note);
    versionAdapter.saveInTx(ctx, version);
    return note.id;
  });
} on TransactionException catch (e) {
  print('Transaction failed: ${e.message}');
  if (e.rolledBack) {
    print('Changes were rolled back');
  }
}
```

---

### 5. StorageLimitException

**Thrown by:** Disk space / quota exceeded

#### ObjectBox Triggers

- Disk full
- Storage errors containing 'quota', 'disk', or 'space'

#### IndexedDB Triggers (Future)

- QuotaExceededError
- Blob too large

#### Usage Pattern

```dart
try {
  await repository.save(largeNote);
} on StorageLimitException catch (e) {
  print('Storage limit exceeded');
  if (e.requestedSize != null && e.availableSpace != null) {
    print('Requested: ${e.requestedSize}, Available: ${e.availableSpace}');
  }
  // UI: "Storage full - please free up space or delete old notes"
}
```

---

### 6. ConcurrencyException

**Reserved for future optimistic locking.**

When implemented:
```dart
try {
  task.version = 5;
  await repository.save(task);  // Another process saved version 6
} on ConcurrencyException catch (e) {
  print('Entity ${e.uuid} was modified by another process');
  // Reload and retry
}
```

Not currently used (no optimistic locking yet).

---

### 7. PersistenceException (Catch-All)

**Thrown by:** Any persistence error not matching specific types

#### Usage Pattern

```dart
try {
  await repository.save(entity);
} on DuplicateEntityException catch (e) {
  // Handle duplicate
} on StorageLimitException catch (e) {
  // Handle quota
} on PersistenceException catch (e) {
  // Catch-all for other persistence errors
  logger.error('Persistence error', error: e.cause, stackTrace: e.stackTrace);
}
```

---

## Repository-Level Error Handling

Repositories can catch and re-throw domain-specific exceptions:

```dart
class TaskRepository extends EntityRepository<Task> {
  @override
  Future<int> save(Task task) async {
    try {
      return await super.save(task);
    } on DuplicateEntityException catch (e) {
      throw TaskAlreadyExistsException(
        'Task "${task.title}" already exists',
        cause: e,
      );
    } on StorageLimitException catch (e) {
      throw InsufficientStorageException(
        'Cannot save task - storage full',
        cause: e,
      );
    }
    // Let other PersistenceExceptions bubble up
  }
}
```

---

## UI-Level Error Handling

```dart
class TaskScreen extends StatelessWidget {
  Future<void> _saveTask(Task task) async {
    try {
      await taskRepository.save(task);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task saved')),
      );
    } on EntityNotFoundException catch (e) {
      _showError('Task not found - may have been deleted');
    } on DuplicateEntityException catch (e) {
      _showError('Task already exists: ${e.fieldValue}');
    } on StorageLimitException catch (e) {
      _showError('Storage full - please delete old tasks');
    } on PersistenceException catch (e) {
      _showError('Failed to save: ${e.message}');
      logger.error('Save failed', error: e.cause, stackTrace: e.stackTrace);
    }
  }
}
```

---

## Testing Error Handling

### Test EntityNotFoundException

```dart
test('getById throws EntityNotFoundException when not found', () async {
  expect(
    () => adapter.getById(999),
    throwsA(isA<EntityNotFoundException>()
      .having((e) => e.id, 'id', 999)
      .having((e) => e.entityType, 'entityType', 'Note')),
  );
});
```

### Test DuplicateEntityException

```dart
test('save throws DuplicateEntityException for unique violation', () async {
  final edge1 = Edge(
    sourceUuid: 'a',
    targetUuid: 'b',
    edgeType: 'links_to',
  );
  await repository.save(edge1);

  final edge2 = Edge(
    sourceUuid: 'a',
    targetUuid: 'b',
    edgeType: 'links_to',  // Same composite key
  );

  expect(
    () => repository.save(edge2),
    throwsA(isA<DuplicateEntityException>()),
  );
});
```

---

## Platform Exception Mapping

### ObjectBox → Typed Exceptions

| ObjectBox Exception | Typed Exception | Mapping Logic |
|---------------------|-----------------|---------------|
| `UniqueViolationException` | `DuplicateEntityException` | Direct mapping |
| `NonUniqueResultException` | `QueryException` | Multiple results when expecting one |
| `NumericOverflowException` | `QueryException` | Aggregate overflow |
| `StorageException` (quota/disk/space) | `StorageLimitException` | Message content check |
| `StorageException` (other) | `PersistenceException` | Generic storage error |
| `SchemaException` | `PersistenceException` | Schema/migration error |
| Other `ObjectBoxException` | `PersistenceException` | Catch-all |
| Unknown exceptions | `PersistenceException` | Wrap with cause |

### IndexedDB → Typed Exceptions (Future)

| IndexedDB Error | Typed Exception | Mapping Logic |
|-----------------|-----------------|---------------|
| `DOMException` (ConstraintError) | `DuplicateEntityException` | Unique constraint |
| `DOMException` (QuotaExceededError) | `StorageLimitException` | Storage quota |
| `DOMException` (DataError) | `QueryException` | Query error |
| `DOMException` (TransactionInactiveError) | `TransactionException` | Transaction closed |
| Other `DOMException` | `PersistenceException` | Catch-all |

---

## Implementation Details

### BaseObjectBoxAdapter Exception Translation

```dart
Never _translateException(Object error, StackTrace stackTrace) {
  final entityType = T.toString();

  if (error is UniqueViolationException) {
    throw DuplicateEntityException(
      entityType,
      'unique constraint',
      fieldValue: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is StorageException) {
    final message = error.toString();
    if (message.contains('quota') ||
        message.contains('disk') ||
        message.contains('space')) {
      throw StorageLimitException(
        'Storage limit exceeded for $entityType',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    throw PersistenceException(
      'Storage error: $message',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // ... other mappings

  // Unknown - wrap as PersistenceException
  throw PersistenceException(
    'Unexpected error with $entityType: $error',
    cause: error,
    stackTrace: stackTrace,
  );
}
```

### Wrapped Operations

Exception handling wraps:
- ✅ `save()` / `saveAll()`
- ✅ `saveInTx()` / `saveAllInTx()`
- ✅ `deleteInTx()` / `deleteAllInTx()`

NOT wrapped (return null/false):
- `findById()` / `findByUuid()` / `findAll()`
- `delete()` / `deleteByUuid()`

---

## Best Practices

### 1. Use Specific Exceptions

```dart
// ❌ Bad - catches everything
try {
  await repository.save(task);
} catch (e) {
  print('Error: $e');
}

// ✅ Good - catches specific types
try {
  await repository.save(task);
} on DuplicateEntityException catch (e) {
  // Handle duplicate
} on StorageLimitException catch (e) {
  // Handle quota
} on PersistenceException catch (e) {
  // Catch-all
}
```

### 2. Preserve Context

```dart
// ✅ All exceptions include cause and stackTrace
try {
  await repository.save(task);
} on PersistenceException catch (e) {
  logger.error(
    'Save failed: ${e.message}',
    error: e.cause,  // Original ObjectBox exception
    stackTrace: e.stackTrace,
  );
}
```

### 3. Use find* vs get*

```dart
// ❌ Bad - handling null when entity MUST exist
final task = await adapter.findById(id);
if (task == null) {
  throw Exception('Task not found');
}

// ✅ Good - use getById when entity must exist
try {
  final task = await adapter.getById(id);  // Throws if not found
  // ...
} on EntityNotFoundException catch (e) {
  // Handle missing entity
}
```

### 4. Don't Swallow Exceptions

```dart
// ❌ Bad - silently ignores errors
try {
  await repository.save(task);
} catch (e) {
  // Silent failure
}

// ✅ Good - log or propagate
try {
  await repository.save(task);
} on PersistenceException catch (e) {
  logger.error('Save failed', error: e);
  rethrow;  // Or throw domain exception
}
```

---

## Summary

**Exception handling is:**
- ✅ Platform-agnostic (ObjectBox/IndexedDB → typed exceptions)
- ✅ Type-safe (7 exception types + base)
- ✅ Debuggable (cause + stackTrace preserved)
- ✅ Consistent (`find*` returns null, `get*` throws exception)

**Application code never sees ObjectBox or IndexedDB exceptions.**
