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

---

## When Do Tools Create Events?

**Tools create events only when coordinator inference is needed to decide next steps. Otherwise, tools are synchronous.**

### The Delineation

**If tool result requires coordinator to think:** → Tool result becomes an event asking for decision
**If tool result is just data flow:** → Tool returns synchronously to caller/LLM

### Examples

#### Tool Result Becomes Event (Coordinator Must Decide)

**Opportunity Searcher** returns matching opportunities
- Context: Coordinator invoked searcher with user's goals/narratives
- Result: List of 5 matching opportunities
- Question: Should we recommend one? Dismiss some? Ask user?
- Solution: `OpportunitySuggestions` event publishes list + original context
- Coordinator listens, re-evaluates with current context, decides

**Tool Execution Fails**
- Context: Timer tool couldn't set timer (API down, bad params, etc.)
- Result: Error object
- Question: Retry? Fallback? Notify user differently?
- Solution: `ErrorOccurred` event publishes failure details
- Coordinator listens, decides recovery strategy

**Key Pattern:** Result + original context together require coordinator decision-making = event

#### Tool Result Stays Synchronous (No Coordinator Inference)

**Task.create** completes
- Context: LLM asked coordinator to create task
- Result: Task ID + confirmation
- Question: None. Tool did exactly what was asked.
- Solution: Return result synchronously
- Coordinator receives result, passes to LLM for response formatting

**Timer.set** completes
- Context: LLM asked coordinator to set timer
- Result: Timer object with duration + start time
- Question: None. Tool completed its job.
- Solution: Return result synchronously
- LLM receives result, tells user "timer set for 5 minutes"

**Opportunity Searcher returns results** (to LLM, not coordinator)
- Context: Coordinator gave searcher criteria, already has context loaded
- Result: List of opportunities
- Question: None. Searcher completed.
- Solution: Return results synchronously to caller (could be coordinator or direct LLM invocation)
- LLM receives list, parses against context already provided, suggests one to user

**Key Pattern:** Tool completed its job, result is final/consumable = synchronous

### Decision Tree

When designing a tool, ask:

1. **Does the tool result need coordinator to re-think the situation?**
   - YES → Event
   - NO → Synchronous

2. **Did the result change something that affects decision-making?**
   - YES → Event
   - NO → Synchronous

3. **Is the result a suggestion/option that needs evaluation?**
   - YES → Event
   - NO → Synchronous

4. **Is the result an error requiring recovery strategy?**
   - YES → Event (ErrorOccurred)
   - NO → Synchronous

### Implementation

**Tools that publish events:**
```dart
Future<void> opportunitySearcherTool(Map params, OpportunityRepository repo) async {
  final results = await repo.searchByContext(params);
  
  // This result needs coordinator decision → publish event
  eventBus.publish(OpportunitySuggestions(
    correlationId: params['correlationId'],
    opportunities: results,
    searchContext: params['context'],
  ));
}
```

**Tools that return synchronously:**
```dart
Future<Map<String, dynamic>> taskCreateTool(Map params, TaskRepository repo) async {
  final task = await repo.create(
    title: params['title'],
    dueDate: params['dueDate'],
  );
  
  // Tool is done → return result, no event
  return {
    'taskId': task.id,
    'title': task.title,
    'created': task.createdAt.toIso8601String(),
  };
}
```

---

## MVP Tools (All Synchronous)

For the initial release, all tools are synchronous:
- task.create, task.list, task.update, task.delete
- timer.set, timer.list, timer.cancel
- media.play, media.stop
- subscription.create, subscription.manage

No tool-to-event loops yet. Simple tool invocation with results returned directly.

Event infrastructure is built and tested, but tools don't use it for MVP. Events come in Opportunity Marketplace phase (external tool results needing coordinator decision).