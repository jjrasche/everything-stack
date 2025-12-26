# Integration Tests - Full App with Real UI and Persistence

Tests the **complete infrastructure end-to-end**: Real UI interactions via WidgetTester, real persistence, mocked external services (STT, LLM, TTS).

## Structure

```
integration_test/
├── app_test.dart      # Infrastructure tests (audio pipeline, tool executor, feedback)
└── README.md          # This file
```

## Test Coverage

**Test 1: Full Audio Pipeline**
- User provides text input (simulating STT)
- Coordinator orchestrates: namespace selection → tool selection → context → LLM call
- Mocked LLM returns conversational response (no tools)
- Invocations persisted in repository
- TTS service called with response
- Verifies: success, response text, invocations recorded

**Test 2: Embedding Service**
- Tests semantic embedding generation
- Verifies correct dimensions returned

**Test 3: Invocation Persistence**
- Verifies invocations stored in repository
- Can find invocations by correlation ID
- Runs multiple times to verify persistence grows

**Test 4: Error Handling**
- Simulates failing LLM service
- Verifies graceful error handling
- Restores working service for next test

## Run Tests

```bash
# Run on Windows desktop
flutter test integration_test/app_test.dart -d windows

# Run on Android emulator
flutter test integration_test/app_test.dart -d <emulator-id>

# Run on iOS simulator
flutter test integration_test/app_test.dart -d <simulator-id>

# Run on specific device
flutter test integration_test/app_test.dart -d <device-id>
```

## Using WidgetTester

The tests use `WidgetTester` to interact with the real Flutter app:

```dart
testWidgets('Test name', (WidgetTester tester) async {
  // 1. Build the app
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();  // Wait for animations

  // 2. Find widgets
  expect(find.byType(VoiceAssistantScreen), findsOneWidget);

  // 3. Interact with widgets
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();

  // 4. Verify UI state
  expect(find.byText('Response text'), findsOneWidget);
});
```

## Key WidgetTester Methods

- `tester.pumpWidget(widget)` - Build widget tree
- `tester.pumpAndSettle()` - Wait for animations/async
- `tester.pump()` - Single frame update
- `find.byType(Type)` - Find by widget type
- `find.byKey(Key)` - Find by key
- `find.byText('text')` - Find by text
- `tester.tap(finder)` - Simulate tap
- `tester.enterText(finder, 'text')` - Enter text
- `tester.drag(finder, offset)` - Drag widget
- `tester.longPress(finder)` - Long press

## Mocking Services

The tests mock external services:

```dart
class MockLLMService extends Mock implements LLMService {
  @override
  Future<LLMResponse> chatWithTools({...}) async {
    return LLMResponse(
      content: 'Conversational response',
      toolCalls: [],
    );
  }
}

class MockTTSService extends Mock implements TTSService {
  @override
  Stream<void> synthesize(String text) async* {
    print('TTS: $text');
    yield null;
  }
}
```

Then register before tests:

```dart
setUpAll(() async {
  final getIt = GetIt.instance;
  getIt.registerSingleton<LLMService>(mockLLMService);
  getIt.registerSingleton<TTSService>(mockTTSService);
});
```

## Verifying Service Calls

Use Mockito's `verify()` to check services were called:

```dart
// Verify LLM was called
verify(mockLLMService.chatWithTools(
  model: anyNamed('model'),
  messages: anyNamed('messages'),
  tools: anyNamed('tools'),
  temperature: anyNamed('temperature'),
)).called(greaterThan(0));

// Verify TTS was called
expect(mockTTSService.spokenTexts, isNotEmpty);
expect(mockTTSService.spokenTexts.first, equals('Response text'));
```

## Verifying Persistence

Get repository from GetIt and query:

```dart
final invocationRepo = getIt<InvocationRepository<Invocation>>();

// Verify invocations persisted
final allInvocations = await invocationRepo.findAll();
expect(allInvocations, isNotEmpty);

// Find by correlation ID
final byId = await invocationRepo.findByCorrelationId(correlationId);
expect(byId, isNotEmpty);
```

## Full Example Test

```dart
testWidgets('Audio pipeline test', (WidgetTester tester) async {
  // Setup
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();

  // Get services
  final coordinator = getIt<Coordinator>();
  final invocationRepo = getIt<InvocationRepository<Invocation>>();

  // Run coordinator (simulates user input)
  final result = await coordinator.orchestrate(
    correlationId: 'test-${DateTime.now().millisecondsSinceEpoch}',
    utterance: 'What is the weather?',
    availableNamespaces: ['general'],
    toolsByNamespace: {'general': []},
  );

  // Verify success
  expect(result.success, isTrue);
  expect(result.finalResponse, isNotEmpty);

  // Verify LLM was called
  verify(mockLLMService.chatWithTools(...)).called(greaterThan(0));

  // Verify TTS was called
  expect(mockTTSService.spokenTexts, isNotEmpty);

  // Verify persistence
  final invocations = await invocationRepo.findAll();
  expect(invocations, isNotEmpty);
});
```

## CI Integration

Tests run automatically on all platforms:
- Android (emulator)
- iOS (simulator)
- Web (Chrome)
- Desktop (Windows, macOS, Linux)

All platforms must pass before merge.

## Debugging

**Test fails: "Widget not found"**
```dart
// Check what widgets exist
print(find.byType(TextField).evaluate());
```

**Test hangs: Animations not complete**
```dart
// Use pumpAndSettle() instead of pump()
await tester.pumpAndSettle();
```

**Service not called**
```dart
// Verify mock was registered
expect(getIt.isRegistered<LLMService>(), isTrue);
```

**Persistence empty**
```dart
// Check repository is registered
final repo = getIt<InvocationRepository<Invocation>>();
expect(repo, isNotNull);
```

## Next Steps

Add tests for:
- Task creation through UI (text input → tool execution)
- Task list filtering
- Feedback mechanism (user provides feedback)
- Trainable aspects (adaptation state changes)
- Error scenarios (invalid input, network failures)
