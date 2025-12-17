# Architecture FAQ

Answers to common questions about Everything Stack architecture.

Read this before designing new features or copying the template for production use.

---

## Timeout & Resilience

### Q: Where does timeout logic live?

**Current state:** Not implemented. Network calls can hang indefinitely.

**Recommended approach:** **Defense in depth** - timeouts at multiple layers:

```dart
// Layer 1: HTTP client level (global default)
class TimeoutHttpClient extends BaseClient {
  final Client _inner;
  final Duration timeout;

  TimeoutHttpClient(this._inner, {this.timeout = const Duration(seconds: 30)});

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }
}

// Layer 2: Service level (operation-specific)
class JinaEmbeddingService {
  static const Duration _embeddingTimeout = Duration(seconds: 45);

  Future<List<double>> generate(String text) async {
    return await _callApi(text).timeout(
      _embeddingTimeout,
      onTimeout: () => throw EmbeddingServiceException('API timeout after 45s'),
    );
  }
}

// Layer 3: Caller level (user-facing deadline)
Future<void> processDocument(Document doc) async {
  try {
    await embeddings.generate(doc.text).timeout(
      Duration(minutes: 2), // User-facing deadline
      onTimeout: () {
        // Log, show UI message, queue for retry
        throw ProcessingTimeoutException('Document too large');
      },
    );
  } catch (e) {
    // Handle or propagate
  }
}
```

**Why three layers:**
- **HTTP client**: Prevents connection leaks, socket exhaustion
- **Service**: Domain-appropriate timeout (embedding vs sync vs TTS)
- **Caller**: User experience deadline

**Not yet implemented.** TODO before production.

---

### Q: Are timeout values standardized?

**Recommended pattern:**

```dart
class TimeoutConfig {
  // Network operations
  static const httpDefault = Duration(seconds: 30);
  static const httpUpload = Duration(minutes: 5);

  // API services
  static const embeddingGeneration = Duration(seconds: 45);
  static const llmStreaming = Duration(seconds: 10); // Per chunk
  static const ttsGeneration = Duration(seconds: 20);
  static const sttProcessing = Duration(seconds: 30);

  // Sync operations
  static const entityPush = Duration(seconds: 15);
  static const blobPush = Duration(minutes: 10); // Large files
  static const pullAll = Duration(minutes: 5);

  // Background jobs
  static const embeddingQueue = Duration(seconds: 30); // Per batch
  static const indexRebuild = Duration(hours: 1);
}
```

**Per-service configuration:**
- Each service imports `TimeoutConfig`
- Can override in constructor for testing
- Documented in service class comments

**Not yet implemented.** Currently each service picks its own (or none).

---

### Q: When timeout happens, what's the recovery pattern?

**Depends on operation type:**

#### Idempotent Operations (safe to retry)
```dart
Future<Result> generateEmbedding(String text) async {
  return await _retryWithBackoff(
    () => _api.embed(text),
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    onTimeout: (attempt) {
      print('Embedding timeout, attempt $attempt/3');
    },
  );
}

Future<T> _retryWithBackoff<T>(
  Future<T> Function() operation, {
  required int maxAttempts,
  required Duration initialDelay,
  void Function(int)? onTimeout,
}) async {
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await operation().timeout(TimeoutConfig.embeddingGeneration);
    } on TimeoutException {
      if (attempt == maxAttempts) rethrow;
      onTimeout?.call(attempt);
      await Future.delayed(initialDelay * math.pow(2, attempt - 1));
    }
  }
  throw StateError('Unreachable');
}
```

#### Non-Idempotent Operations (mutations)
```dart
Future<void> pushEntity(Entity entity) async {
  try {
    await _api.push(entity.toJson()).timeout(TimeoutConfig.entityPush);
  } on TimeoutException {
    // Don't retry - might have succeeded on server
    // Queue for reconciliation instead
    await _conflictResolution.enqueue(entity);
    throw SyncTimeoutException(
      'Push timeout - queued for reconciliation',
      entity: entity,
    );
  }
}
```

#### User-Initiated Operations
```dart
Future<void> syncNow() async {
  try {
    await _sync().timeout(TimeoutConfig.pullAll);
  } on TimeoutException {
    // Show user-friendly error
    throw SyncException(
      'Sync timed out. Check your connection and try again.',
      recoverable: true,
    );
  }
}
```

