# Tools Architecture

## Core Principle

**Each domain (task, timer, media, subscription) is self-contained and owns:**
- Entity definitions
- Persistence layer (repository + platform-specific adapters)
- Tool function definitions
- Tool registration with ToolRegistry

Bootstrap doesn't know about persistence. ToolExecutor doesn't create entities. Domains manage themselves.

## Pattern

### Domain Layer Structure
```
lib/tools/{domain}/
├── entities/        [Pure Dart POJOs - NO ORM decorators]
├── repositories/    [Repository - handles adapter selection internally]
├── adapters/        [ObjectBox (native) + IndexedDB (web)]
└── {domain}_tools.dart  [Tool functions + registerXxxTools()]
```

### Flow

1. **Bootstrap** creates repository → calls `registerTaskTools(registry, repo)` → done
2. **Domain** (task_tools.dart) defines tool functions that call the repository
3. **Registry** stores tool definitions + functions keyed by "task.create", "task.list", etc.
4. **ToolExecutor** looks up function by name → executes → returns result

### Key Details

**Repository owns adapter selection:**
- TaskRepository constructor detects platform (kIsWeb) and creates ObjectBoxAdapter or IndexedDBAdapter internally
- Bootstrap never touches adapters
- Same repository works on all platforms

**Tool functions are simple:**
- Take params map + repository
- Call repo methods
- Return JSON-serializable result map
- Registered via `registry.register(ToolDefinition(...), (params) => functionName(params, repo))`

**No platform-specific code in bootstrap:**
- No conditional imports
- No stubs
- No getIt<TaskRepository>() - just TaskRepository()

**No hardcoded dispatch in ToolExecutor:**
- toolRegistry.getTool('task.create') returns the function
- Execute it
- No if/else statements

## Adding New Tool Domain

1. Create `lib/tools/{domain}/` directory with entities/, repositories/, adapters/
2. Implement `{domain}_tools.dart` with tool functions + `register{Domain}Tools()`
3. In bootstrap: `register{Domain}Tools(getIt<ToolRegistry>(), repo)`
4. That's it.

## Critical Principle: No ORM Decorators in Entities

**Entities are pure Dart classes with NO ORM-specific code:**

```dart
// ✅ CORRECT - Task entity is platform-agnostic
class Task extends BaseEntity with Ownable, Invocable {
  String title;
  DateTime? dueDate;
  String priority;
  bool completed;
  // ... no @Entity(), @Id(), @Property(), @Transient()
}
```

**All ORM-specific logic lives in adapters:**

- **ObjectBox decorators** (@Entity, @Id, @Property, @Transient) → in TaskObjectBoxAdapter only
- **IndexedDB schema** (keyPath, indexes) → in TaskIndexedDBAdapter only
- **Sync configuration** (SyncStatus fields) → handled by adapter layer

This ensures:
- Domain code is platform-agnostic (no dart:ffi imports on web)
- Web compilation succeeds (no FFI analysis errors)
- Same entity works with multiple persistence backends
- Entities can be used in UI, services, and other layers without persistence concerns

## Platform Transparency

Web and native use the same code. The only difference:
- Native: TaskRepository → TaskObjectBoxAdapter → ObjectBox (with decorators)
- Web: TaskRepository → TaskIndexedDBAdapter → IndexedDB (no decorators)

The choice happens inside TaskRepository. Nobody else knows or cares.
