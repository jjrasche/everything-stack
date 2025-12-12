# Adding a New Entity

This guide shows how to add a new entity type to the Everything Stack. Following this pattern ensures your entity gets full CRUD, transactions, sync, and semantic search (if Embeddable) with minimal code.

## The 8-Line Pattern

Adding a new entity requires creating just one file: the ObjectBox adapter. Everything else (CRUD, transactions, queries, sync) is inherited from `BaseObjectBoxAdapter`.

### Example: Adding a Task Entity

Assuming you already have:
- `lib/domain/task.dart` - Entity class extending `BaseEntity`
- ObjectBox codegen generated `Task_` query conditions

Create the adapter:

**`lib/persistence/objectbox/task_objectbox_adapter.dart`**

```dart
import 'package:objectbox/objectbox.dart';
import 'base_objectbox_adapter.dart';
import '../../core/base_entity.dart';
import '../../domain/task.dart';
import '../../objectbox.g.dart';

class TaskObjectBoxAdapter extends BaseObjectBoxAdapter<Task> {
  TaskObjectBoxAdapter(Store store) : super(store);

  @override
  Condition<Task> uuidEqualsCondition(String uuid) => Task_.uuid.equals(uuid);

  @override
  Condition<Task> syncStatusLocalCondition() =>
      Task_.dbSyncStatus.equals(SyncStatus.local.index);
}
```

**That's it.** 8 lines of entity-specific code.

Your adapter now has:
- ✅ Full CRUD (findById, findByUuid, findAll, save, saveAll, delete, deleteByUuid, deleteAll)
- ✅ Transaction support (all *InTx variants)
- ✅ Sync queries (findUnsynced, count)
- ✅ Proper query cleanup (automatic try/finally)
- ✅ Touch behavior (automatic updatedAt timestamps)
- ✅ Platform abstraction (implements PersistenceAdapter<Task>)

## What You Get for Free

### 1. CRUD Operations (Async)
```dart
final adapter = TaskObjectBoxAdapter(store);

// Create
final task = Task(title: 'Learn Flutter');
await adapter.save(task);

// Read
final found = await adapter.findByUuid(task.uuid);
final all = await adapter.findAll();

// Update
task.title = 'Master Flutter';
await adapter.save(task);  // Automatic touch()

// Delete
await adapter.delete(task.id);
await adapter.deleteByUuid(task.uuid);
```

### 2. Transaction Operations (Sync)
```dart
final txManager = ObjectBoxTransactionManager(store);

await txManager.transaction((ctx) {
  // All operations are atomic
  final task = adapter.findByUuidInTx(ctx, uuid);
  task.status = TaskStatus.completed;
  adapter.saveInTx(ctx, task);
  return task.id;
});
```

### 3. Sync Support
```dart
// Find entities pending sync
final unsynced = await adapter.findUnsynced();

// Mark as synced
task.syncStatus = SyncStatus.synced;
await adapter.save(task);
```

### 4. Repository Integration
```dart
class TaskRepository extends EntityRepository<Task> {
  TaskRepository({
    required TaskObjectBoxAdapter adapter,
    EmbeddingService? embeddingService,
    VersionRepository? versionRepository,
    TransactionManager? transactionManager,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService,
          versionRepository: versionRepository,
          transactionManager: transactionManager,
        );
}
```

Now `TaskRepository` has all repository features:
- Automatic embedding generation (if Task is Embeddable)
- Automatic version tracking (if Task is Versionable)
- Atomic saves with transactions
- Semantic search (if Task is Embeddable)

## Advanced: Entity-Specific Queries

If your entity needs custom queries beyond the base CRUD, add them to your adapter:

```dart
class TaskObjectBoxAdapter extends BaseObjectBoxAdapter<Task> {
  TaskObjectBoxAdapter(Store store) : super(store);

  @override
  Condition<Task> uuidEqualsCondition(String uuid) => Task_.uuid.equals(uuid);

  @override
  Condition<Task> syncStatusLocalCondition() =>
      Task_.dbSyncStatus.equals(SyncStatus.local.index);

  // ============ Task-specific queries ============

  Future<List<Task>> findByStatus(TaskStatus status) async {
    final query = box.query(Task_.dbStatus.equals(status.index)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<Task>> findDueToday() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = box
        .query(Task_.dueDate.between(
          startOfDay.millisecondsSinceEpoch,
          endOfDay.millisecondsSinceEpoch,
        ))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}
```

**Pattern:** Use the protected `box` getter for custom queries. Follow the try/finally pattern for cleanup.

## Advanced: Semantic Search (Embeddable Entities)

