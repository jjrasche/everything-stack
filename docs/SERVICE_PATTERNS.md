# Service Patterns

Reference documentation for Everything Stack service architecture.

Read this before implementing new services or modifying service initialization.

---

## Service Architecture

Everything Stack uses **global singleton instances with explicit initialization**, not traditional dependency injection.

### Pattern Overview

```dart
abstract class ServiceName {
  // Default instance (safe fallback)
  static ServiceName instance = NullServiceName(); // or MockServiceName()

  // Lifecycle methods
  Future<void> initialize();
  void dispose();

  // Service methods
  Future<Result> doSomething();
}
```

**Key characteristics:**
- Global mutable state via `static instance` field
- Explicit initialization order in `bootstrap.dart`
- Safe defaults (Null Object or Mock) for optional services
- Platform-specific implementations via conditional imports

### NOT a Service Locator

This is NOT `get_it` or provider pattern. Services are:
- Globally accessible via `ServiceName.instance`
- Set once at app startup
- Replaced with mocks during testing via `instance = MockService()`

---

## Service Lifecycle

### Initialization

**Required pattern:**

```dart
abstract class MyService {
  Future<void> initialize();
  void dispose();

  // Safe check before operations (optional)
  bool get isReady;
}

// Production implementation
class RealMyService extends MyService {
  bool _isReady = false;

  @override
  Future<void> initialize() async {
    // Platform setup, resource allocation, validation
    await _setupPlatformResources();
    _isReady = true;
  }

  @override
  void dispose() {
    // Cleanup: close streams, release resources
    _streamController.close();
    _isReady = false;
  }

  Future<void> doSomething() async {
    if (!_isReady) await initialize(); // Lazy init fallback
    // ... perform operation
  }
}
```

### States

Services have three states:

1. **Uninitialized** - Created but `initialize()` not called
2. **Ready** - `initialize()` completed successfully
3. **Disposed** - `dispose()` called, resources released

**Best practice:** Check `_isReady` flag before operations, with lazy initialization fallback.

---

## Required vs Optional Services

### Required Services

**Must be initialized for app to function.** Bootstrap throws if initialization fails.

| Service | Purpose | Failure Impact |
|---------|---------|----------------|
| `PersistenceFactory` | Database (ObjectBox/IndexedDB) | Fatal - app cannot persist data |
| `BlobStore` | Binary file storage | Fatal - file operations fail |
| `FileService` | File picker integration | Fatal - cannot capture media |
| `ConnectivityService` | Network state monitoring | Fatal - offline detection broken |

**Pattern:**
```dart
// Throws on failure - app stops
final store = await initializePersistence();
BlobStore.instance = createPlatformBlobStore();
await BlobStore.instance.initialize(); // Throws on error
```

### Optional Services

**App degrades gracefully if not configured.** Use Null Object or Mock as fallback.

| Service | Purpose | Fallback Behavior |
|---------|---------|-------------------|
| `SyncService` | Supabase remote sync | Uses `MockSyncService` (no remote sync, local-only) |
| `EmbeddingService` | Semantic search embeddings | Uses `NullEmbeddingService` (zero vectors, no semantic search) |

**Pattern:**
```dart
if (hasApiKey) {
  EmbeddingService.instance = JinaEmbeddingService(apiKey: key);
}
// else: keeps NullEmbeddingService default (already set)
```

---

## Error Handling Patterns

### Exception Types

Use **typed exceptions** for domain errors, let platform exceptions bubble as generic errors.

**Example:**
```dart
// Typed domain exception
class MyServiceException implements Exception {
  final String message;
  final Object? cause;

  MyServiceException(this.message, {this.cause});
}

// In implementation
Future<void> doSomething() async {
  try {
    await platformOperation();
  } on PlatformException catch (e) {
    throw MyServiceException(
      'Platform operation failed: ${e.message}',
      cause: e,
    );
  }
}
```

### Error Strategies by Service Type

#### Network Services (API calls, sync)

**Current state:** No timeout, no retry, no circuit breaker

**Recommended pattern (not yet implemented):**

```dart
Future<Result> apiCall() async {
  try {
    return await http.post(url)
      .timeout(Duration(seconds: 30)); // Add timeout
  } on TimeoutException {
    // Log, return error, or retry
    throw MyServiceException('API timeout after 30s');
  } on SocketException {
    // Network unavailable
    throw MyServiceException('No network connection');
  }
}
```

**TODO:** Add timeout wrappers to:
- `JinaEmbeddingService.generateBatch()`
- `GeminiEmbeddingService.generate()`
- `SupabaseSyncService.pushEntity()`

#### Persistence Services

**Current pattern:** Fail-fast with typed exceptions

