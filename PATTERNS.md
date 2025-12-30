# Development Patterns

How to build with Everything Stack. Code examples, patterns, anti-patterns, and walkthroughs.

See ARCHITECTURE.md for the entity model and system design.
See TESTING.md for E2E testing approach.

---

## Adding a Feature: The 8-Step Pattern

Every new feature follows this pattern:

```
1. Define domain entities        lib/domain/{entity_name}.dart
2. Add repository interfaces     lib/data/repositories/{entity_name}_repository.dart
3. Add to bootstrap              lib/services/service_locator.dart
4. Write E2E test                integration_test/{platform}_{feature}_e2e_test.dart
5. Implement feature logic       lib/features/{feature}/ (adapters + services)
6. Test all platforms            flutter test integration_test/ -d {platform}
7. Run E2E end-to-end            flutter test integration_test/ --watch
8. Commit                        git add . && git commit
```

**Don't skip step 4.** E2E test first captures requirements before you write code.

### Example: Adding Speaker Recognition Feature

**Step 1: Domain Entity**
```dart
// lib/domain/speaker_profile.dart
class SpeakerProfile extends BaseEntity {
  final String userId;
  final String name;
  final List<double>? voiceEmbedding;  // Semantic search
  final DateTime createdAt;

  SpeakerProfile({
    required this.userId,
    required this.name,
    this.voiceEmbedding,
    required this.createdAt,
  });
}
```

**Step 2: Repository Interface**
```dart
// lib/data/repositories/speaker_profile_repository.dart
abstract class SpeakerProfileRepository extends EntityRepository<SpeakerProfile> {
  Future<SpeakerProfile?> findByUserId(String userId);
  Future<List<SpeakerProfile>> findAll();
  Future<SpeakerProfile> save(SpeakerProfile profile);
  Future<bool> delete(String profileId);
}
```

**Step 3: Bootstrap**
```dart
// lib/services/service_locator.dart
void setupRepositories() {
  if (kIsWeb) {
    GetIt.I.registerSingleton<SpeakerProfileRepository>(
      SpeakerProfileIndexedDBAdapter(),
    );
  } else {
    GetIt.I.registerSingleton<SpeakerProfileRepository>(
      SpeakerProfileObjectBoxAdapter(store),
    );
  }
}
```

**Step 4: E2E Test FIRST**
```dart
// integration_test/android_speaker_recognition_e2e_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Speaker recognition end-to-end flow', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // User creates profile
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.tap(find.text('Record'));
    await Future.delayed(Duration(seconds: 3));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    // Profile appears in UI
    expect(find.text('Alice'), findsOneWidget);

    // Profile persisted (check database)
    final repo = GetIt.I<SpeakerProfileRepository>();
    final profiles = await repo.findAll();
    expect(profiles.first.name, 'Alice');

    // User speaks: system recognizes
    await tester.tap(find.byIcon(Icons.mic));
    await Future.delayed(Duration(seconds: 2));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    // Recognition result visible in UI
    expect(find.text('Recognized: Alice'), findsOneWidget);

    // Real Invocation log created (system learned something)
    final invocations = await invocationRepository.findAll();
    expect(invocations, isNotEmpty);
    expect(invocations.last.componentName, 'SpeakerMatcher');

    // User rates recognition (feedback)
    await tester.tap(find.byIcon(Icons.thumb_up));
    await tester.pumpAndSettle();

    // Feedback stored in Invocation
    final inv = await invocationRepository.findById(invocations.last.id);
    expect(inv.feedback, isNotNull);
  });
}
```

**Steps 5-8: Implement Until Test Passes**

---

## Service Architecture Pattern

Services are global singletons. They handle cross-cutting concerns: database access, API calls, crypto, etc.

### Service Definition
```dart
// lib/services/embedding_service.dart
abstract class EmbeddingService {
  Future<List<double>> embed(String text);
}

// Implement the service directly (no Impl suffix)
class EmbeddingService implements EmbeddingService {
  final _jinaClient = JinaClient();

  @override
  Future<List<double>> embed(String text) async {
    final response = await _jinaClient.embed(text);
    return response.embedding;
  }
}
```