**Current state:** No retry logic. Timeouts bubble as exceptions (when they exist).

---

### Q: How do you test timeout behavior?

**Pattern: Fake services with controllable delays**

```dart
class FakeEmbeddingService extends EmbeddingService {
  Duration? simulatedDelay;
  bool shouldTimeout = false;

  @override
  Future<List<double>> generate(String text) async {
    if (shouldTimeout) {
      await Future.delayed(Duration(hours: 1)); // Never completes in test time
    }
    if (simulatedDelay != null) {
      await Future.delayed(simulatedDelay!);
    }
    return List.filled(dimension, 0.5);
  }
}

// In test
test('Handles embedding timeout gracefully', () async {
  final fake = FakeEmbeddingService()..shouldTimeout = true;
  EmbeddingService.instance = fake;

  await expectLater(
    embeddings.generate('test').timeout(Duration(milliseconds: 100)),
    throwsA(isA<TimeoutException>()),
  );
});

test('Retries on timeout', () async {
  final fake = FakeEmbeddingService()..simulatedDelay = Duration(seconds: 2);
  int attempts = 0;

  await expectLater(
    _retryWithBackoff(
      () { attempts++; return fake.generate('test'); },
      maxAttempts: 3,
      initialDelay: Duration.zero, // Fast test
    ).timeout(Duration(milliseconds: 500)), // Short timeout for test
    throwsA(isA<TimeoutException>()),
  );

  expect(attempts, equals(3)); // Verify retry count
});
```

**Alternative: Mock with thenAnswer delays**
```dart
test('Handles slow API gracefully', () async {
  when(mockApi.embed(any)).thenAnswer(
    (_) async {
      await Future.delayed(Duration(seconds: 100));
      return [0.1, 0.2, 0.3];
    },
  );

  await expectLater(
    service.generate('text').timeout(Duration(milliseconds: 100)),
    throwsA(isA<TimeoutException>()),
  );
});
```

**Don't:** Actually wait for timeouts in tests. Use `shouldTimeout` flags or short test timeouts.

---

### Q: How are streaming operations different?

**WebSocket/SSE streams need different timeout semantics:**

```dart
class DeepgramSTTService {
  Stream<String> transcribe(Stream<Uint8List> audio) async* {
    final ws = await WebSocket.connect(url);

    // Connection timeout
    await ws.ready.timeout(
      Duration(seconds: 10),
      onTimeout: () => throw STTException('Connection timeout'),
    );

    // Idle timeout (no data received)
    yield* ws.cast<String>().transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          _lastDataTime = DateTime.now();
          sink.add(data);
        },
      ),
    ).timeout(
      Duration(seconds: 30), // Idle timeout
      onTimeout: (sink) {
        sink.addError(STTException('No data for 30s'));
        sink.close();
      },
    );
  }

  DateTime _lastDataTime = DateTime.now();
}
```

**Streaming timeout types:**
1. **Connection timeout**: WebSocket connect
2. **Idle timeout**: No data received (per-chunk deadline)
3. **Total timeout**: Maximum stream duration
4. **Heartbeat**: Keep-alive to prevent idle timeout

**Example: TTS streaming**
```dart
Stream<Uint8List> synthesize(String text) async* {
  final response = await http.post(url, body: text).timeout(
    Duration(seconds: 10), // Connection timeout
  );

  await for (final chunk in response.stream.timeout(
    Duration(seconds: 5), // Idle timeout between chunks
    onTimeout: (sink) {
      sink.addError(TTSException('Streaming stalled'));
      sink.close();
    },
  )) {
    yield chunk;
  }
}
```

**Not yet implemented** in this codebase. Will be critical for conversational AI.

---

## VersionableHandler & ObjectBox

### Q: What's the issue with VersionableHandler on ObjectBox?

**Problem:** Version tracking silently fails on ObjectBox (native platforms).

**Root cause:** `VersionableHandler` was designed for IndexedDB (web) where transactions are explicit. On ObjectBox, the transaction context doesn't propagate correctly through the handler chain.

**Current behavior:**
- **Web (IndexedDB):** Versions saved correctly ✓
- **Native (ObjectBox):** Versions never created ✗