```dart
try {
  await adapter.save(entity);
} on DuplicateEntityException {
  // Handle unique constraint violation
} on StorageLimitException {
  // Handle quota exceeded
} on PersistenceException {
  // Generic database error
}
```

**No automatic retry** - caller decides recovery strategy.

#### Stream Services

**Current pattern:** Errors propagated via `StreamController.addError()`

```dart
StreamController<State> _controller = StreamController.broadcast();

void _onPlatformUpdate(State state) {
  try {
    final validated = _validateState(state);
    _controller.add(validated);
  } catch (e) {
    _controller.addError(e); // Propagate to listeners
  }
}
```

Listeners handle errors:
```dart
myService.onStateChanged.listen(
  (state) { /* handle state */ },
  onError: (error) { /* handle error */ },
);
```

---

## Bootstrap Initialization Order

**Why order matters:** Services have dependencies. Initialized in dependency order.

### Initialization Sequence

```dart
await initializeEverythingStack();
```

Executes in this order:

#### 1. PersistenceFactory (ObjectBox or IndexedDB)
```dart
_persistenceFactory = await initializePersistence();
```
**Why first:** All repositories depend on this
**Failure:** Fatal - throws `PersistenceException`

#### 2. BlobStore (FileSystem or IndexedDB)
```dart
final blobStore = createPlatformBlobStore();
await blobStore.initialize();
BlobStore.instance = blobStore;
```
**Why second:** FileService depends on this
**Failure:** Fatal - throws exception

#### 3. FileService
```dart
final fileService = RealFileService(blobStore: blobStore);
await fileService.initialize();
FileService.instance = fileService;
```
**Depends on:** BlobStore
**Failure:** Fatal - throws exception

#### 4. ConnectivityService
```dart
final connectivityService = ConnectivityPlusService();
await connectivityService.initialize();
ConnectivityService.instance = connectivityService;
```
**Independent:** No dependencies
**Failure:** Fatal - throws `ConnectivityServiceException`

#### 5. SyncService (optional)
```dart
if (cfg.hasSyncConfig) {
  final syncService = SupabaseSyncService(...);
  await syncService.initialize();
  SyncService.instance = syncService;
}
// else: keeps MockSyncService default
```
**Depends on:** None (optionally checks ConnectivityService in app code)
**Failure:** Graceful - uses MockSyncService

#### 6. EmbeddingService (optional)
```dart
if (cfg.jinaApiKey != null) {
  EmbeddingService.instance = JinaEmbeddingService(apiKey: cfg.jinaApiKey);
}
// else: keeps NullEmbeddingService default
```
**Depends on:** None
**Failure:** Graceful - uses NullEmbeddingService

### Adding New Services

**Follow this pattern:**

1. **Determine if required or optional**
   - Required: App cannot function without it
   - Optional: App degrades gracefully

2. **Set safe default**
   - Optional services: Use Null Object or Mock as `instance` initializer
   - Required services: Use `late` and throw if not initialized

3. **Add to bootstrap in dependency order**
   - After services it depends on
   - Before services that depend on it

4. **Handle initialization failure**
   - Required: Let exception bubble (app stops)
   - Optional: Log warning, keep default

---

## Null Object vs Throwing

### When to Use Null Object

**Use for optional features** where absence of functionality is acceptable.

```dart
class NullEmbeddingService extends EmbeddingService {
  @override
  Future<List<double>> generate(String text) async {
    print('Warning: Embeddings disabled. Configure API key to enable.');
    return List.filled(dimension, 0.0); // Safe no-op
  }
}
```

**Characteristics:**
- Returns safe default values (empty list, zero vector, etc.)
- Logs warnings when used
- Allows app to continue
- Used in production when feature is unavailable

**When appropriate:**
- Semantic search without API key → NullEmbeddingService
- Remote sync without Supabase config → MockSyncService (acts as null object)
- Analytics without tracking consent → NullAnalyticsService

### When to Throw

**Use for required operations** where failure indicates misconfiguration.

```dart
class JinaEmbeddingService extends EmbeddingService {
  Future<List<double>> generate(String text) async {
    _validateApiKey(); // Throws if missing
    return await _callApi(text);
  }

  void _validateApiKey() {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw EmbeddingServiceException(
        'JINA_API_KEY not configured. Pass apiKey to constructor.',
      );
    }
  }
}
```

**When appropriate:**
- Persistence adapter with missing database → Throw
- File service with no storage permissions → Throw
- API service called without credentials → Throw

### Decision Matrix

| Scenario | Pattern | Rationale |
|----------|---------|-----------|
| User doesn't configure optional API | Null Object | Feature unavailable, app continues |
| Database cannot initialize | Throw | Critical failure, app cannot function |
| Network call fails | Throw | Transient error, caller can retry |
| Missing required permission | Throw | User must grant permission |
| Service used before `initialize()` | Lazy init or throw | Depends on whether recoverable |

