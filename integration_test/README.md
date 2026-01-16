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
import 'shared/response_map_implementer.dart';
import 'mocks/mock_flutter_tts_implementer.dart';

// Define utterances once (if multi-turn)
final _utterances = {
  'turn1': 'What is 2+2?',
};

// Define mock responses
final _responses = {
  _utterances['turn1']!: LLMResponse(
    id: 'mock_1',
    content: 'The answer is 4',
    toolCalls: [],
    tokensUsed: 10,
  ),
};

final mathTest = IntegrationTestConfig(
  name: 'Math Question',
  repos: [InvocationRepository<Invocation>],
  utterances: _utterances,
  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
    'tts': MockFlutterTTSImplementer(),
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

### Why Optional mockImplementers?

**Goal**: Flexibility - not all tests need Coordinator.

**Pattern**: Only register Coordinator when `mockImplementers != null`. Tests without external mocks (e.g., audio pipeline) omit the field.

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
3. Register Coordinator (if mockImplementers provided) → Wires EventBus listener
4. Run test logic → Your testLogic function executes with full infrastructure
5. Clean up → GetIt.reset()

## Error Handling Tests

Tests verify system gracefully handles service failures and logs invocations with `success=false`.

### Pattern: Failure Simulation

Mock implementers accept `shouldFail` parameter. When true, implementer throws exception.

**Example** (from `error_handling_logic.dart`):

```dart
final llmFailureTest = IntegrationTestConfig(
  name: 'LLM Failure Handling',
  repos: [InvocationRepository<Invocation>],
  utterances: {'trigger': 'Test error handling'},
  mockImplementers: {
    'groq': MockGroqImplementer(shouldFail: true),
    'tts': MockFlutterTTSImplementer(),
  },
  testLogic: (t) async {
    try {
      await t.stt('trigger');
    } catch (e) {
      print('⚠️ Expected error caught: $e');
    }

    // Verify invocations logged
    final invocations = await t.invocationRepo.findAll();
    final recent = invocations.where((i) =>
      i.createdAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))
    ).toList();

    // Assert: ContextSelector succeeded (before LLM)
    final contextInvocations = recent.where((i) => i.componentType == 'context_selector').toList();
    expect(contextInvocations.first.success, isTrue);
  },
);
```

### Available Tests

Run individual error tests:

```bash
# LLM failure
flutter test integration_test/shared/generic_test.dart --dart-define=TEST=llm_failure -d windows

# STT failure
flutter test integration_test/shared/generic_test.dart --dart-define=TEST=stt_failure -d windows

# TTS failure
flutter test integration_test/shared/generic_test.dart --dart-define=TEST=tts_failure -d windows
```

**What's tested**:
- `llm_failure` - LLM service throws error (ContextSelector succeeds, LLM fails)
- `stt_failure` - STT service throws error (direct implementer call)
- `tts_failure` - TTS service throws error (ContextSelector + LLM succeed, TTS fails)

**Verification**: System handles errors gracefully, preceding steps log success=true, error info captured in invocation.
