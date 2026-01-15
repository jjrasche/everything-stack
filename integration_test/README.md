# Integration Tests

E2E tests with real app, real persistence, mocked external APIs.

## Structure

```
integration_test/
├── shared/          # Test harness (IntegrationTestConfig, TestContext helper)
├── *_logic.dart     # Test logic files (one per feature/domain)
└── README.md
```

## Run Tests

### CI Mode (Mocked APIs - Default)

```bash
# All tests
flutter test integration_test/shared/generic_test.dart -d windows

# Single test
flutter test integration_test/shared/generic_test.dart --dart-define=TEST=timer -d windows
```

**What's mocked**: External APIs (Groq, Deepgram, TTS)
**What's real**: Repositories (ObjectBox/IndexedDB), EventBus, Coordinator, full app infrastructure

### Smoke Mode (Real APIs)

```bash
# All tests with real APIs
flutter test integration_test/shared/generic_test.dart --dart-define=SMOKE_TEST=true -d windows
```

**Use case**: Verify real API integrations work (rate-limited, slower, requires API keys in .env)

## Pattern: Add a New Test

**1. Create `integration_test/my_feature_logic.dart`**

```dart
// Define utterances once (if multi-turn)
final _utterances = {
  'turn1': 'What is 2+2?',
};

final mathTest = IntegrationTestConfig(
  name: 'Math Question',
  repos: [InvocationRepository<Invocation>],
  utterances: _utterances,
  mockResponses: {
    'groq': {
      _utterances['turn1']!: LLMResponse(
        id: 'mock_1',
        content: 'The answer is 4',
        toolCalls: [],
        tokensUsed: 10,
      ),
    },
  },
  testLogic: (t) async {
    await t.stt('turn1');

    final invocations = await t.invocationRepo.findAll();
    final recent = invocations
        .where((i) => i.createdAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1))))
        .toList();

    expect(recent.isNotEmpty, isTrue);

    final componentTypes = recent.map((i) => i.componentType).toSet();
    expect(componentTypes.contains('llm'), isTrue);
  },
);
```

**2. Register in `generic_test.dart`**

```dart
import '../my_feature_logic.dart';

final configs = {
  'timer': timerMultiturnTest,
  'audio': audioPipelineTest,
  'semantic': invocationSemanticTest,
  'math': mathTest, // NEW
};
```

Done. Run with `--dart-define=TEST=math`.

## TestContext Helper

Syntactic sugar for common test operations:

- `t.stt('turn1')` - Publish transcription_complete event (triggers Coordinator)
- `t.timerRepo` - Get TimerRepository from GetIt
- `t.invocationRepo` - Get InvocationRepository from GetIt
- `t.eventBus` - Get EventBus from GetIt

Keeps test logic clean: just arrange/act/assert.

## Architectural Decisions

### Why IntegrationTestConfig (Data-Driven Pattern)?

**Goal**: Make tests easy to write and maintain.

**Pattern**: Separate data (config) from logic (test function). Test harness handles ALL DI/setup.

**Result**: Tests are pure data configs + clean test logic. No DI noise. Easy to add new tests (just add config + logic function).

### Why Separate Utterances Map?

**Goal**: Single source of truth for test inputs.

**Pattern**: Define utterances once at top, reference in mockResponses via `_utterances['turn1']!`.

**Result**: DRY - change utterance in one place, all references update. No string duplication.

### Why ResponseMapLLMImplementer (Pure Data Lookup)?

**Goal**: Zero conditionals in mocks.

**Pattern**: Mock is `Map<String, LLMResponse>`. Match utterance → return response. No if/else chains.

**Result**: Clean, maintainable, type-safe. Easy to add new utterances.

### Why Real Repositories (Not Mocks)?

**Goal**: Test the full stack, including persistence layer.

**Pattern**: Use REAL repositories (ObjectBox on native, IndexedDB on web). Only mock external APIs.

**Result**: Tests validate database writes, queries, indices. Catches ObjectBox/IndexedDB bugs.

### Why Optional mockResponses?

**Goal**: Flexibility - not all tests need Coordinator.

**Pattern**: Only register Coordinator when `mockResponses != null`. Tests without external mocks (e.g., audio pipeline) omit the field.

**Result**: Tests opt-in to Coordinator when needed. Simpler tests don't pay coordination overhead.

## Ethos

**1. Test the real thing**
If it runs in prod, it runs in tests. Real app, real database, real event flow. Only external APIs are mocked.

**2. No mocks for internal infrastructure**
Repositories, EventBus, Coordinator - all real. Mocks hide bugs. We want to catch them.

**3. Data over code**
Tests are data configs + small logic functions. The pattern scales without code duplication.

**4. DRY ruthlessly**
Define utterances once. Define responses once. Reference everywhere. Change in one place = change everywhere.

**5. Clean test logic**
Test logic is pure arrange/act/assert. No DI, no service registration, no setup noise. Shared infrastructure handles that.

**6. CI-first, smoke second**
Default mode uses mocks (fast, deterministic, no API keys). Smoke mode validates real APIs (slower, requires keys, run less frequently).

## What Runs Under the Hood

1. Build app → Bootstrap creates real repos (ObjectBox/IndexedDB)
2. Swap externals → Groq/TTS/Deepgram implementers replaced with mocks (repos kept real)
3. Register Coordinator (if mockResponses provided) → Wires EventBus listener
4. Run test logic → Your testLogic function executes with full infrastructure
5. Clean up → GetIt.reset()