---

## Service Composition

### Constructor Injection (Preferred)

For services that compose other services:

```dart
class ChunkingService {
  final HnswIndex index;
  final EmbeddingService embeddingService;

  ChunkingService({
    required this.index,
    required this.embeddingService,
  });

  // Or use global instance as default
  ChunkingService({
    HnswIndex? index,
    EmbeddingService? embeddingService,
  }) : index = index ?? HnswIndex(),
       embeddingService = embeddingService ?? EmbeddingService.instance;
}
```

**Why:** Explicit dependencies, easy to test, no hidden global state.

### Global Instance Access

For cross-cutting services used everywhere:

```dart
class MyRepository {
  Future<void> syncEntity(Entity entity) async {
    final isOnline = await ConnectivityService.instance.isConnected();
    if (isOnline) {
      await SyncService.instance.syncEntity(entity.uuid);
    }
  }
}
```

**When acceptable:**
- Connectivity status (used everywhere)
- Logging (used everywhere)
- Analytics (used everywhere)

**Avoid for:** Domain services that have clear ownership.

---

## Testing Patterns

### Service Replacement

Replace global instances in test setup:

```dart
setUp(() {
  final mockSync = MockSyncService();
  SyncService.instance = mockSync;

  when(mockSync.syncEntity(any)).thenAnswer((_) async => SyncStatus.synced);
});

tearDown(() {
  // Optional: restore defaults
  SyncService.instance = MockSyncService();
});
```

### Mock vs Null Object in Tests

**MockService (for tests):**
- Deterministic behavior
- Controllable state
- Verifiable interactions

```dart
class MockConnectivityService extends ConnectivityService {
  ConnectivityState _state = ConnectivityState.wifi;

  void simulate(ConnectivityState state) {
    _state = state;
    _controller.add(state);
  }
}
```

**NullService (production fallback):**
- Safe no-op behavior
- Logs warnings
- No test-specific logic

Tests should use Mock, production should use Null Object.

---

## Common Pitfalls

### ❌ Using Mock as Production Fallback

```dart
// WRONG - test double in production
if (apiKey == null) {
  EmbeddingService.instance = MockEmbeddingService();
}
```

**Why wrong:** Mocks are for tests. Production should use Null Object.

**Correct:**
```dart
// Production fallback uses intentional no-op
if (apiKey == null) {
  EmbeddingService.instance = NullEmbeddingService();
}
```

### ❌ Swapping Services During Runtime

```dart
// WRONG - active streams will break
EmbeddingService.instance = JinaEmbeddingService(apiKey: newKey);
```

**Why wrong:** Existing references to old instance continue using it. Streams die.

**Correct:** Set once at startup, don't swap.

### ❌ Forgetting Initialization Order

```dart
// WRONG - FileService depends on BlobStore
FileService.instance = RealFileService(blobStore: BlobStore.instance);
BlobStore.instance = createPlatformBlobStore(); // Too late!
```

**Correct:** Initialize dependencies first (see Bootstrap Initialization Order).

### ❌ Not Handling Optional Service Absence

```dart
// WRONG - assumes EmbeddingService is configured
final embedding = await EmbeddingService.instance.generate(text);
// Throws if NullEmbeddingService!
```

**Correct:** Check if service is configured or handle null results:
```dart
if (EmbeddingService.instance is! NullEmbeddingService) {
  final embedding = await EmbeddingService.instance.generate(text);
  // Use embedding
} else {
  // Semantic search unavailable
}
```

---

## Future Improvements

### Needed (Not Yet Implemented)

1. **Timeout wrappers** for network calls
2. **Retry logic** with exponential backoff for transient failures
3. **Circuit breakers** for external APIs
4. **Structured logging** (replace `print` statements)
5. **Metrics/monitoring** for error rates
6. **Health checks** for service status reporting

### Architecture Gaps

- No automatic retry for sync failures (manual `syncAll()` required)
- No timeout on embedding API calls (can hang indefinitely)
- No backpressure handling for fast stream producers
- No service hot-swap safety (swapping kills in-flight streams)

See `docs/ARCHITECTURE_DECISIONS.md` for rationale on current approach.

---

## Summary

**Key Principles:**

1. **Required services throw, optional services degrade** (Null Object)
2. **Initialize in dependency order** (dependencies before dependents)
3. **Mocks are for tests, Null Objects are for production** fallbacks
4. **Set services once at startup**, don't swap at runtime
5. **Use typed exceptions**, propagate platform errors as generic
6. **Fail-fast on critical paths**, best-effort on non-critical

Read `lib/bootstrap.dart` for initialization implementation.
Read `lib/services/*.dart` for individual service patterns.