**Why it fails:**
```dart
// In VersionableHandler
@override
Future<void> beforeSave(T entity, dynamic context) async {
  final version = EntityVersion.fromEntity(entity);

  // This tries to save in a separate transaction!
  // ObjectBox sees it as concurrent write, might fail or be ignored
  await _versionRepo.save(version);
}
```

ObjectBox transactions are synchronous and thread-local. Async saves in handlers break the transaction boundary.

---

### Q: What's the architectural fix?

**Option 1: Make versioning async (like embeddings)**

```dart
class VersionQueueService {
  Future<void> enqueueVersion(String entityUuid, String entityType, Map<String, dynamic> snapshot) async {
    final task = VersionTask(
      entityUuid: entityUuid,
      entityType: entityType,
      snapshot: snapshot,
      timestamp: DateTime.now(),
    );
    _taskBox.put(task);
  }

  Future<void> _processBatch() async {
    // Background version creation
    final tasks = _getPendingTasks();
    for (final task in tasks) {
      await _versionRepo.save(EntityVersion.fromTask(task));
      task.status = TaskStatus.completed;
      _taskBox.put(task);
    }
  }
}
```

**Pros:**
- Consistent with embedding queue pattern
- Works on all platforms
- Doesn't block saves

**Cons:**
- Versions created slightly after save (eventual consistency)
- Adds complexity

---

**Option 2: Platform-specific versioning**

```dart
// On ObjectBox: Save versions in same transaction (sync)
class ObjectBoxVersionableHandler extends VersionableHandler {
  @override
  T saveInTx(TransactionContext ctx, T entity) {
    // Extract ObjectBox write transaction
    final obCtx = ctx as ObjectBoxTxContext;
    final versionBox = obCtx.store.box<EntityVersionOB>();

    // Synchronous save in same transaction
    final version = EntityVersion.fromEntity(entity);
    final versionOB = EntityVersionOBAdapter().toOB(version);
    versionBox.put(versionOB); // Sync!

    return entity;
  }
}

// On IndexedDB: Async versioning works as-is
class IndexedDBVersionableHandler extends VersionableHandler {
  // Current implementation
}
```

**Pros:**
- Platform-optimized
- Versions guaranteed consistent with entity

**Cons:**
- Platform-specific code in handler (violates abstraction)
- More complex

---

**Option 3: Disable versioning on ObjectBox, document why**

```dart
class GenericHandlerFactory {
  List<RepositoryPatternHandler<T>> createHandlers() {
    if (isWeb) {
      // Versioning only works on web
      handlers.add(VersionableHandler(...));
    } else {
      print('Warning: Entity versioning disabled on native platforms');
      // TODO: Implement ObjectBox-compatible versioning
    }
  }
}
```

**Pros:**
- Simple
- Honest about limitations

**Cons:**
- Feature unavailable on native
- Users might need it

---

**Recommendation:** **Option 1 (async queue)** for consistency with embedding pattern.

**Not yet implemented.** Versioning currently broken on ObjectBox.

---

## Service vs Repository vs Handler

### Q: When should I use a Service? A Repository? A Handler?

**Service:**
- **What:** Stateless operations, external integrations, cross-cutting concerns
- **Examples:** `EmbeddingService`, `SyncService`, `ConnectivityService`, `FileService`
- **Characteristics:**
  - No entity ownership
  - Often talks to external APIs or platform services
  - Global singleton (`Service.instance`)
  - Reusable across entities

**Repository:**
- **What:** CRUD operations for a specific entity type
- **Examples:** `NoteRepository`, `EdgeRepository`, `VersionRepository`
- **Characteristics:**
  - Owns persistence for one entity type
  - Delegates to `PersistenceAdapter` for storage
  - Coordinates handlers for cross-cutting concerns
  - One repository per entity

**Handler:**
- **What:** Lifecycle hooks that execute before/after entity operations
- **Examples:** `VersionableHandler`, `EdgeCascadeDeleteHandler`, `EmbeddingQueueHandler` (if we made one)
- **Characteristics:**
  - Attached to repositories via patterns (`with Versionable`, `with Edgeable`)
  - Runs automatically on save/delete
  - Stateless, composable

---

### Decision Matrix