### Registration
```dart
// lib/services/service_locator.dart
GetIt.I.registerSingleton<EmbeddingService>(
  EmbeddingService(),
);
```

### Usage Anywhere
```dart
final service = GetIt.I<EmbeddingService>();
final embedding = await service.embed('hello world');
```

### Testing with Real or Mock
```dart
// E2E: Use real service
GetIt.I.registerSingleton<EmbeddingService>(EmbeddingService());

// Special case: Use mock
GetIt.I.registerSingleton<EmbeddingService>(MockEmbeddingService());
```

---

## Trainable Component Pattern

Components that learn from feedback use the Trainable mixin.

### Pattern
```dart
class SpeakerMatcher with TrainableComponentMixin {
  @override
  Future<InvocationResult> execute(
    String input, {
    required AdaptationState adaptation,
  }) async {
    // Use adaptation state to make decisions
    final strategy = adaptation?.strategy ?? 'conservative';

    // Execute
    final result = strategy == 'aggressive'
      ? await _aggressiveMatch(input)
      : await _conservativeMatch(input);

    // TrainableComponentMixin logs automatically via Invocation
    return InvocationResult(
      output: result,
      metadata: {'strategy': strategy, 'confidence': 0.92},
    );
  }

  Future<void> trainFromFeedback(String correlationId) async {
    // Called when user provides feedback on this component
    final invocations = await invocationRepo.findByCorrelationId(correlationId);
    final feedback = await feedbackRepo.findByComponent('SpeakerMatcher');

    // Update AdaptationState based on feedback
    final adaptation = await adaptationStateRepo.findByScope(AdaptationScope.user);
    adaptation.adaptations['SpeakerMatcher.strategy'] = learnedStrategy;
    await adaptationStateRepo.save(adaptation);
  }
}
```

### Result
- Execution logged to Invocation
- User provides feedback
- Feedback trains AdaptationState
- Next execution uses learned state

---

## Exception Handling Pattern

Platform-agnostic exception hierarchy.

### Define Custom Exceptions
```dart
// lib/core/exceptions.dart
abstract class CustomException implements Exception {
  String get message;
  String get code;
}

class ServiceException extends CustomException {
  @override
  final String code;

  @override
  final String message;

  ServiceException({required this.code, required this.message});

  @override
  String toString() => '$code: $message';
}

class ValidationException extends CustomException {
  @override
  final String code = 'VALIDATION_ERROR';

  @override
  final String message;

  ValidationException(this.message);
}
```

### Usage: find() vs get()

**find()** - Returns null on not found
```dart
Future<MyEntity?> findById(String id) async {
  try {
    return await repository.findByUuid(id);
  } on CustomException {
    return null;  // Graceful
  }
}
```

**get()** - Throws on not found
```dart
Future<MyEntity> getById(String id) async {
  try {
    final entity = await repository.findByUuid(id);
    if (entity == null) {
      throw ServiceException(
        code: 'NOT_FOUND',
        message: 'Entity $id not found',
      );
    }
    return entity;
  } on CustomException catch (e) {
    throw ServiceException(code: e.code, message: e.message);
  }
}
```

---

## Transaction Pattern (ACID)

Atomic multi-entity changes. Same code works on both ObjectBox and IndexedDB.

### Native (ObjectBox)
```dart
// Synchronous transaction, atomic
db.runInTransaction(() {
  userRepo.save(user);
  eventRepo.save(event);
  // Both succeed or both rollback
});
```

### Web (IndexedDB)
```dart
// Async transaction, atomic
await db.runInTransaction(() async {
  await userRepo.save(user);
  await eventRepo.save(event);
  // Both succeed or both rollback
});
```

### Abstraction (Same Code Everywhere)
```dart
// Works on both ObjectBox (sync) and IndexedDB (async)
await repository.runTransaction(() async {
  await userRepository.save(user);
  await eventRepository.saveAll(events);
  // All succeed or all rollback
});
```

---

## Execution Fungibility: Service Implementations

Services can have multiple implementations. The system chooses which one to use based on what works.

### Service Interface
```dart
// What the service does (platform-agnostic)
abstract class EmbeddingService {
  Future<List<double>> embed(String text);
}
```