If your entity is `Embeddable` (has an embedding field), override the semantic search methods:

```dart
class TaskObjectBoxAdapter extends BaseObjectBoxAdapter<Task> {
  // ... base overrides ...

  @override
  Future<List<Task>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    final query = box
        .query(Task_.embedding.nearestNeighborsF32(queryVector, limit))
        .build();

    try {
      final results = query.findWithScores();

      // ObjectBox returns cosine distance, convert to similarity: 1 - distance
      final filtered = <Task>[];
      for (final result in results) {
        final similarity = 1.0 - result.score;
        if (similarity >= minSimilarity) {
          filtered.add(result.object);
        }
      }

      return filtered;
    } finally {
      query.close();
    }
  }

  @override
  int get indexSize {
    final query = box.query(Task_.embedding.notNull()).build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) async {
    final tasks = await findAll();

    for (final task in tasks) {
      if (task.embedding == null) {
        final embedding = await generateEmbedding(task);
        if (embedding != null) {
          task.embedding = embedding;
          await save(task);
        }
      }
    }
  }
}
```

## Advanced: Immutable Entities

If your entity shouldn't have `updatedAt` automatically set (like EntityVersion), override `shouldTouchOnSave`:

```dart
class AuditLogObjectBoxAdapter extends BaseObjectBoxAdapter<AuditLog> {
  AuditLogObjectBoxAdapter(Store store) : super(store);

  @override
  Condition<AuditLog> uuidEqualsCondition(String uuid) =>
      AuditLog_.uuid.equals(uuid);

  @override
  Condition<AuditLog> syncStatusLocalCondition() =>
      AuditLog_.dbSyncStatus.equals(SyncStatus.local.index);

  /// Audit logs are immutable - don't touch() them
  @override
  bool get shouldTouchOnSave => false;
}
```

## Specialized Adapter Interfaces

Some entities have domain-specific query needs. Create a specialized adapter interface:

**`lib/core/persistence/task_persistence_adapter.dart`**

```dart
import 'persistence_adapter.dart';
import '../domain/task.dart';

abstract class TaskPersistenceAdapter implements PersistenceAdapter<Task> {
  Future<List<Task>> findByStatus(TaskStatus status);
  Future<List<Task>> findDueToday();
  Future<List<Task>> findOverdue();
}
```

Then implement it:

```dart
class TaskObjectBoxAdapter extends BaseObjectBoxAdapter<Task>
    implements TaskPersistenceAdapter {
  // ... standard overrides ...

  @override
  Future<List<Task>> findByStatus(TaskStatus status) async {
    // ... implementation ...
  }

  @override
  Future<List<Task>> findDueToday() async {
    // ... implementation ...
  }

  @override
  Future<List<Task>> findOverdue() async {
    // ... implementation ...
  }
}
```

Now TaskRepository can depend on `TaskPersistenceAdapter` instead of the concrete ObjectBox implementation.

## Testing Your Adapter

Adapters are tested through repositories. See `test/domain/` for examples.

```dart
void main() {
  late Store store;
  late TaskObjectBoxAdapter adapter;
  late TaskRepository repository;

  setUp(() async {
    store = await openTestStore();
    adapter = TaskObjectBoxAdapter(store);
    repository = TaskRepository(adapter: adapter);
  });

  tearDown(() {
    store.close();
  });

  test('save creates task in database', () async {
    final task = Task(title: 'Test task');
    await repository.save(task);

    final found = await repository.findByUuid(task.uuid);
    expect(found, isNotNull);
    expect(found!.title, 'Test task');
  });
}
```

## IndexedDB (Web)

When you add IndexedDB support (future), you'll create:

**`lib/persistence/indexeddb/task_indexeddb_adapter.dart`**

```dart
class TaskIndexedDBAdapter extends BaseIndexedDBAdapter<Task> {
  // Same pattern, different platform
}
```

TaskRepository doesn't change - it works with both platforms through the `PersistenceAdapter<Task>` interface.

## Summary

**To add a new entity:**

1. Create entity class in `lib/domain/` extending `BaseEntity`
2. Add to ObjectBox schema and run codegen
3. Create adapter in `lib/persistence/objectbox/` (8 lines)
4. Create repository in `lib/domain/` (boilerplate constructor)
5. Write tests in `test/domain/`

**New entity cost:** ~50 lines total (entity class, adapter, repository, tests)

**You get:** Full CRUD, transactions, sync, versioning, embeddings, graph edges - everything the infrastructure provides.

This is "pay complexity once" - the infrastructure is paid for. New entities are cheap.