| You need to... | Use... | Example |
|----------------|--------|---------|
| Save/load an entity | **Repository** | `noteRepo.save(note)` |
| Call external API | **Service** | `EmbeddingService.instance.generate(text)` |
| Auto-create versions on save | **Handler** | `VersionableHandler` attached to repo |
| Check network status | **Service** | `ConnectivityService.instance.isConnected()` |
| Delete related entities | **Handler** | `EdgeCascadeDeleteHandler` |
| Process uploaded files | **Service** | `FileService.instance.pickFile()` |
| Background async work | **Service** | `EmbeddingQueueService` |

---

### Q: What if services conflict?

**Example conflict:** `EmbeddingService` needs timeout, but `VersionableHandler` depends on it completing synchronously.

**Resolution strategies:**

#### 1. Make handler async-safe
```dart
class EmbeddingQueueHandler extends RepositoryPatternHandler {
  @override
  Future<void> afterSave(Entity entity, dynamic ctx) async {
    // Don't wait for embedding - queue it
    await _queue.enqueue(
      entityUuid: entity.uuid,
      text: entity.searchableText,
    );
    // Handler completes immediately, embedding happens later
  }
}
```

**Rule:** Handlers should never block on slow operations.

---

#### 2. Remove handler, use repository override
```dart
class NoteRepository {
  @override
  Future<int> save(Note entity) async {
    final id = await super.save(entity); // Persist first

    // Then call conflicting service
    try {
      await _embeddingService.generate(entity.text).timeout(Duration(seconds: 30));
    } catch (e) {
      // Log but don't fail the save
      print('Embedding failed: $e');
    }

    return id;
  }
}
```

**Rule:** Repository orchestrates when timing matters.

---

#### 3. Service composition
```dart
class EmbeddingService {
  Future<List<double>> generate(String text) async {
    // Synchronous fast path (cached result)
    final cached = _cache[text];
    if (cached != null) return cached;

    // Async slow path
    return await _callApi(text).timeout(...);
  }
}
```

**Rule:** Provide fast synchronous path when possible.

---

### Q: What's the pattern for streaming services (STT/TTS/LLM)?

**Recommended contract:**

```dart
abstract class StreamingService {
  /// Initialize connection, authenticate
  Future<void> initialize();

  /// Start streaming, return input sink
  StreamSubscription<Output> stream({
    required Stream<Input> input,
    required void Function(Output) onData,
    required void Function(Object) onError,
    void Function()? onDone,
  });

  /// Cleanup
  void dispose();
}
```

**Example: Speech-to-Text**
```dart
abstract class STTService extends StreamingService {
  static STTService instance = NullSTTService();

  /// Stream audio bytes, receive transcription chunks
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    required void Function(Object) onError,
    void Function()? onDone,
  });
}

class DeepgramSTTService extends STTService {
  WebSocket? _ws;

  @override
  Future<void> initialize() async {
    _ws = await WebSocket.connect(url).timeout(Duration(seconds: 10));
  }

  @override
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    // Send audio to WebSocket
    audio.listen((chunk) => _ws!.add(chunk));

    // Receive transcripts
    return _ws!.cast<String>().listen(
      onTranscript,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  void dispose() {
    _ws?.close();
  }
}

class NullSTTService extends STTService {
  @override
  StreamSubscription<String> transcribe(...) {
    onError(STTException('STT not configured'));
    return Stream<String>.empty().listen(null);
  }
}
```

**Example: Text-to-Speech**
```dart
abstract class TTSService extends StreamingService {
  static TTSService instance = NullTTSService();

  /// Stream text, receive audio bytes
  Stream<Uint8List> synthesize(String text);
}

class GoogleTTSService extends TTSService {
  @override
  Stream<Uint8List> synthesize(String text) async* {
    final response = await http.post(
      url,
      body: {'text': text},
    ).timeout(Duration(seconds: 10));

    await for (final chunk in response.stream.timeout(
      Duration(seconds: 5), // Idle timeout
      onTimeout: (sink) {
        sink.addError(TTSException('Stream timeout'));
        sink.close();
      },
    )) {
      yield chunk;
    }
  }
}
```