### Jina Implementation
```dart
// Server-side embeddings via Jina API
class JinaEmbedding implements EmbeddingService {
  final _jinaClient = JinaClient();

  @override
  Future<List<double>> embed(String text) async {
    return _jinaClient.embed(text);  // Powerful, slower
  }
}
```

### Local Implementation
```dart
// On-device embeddings for a specific model
class LocalEmbedding implements EmbeddingService {
  final _model = loadOnDeviceModel();

  @override
  Future<List<double>> embed(String text) async {
    return _model.predict(text);  // Fast, private
  }
}
```

### Implementation Selection (Trainable)
```dart
// Choose based on learned behavior
class EmbeddingService {
  static EmbeddingService selectImplementation({
    required AdaptationState? adaptation,
  }) {
    // If user feedback showed Jina was more accurate → use Jina
    // If local was faster enough → use local
    // Otherwise heuristic (network, device CPU, privacy preference)

    if (adaptation?.preferredImplementation == 'jina') {
      return JinaEmbedding();
    }
    return LocalEmbedding();
  }
}

// User feedback trains the choice
feedback: 'Found exactly what I was looking for'
→ System learns which implementation led to better results
→ Next execution uses learned choice
```

---

## Semantic Search Pattern

Vector embeddings for similarity search. The Embeddable mixin requires entities to define how they generate their embeddings.

### Entity with Embeddable
```dart
// lib/domain/turn.dart
class Turn extends BaseEntity with Embeddable {
  final String conversationId;
  final String userMessage;
  final String systemResponse;
  final List<double>? embedding;

  Turn({
    required this.conversationId,
    required this.userMessage,
    required this.systemResponse,
    this.embedding,
  });

  // Embeddable requires: how to generate embedding from this entity
  @override
  Future<List<double>> generateEmbedding(EmbeddingService embedder) async {
    // Combine relevant fields into searchable text
    final text = '$userMessage $systemResponse';
    return await embedder.embed(text);
  }
}
```

### Save with Automatic Embedding
```dart
// When entity is saved
final turn = Turn(
  conversationId: 'conv-123',
  userMessage: 'How do I fix a leak?',
  systemResponse: 'Here are steps...',
);

await turnRepository.save(turn);
// → Framework detects Embeddable mixin
// → Calls turn.generateEmbedding(embeddingService)
// → Stores embedding alongside turn
```

### Search by Similarity
```dart
// User searches for similar conversations
final query = "water damage repair";
final queryEmbedding = await embeddingService.embed(query);

// Find semantically similar turns
final results = await turnRepository.semanticSearch(
  queryEmbedding,
  limit: 10,
  minSimilarity: 0.7,  // 70% threshold
);

// Results ranked by semantic similarity to "water damage repair"
// Not keyword match - actual meaning similarity
```

---

## Common Gotchas

### 1. ORM Decorators in Domain (❌ Don't)
```dart
// ❌ WRONG - breaks web compilation
@Entity()
class MyEntity extends BaseEntity {
  @Id()
  int id;
}

// ✅ CORRECT - decorators in adapter only
class MyEntity extends BaseEntity {
  final String uuid;
}

// ObjectBox adapter has decorators
@Entity()
class MyEntityOB {
  @Id()
  int id;
}
```

### 2. Forgetting to Reset Services in Tests
```dart
// Services are global singletons
// Must reset between tests
setUp(() {
  GetIt.I.reset();
  // Re-register (real for E2E, mock for unit)
  GetIt.I.registerSingleton<MyService>(MockMyService());
});
```

### 3. Service Registration Before Access
```dart
// ❌ WRONG - accessing before registered
final service = GetIt.I<MyService>();  // Crashes if not registered

// ✅ CORRECT - register in bootstrap
GetIt.I.registerSingleton<MyService>(MyService());

// Then access anywhere
final service = GetIt.I<MyService>();
```

---

## Reference

See ARCHITECTURE.md for the entity model (Event, Invocation, Turn, Feedback, AdaptationState).
See TESTING.md for E2E testing approach and platform setup.
See DECISIONS.md for why we chose these patterns.

---

**Last Updated**: December 26, 2025