**Example: LLM Streaming**
```dart
abstract class LLMService {
  static LLMService instance = NullLLMService();

  /// Stream chat messages, receive response tokens
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
  });
}

class ClaudeService extends LLMService {
  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
  }) async* {
    final response = await http.post(
      url,
      headers: {'anthropic-version': '2023-06-01', 'x-api-key': _apiKey},
      body: jsonEncode({
        'messages': [...history, {'role': 'user', 'content': userMessage}],
        'stream': true,
      }),
    ).timeout(Duration(seconds: 10)); // Connection timeout

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .timeout(
          Duration(seconds: 30), // Idle timeout (no token for 30s)
          onTimeout: (sink) {
            sink.addError(LLMException('Stream stalled'));
            sink.close();
          },
        )) {
      if (line.startsWith('data: ')) {
        final json = jsonDecode(line.substring(6));
        if (json['type'] == 'content_block_delta') {
          yield json['delta']['text'];
        }
      }
    }
  }
}
```

**Key patterns:**
- Input and output as streams (bidirectional)
- Timeout on connection AND idle
- Null Object fallback
- Error propagation via stream

**Not yet implemented.** Will be critical for conversational AI.

---

## Error Handling

### Q: Should we use Result types or exceptions?

**Current approach:** **Exceptions**

**Rationale:**
- Dart's async/await naturally propagates errors
- `try-catch` is familiar to most developers
- No `Result<T, E>` type in Dart standard library

**Recommended pattern:**

```dart
// Throw typed exceptions
class EmbeddingServiceException implements Exception {
  final String message;
  final Object? cause;

  EmbeddingServiceException(this.message, {this.cause});

  @override
  String toString() => 'EmbeddingServiceException: $message';
}

// Caller handles with try-catch
try {
  final embedding = await EmbeddingService.instance.generate(text);
  // Use embedding
} on EmbeddingServiceException catch (e) {
  // Handle embedding-specific error
  log.error('Embedding failed', error: e);
  // Fallback: skip semantic search
} on TimeoutException {
  // Handle timeout
} catch (e) {
  // Generic error
  rethrow;
}
```

**If you prefer Result types:**

```dart
// Define Result type (not in stdlib)
abstract class Result<T, E> {
  factory Result.ok(T value) = Ok<T, E>;
  factory Result.err(E error) = Err<T, E>;

  bool get isOk;
  bool get isErr;

  T? get value;
  E? get error;

  T unwrap();
  T unwrapOr(T defaultValue);
  U fold<U>(U Function(T) onOk, U Function(E) onErr);
}

// Service returns Result
class EmbeddingService {
  Future<Result<List<double>, EmbeddingError>> generate(String text) async {
    try {
      final embedding = await _api.embed(text);
      return Result.ok(embedding);
    } on TimeoutException {
      return Result.err(EmbeddingError.timeout);
    } catch (e) {
      return Result.err(EmbeddingError.unknown);
    }
  }
}

// Caller pattern-matches
final result = await embeddings.generate(text);
if (result.isOk) {
  note.embedding = result.value;
} else {
  switch (result.error) {
    case EmbeddingError.timeout:
      // Retry
    case EmbeddingError.unknown:
      // Log
  }
}
```

**Tradeoff:**
- **Exceptions:** Idiomatic Dart, less boilerplate
- **Result types:** Explicit error handling, type-safe

**Current codebase uses exceptions.** Could adopt Result types for network services if preferred.

---

## Documentation

### Q: How do I add a new service?

**Step-by-step guide:**

#### 1. Define the abstract service interface

```dart
// lib/services/my_service.dart

/// MyService provides [brief description].
///
/// ## Initialization
/// Call `await MyService.instance.initialize()` in bootstrap.
///
/// ## Error handling
/// Throws [MyServiceException] on [specific failure conditions].
///
/// ## Platform support
/// - Native (Android/iOS/Desktop): [RealMyService]
/// - Web: [WebMyService]
/// - Fallback: [NullMyService] (when [condition])
abstract class MyService {
  /// Global instance (default: NullMyService)
  static MyService instance = NullMyService();

  /// Initialize platform resources
  Future<void> initialize();

  /// Cleanup
  void dispose();

  /// Check if ready to use
  bool get isReady;

  /// Main service method
  Future<Output> doSomething(Input input);
}
```

#### 2. Implement production service

```dart
// lib/services/my_service_impl.dart

class RealMyService extends MyService {
  bool _isReady = false;

  @override
  Future<void> initialize() async {
    // Platform setup
    await _setupPlatformResources();
    _isReady = true;
  }

  @override
  void dispose() {
    // Cleanup
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;

  @override
  Future<Output> doSomething(Input input) async {
    if (!_isReady) await initialize(); // Lazy init

    try {
      return await _platformOperation(input).timeout(
        TimeoutConfig.myServiceOperation,
      );
    } on TimeoutException {
      throw MyServiceException('Operation timeout');
    } on PlatformException catch (e) {
      throw MyServiceException('Platform error: ${e.message}', cause: e);
    }
  }
}
```

#### 3. Implement Null Object fallback

```dart
// lib/services/my_service_impl.dart

class NullMyService extends MyService {
  @override
  Future<void> initialize() async {
    print('Warning: MyService not configured');
  }

  @override
  void dispose() {}

  @override
  bool get isReady => false;

  @override
  Future<Output> doSomething(Input input) async {
    print('Warning: MyService unavailable - using fallback');
    return Output.empty(); // Safe no-op
  }
}
```

#### 4. Add to bootstrap (optional service)

```dart
// lib/bootstrap.dart

Future<void> initializeEverythingStack() async {
  // ... existing initialization ...

  // MyService (optional)
  if (cfg.hasMyServiceConfig) {
    final myService = RealMyService(config: cfg.myServiceConfig);
    await myService.initialize();
    MyService.instance = myService;
  }
  // else: keeps NullMyService default
}

Future<void> disposeEverythingStack() async {
  // ... existing disposal ...

  MyService.instance.dispose();
}
```

#### 5. Add tests

```dart
// test/services/my_service_test.dart

void main() {
  group('MyService interface', () {
    test('NullMyService is default instance', () {
      expect(MyService.instance, isA<NullMyService>());
    });
  });

  group('MockMyService', () {
    late MockMyService mockService;

    setUp(() {
      mockService = MockMyService();
      MyService.instance = mockService;
    });

    tearDown(() {
      MyService.instance = NullMyService();
    });

    test('initialize completes', () async {
      await mockService.initialize();
      expect(mockService.isReady, isTrue);
    });

    test('doSomething returns output', () async {
      final result = await mockService.doSomething(testInput);
      expect(result, isNotNull);
    });
  });

  group('RealMyService', () {
    // Platform integration tests (if needed)
  });
}
```

---

### Q: Are there unstated assumptions about background jobs?

**Lessons from EmbeddingQueueService implementation:**

1. **Task status must be explicitly updated**
   - Don't assume tasks auto-complete
   - Mark `completed` after ALL work (including DB writes)

2. **Batch processing needs completion logic**
   - Individual processing had it
   - Batch processing forgot it
   - Always update task status in BOTH paths

3. **Test with actual pending count checks**
   - Don't just test "it doesn't throw"
   - Verify queue empties (`pending == 0`)

4. **Use defensive timeouts even for internal operations**
   - `flush()` had 100-iteration circuit breaker
   - Prevents infinite loops in production

5. **Touch parameter for background updates**
   - Background jobs shouldn't update `updatedAt`
   - Requires `{bool touch = false}` option

6. **Persistent queue survives crashes**
   - ObjectBox entity for queue
   - Not in-memory

7. **Entity might be deleted while in queue**
   - Check `findByUuid()` returns non-null
   - Mark as completed (not failed) if deleted

---

## Summary of Gaps

**What needs fixing before production:**

### Critical
1. ✗ **Timeout wrappers** on all network calls
2. ✗ **VersionableHandler** doesn't work on ObjectBox
3. ✗ **No retry logic** for transient failures
4. ✗ **No circuit breakers** for external APIs

### Important
5. ✗ **Test failures** in semantic indexing (removed handler, tests still expect it)
6. ✗ **Structured logging** (replace `print` statements)
7. ✗ **Result types** for network services (if preferred over exceptions)

### Nice-to-Have
8. ✗ **Health checks** endpoint for service status
9. ✗ **Metrics/monitoring** for error rates
10. ✗ **Service hot-swap safety** (prevent in-flight stream breakage)

**Next priorities:**
1. Fix semantic indexing tests (remove or update them)
2. Add timeout wrappers to network services
3. Implement VersionQueueService (async versioning)
4. Add retry logic with exponential backoff

---

## Related Documentation

- **Service patterns:** `docs/SERVICE_PATTERNS.md`
- **Testing approach:** `docs/testing/TESTING_APPROACH.md`
- **Bootstrap initialization:** `lib/bootstrap.dart`
- **Adding new entities:** `docs/templates/ARCHITECTURE_TEMPLATE.md`
