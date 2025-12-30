# Testing

## Philosophy

Tests are truth. A feature is done when E2E tests pass and real execution produces the right Invocation logs.

No mocks. No abstraction layers between test and reality. What you test is what ships.

This aligns with the learning architecture (see ARCHITECTURE.md): the system learns from real execution feedback. E2E tests generate real Invocation logs that feed the training loop. Unit test mocks generate fake logs that teach the system nothing.

See `.claude/CLAUDE.md` for how testing gates the ASD workflow (contract-first, AI-built, universal).

---

## What is E2E Testing?

**E2E (End-to-End):** User action → System processes → Result visible to user

- No mocks
- No test doubles
- Real components, real services
- Real persistence layer (ObjectBox on native, IndexedDB on web)
- Real API calls (Groq, Deepgram, Jina)

**Result:** You test what you ship. Every test produces a real Invocation log that the system learns from.

---

## When to Write E2E Tests

Write E2E tests for:
- ✅ Every user-facing feature (message, rating, action)
- ✅ Every end result (entity created, updated, deleted)
- ✅ Every adaptation loop (user feedback → system learns)
- ✅ Every platform (iOS, Android, Web, macOS, Windows, Linux)

Don't write tests for:
- ❌ Internal service contracts (if it's internal, E2E will catch the break)
- ❌ Algorithm correctness in isolation (E2E reveals what matters)
- ❌ Mock behavior (mocks aren't shipped)

---

## Structure: E2E Test Template

**File:** `integration_test/{platform}_{feature}_e2e_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('E2E: Speaker Recognition', () {
    testWidgets('User creates speaker profile and app recognizes them', (tester) async {
      // Setup: Launch app
      app.main();
      await tester.pumpAndSettle();

      // User creates profile
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.tap(find.text('Record'));
      // Simulate 5-second voice recording
      await Future.delayed(Duration(seconds: 5));
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Verify profile created
      expect(find.text('Alice'), findsOneWidget);

      // User speaks: system should recognize them
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();
      // Simulate 3-second voice input
      await Future.delayed(Duration(seconds: 3));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Verify recognition
      expect(find.text('Recognized: Alice'), findsOneWidget);

      // Check Invocation logs (real execution)
      final invocations = await invocationRepository.findAll();
      expect(invocations, isNotEmpty);

      // Invocation should have real data (not mocks)
      final speakerMatchInvocation = invocations.firstWhere(
        (inv) => inv.componentName == 'SpeakerMatcher',
      );
      expect(speakerMatchInvocation.output, contains('confidence'));
      expect(speakerMatchInvocation.feedback, isNull); // Not yet rated
    });

    testWidgets('User rates recognition as correct (feedback → adaptation)', (tester) async {
      // Previous test created profile and recognized speaker
      // Now user rates the result

      await tester.tap(find.byIcon(Icons.thumb_up)); // Correct recognition
      await tester.pumpAndSettle();

      // Verify feedback logged
      final invocations = await invocationRepository.findAll();
      final ratedInvocation = invocations.lastWhere(
        (inv) => inv.componentName == 'SpeakerMatcher',
      );
      expect(ratedInvocation.feedback, equals(InvocationFeedback.correct));

      // Verify AdaptationState updated (next time will use this feedback)
      final adaptation = await adaptationStateRepository.findByUser(userId);
      expect(adaptation.adaptations, contains('SpeakerMatcher'));
      expect(adaptation.adaptations['SpeakerMatcher'].confidence, greaterThan(0.5));
    });
  });
}
```

---

## Running E2E Tests

**All platforms (CI):**
```bash
# Android emulator
flutter test integration_test/ -d android

# iOS simulator
flutter test integration_test/ -d ios

# Web (Chrome)
flutter test integration_test/ -d chrome

# macOS desktop
flutter test integration_test/ -d macos

# Windows desktop
flutter test integration_test/ -d windows

# Linux desktop
flutter test integration_test/ -d linux
```

**Local development (fastest):**
```bash
# Web - fastest feedback loop
flutter test integration_test/ -d chrome --watch

# Or native platform you're targeting
flutter test integration_test/ -d android --watch
```

**Headed (see browser/app during test):**
```bash
flutter test integration_test/ -d chrome --headed
```

---

## Smoke Tests (Pre-Release Validation)

Smoke tests validate **real API integrations** before release. Same test logic as E2E tests, but with real services instead of mocks.

**Why both?**
- **E2E tests (CI):** Mocked, fast (~1s), catch regressions
- **Smoke tests (manual):** Real APIs, slower (~3-5s), catch production issues

**Running:**
```bash
flutter test test/smoke/
```

**Requirements:**
- `.env` file with valid `GROQ_API_KEY` and `DEEPGRAM_API_KEY`
- Network connection

**Test validates:**
- API integrations work (Groq, Deepgram)
- Real latency acceptable
- Invocation logging with real data

Smoke tests and E2E tests share identical test logic (via `test/support/audio_pipeline_test_shared.dart`). Only service registration differs. Zero duplication.

---

## How Tests Generate Learning Data

Every E2E test creates real Invocations:

1. **Service executes** (e.g., SpeakerMatcher.identify())
2. **Invocation logged** (component, input, output, executionContext, latency)
3. **User provides feedback** (in test, we simulate: `tester.tap(Icons.thumb_up)`)
4. **Feedback stored** in Invocation.feedback
5. **AdaptationState updated** from feedback
6. **Next execution uses updated AdaptationState** (system learns)

This is the only kind of learning signal that matters. Unit test mocks create fake logs. E2E tests create real ones.

---

## Writing Tests for Each Component Type

### Service Tests
Test the service is callable and produces output:

```dart
testWidgets('EmbeddingService embeds text', (tester) async {
  app.main();
  await tester.pumpAndSettle();

  // Trigger embedding (user action that calls service)
  await tester.enterText(find.byType(TextField), 'hello world');
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();

  // Verify result visible
  expect(find.text('Results: 5 matches'), findsOneWidget);

  // Verify Invocation logged (real execution)
  final invocations = await invocationRepository.findByComponent('EmbeddingService');
  expect(invocations, isNotEmpty);
  expect(invocations.last.output, contains('embedding'));
});
```

### Repository Tests
Test persistence works end-to-end:

```dart
testWidgets('Save and load entity across app restart', (tester) async {
  app.main();
  await tester.pumpAndSettle();

  // Create entity via UI
  await tester.tap(find.byIcon(Icons.add));
  await tester.enterText(find.byType(TextField), 'Test Note');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();

  // Verify saved
  expect(find.text('Test Note'), findsOneWidget);

  // Restart app (simulates device restart)
  await binding.window.physicalSizeTestValue = Size(800, 600);
  addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

  // Data should persist
  expect(find.text('Test Note'), findsOneWidget);
});
```

### Adaptation Tests
Test feedback updates learned behavior:

```dart
testWidgets('System learns from feedback', (tester) async {
  app.main();
  await tester.pumpAndSettle();

  // First execution: system makes a choice (e.g., local vs remote)
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();

  var invocations = await invocationRepository.findAll();
  var firstInvocation = invocations.last;
  expect(firstInvocation.executionContext, isNotEmpty);

  // User rates it (feedback)
  await tester.tap(find.byIcon(Icons.thumb_up));
  await tester.pumpAndSettle();

  // Verify feedback stored
  invocations = await invocationRepository.findAll();
  expect(invocations.last.feedback, equals(InvocationFeedback.correct));

  // Verify AdaptationState learned
  final adaptation = await adaptationStateRepository.findByScope(AdaptationScope.user);
  expect(adaptation.adaptations, isNotEmpty);
});
```

---

## Performance Baselines

Expected latencies for E2E tests (from ARCHITECTURE.md):

| Operation | Expected | Platform |
|-----------|----------|----------|
| Entity save & persist | 20-50ms | ObjectBox (native) / IndexedDB (web) |
| Semantic search (100 docs) | 50-200ms | Local |
| Speaker recognition | 500-2000ms | Local (audio processing) |
| LLM inference | 200-800ms | Remote (Groq API) |
| Full conversation turn | <3 seconds | End-to-end |

If test latencies exceed these, investigate:
- Is a service blocking unexpectedly?
- Should this execute remote instead of local?
- Is the plugin selection wrong?

Reference ARCHITECTURE.md "Execution Fungibility" for how plugin choice affects latency.

---

## Platform-Specific Notes

### Android & iOS
- Tests run on emulator/simulator (not real device)
- File system access via FileService
- Audio input simulated (no real microphone)
- Platform-specific plugins tested here

### Web (Chrome)
- IndexedDB persistence instead of ObjectBox
- No file system (use BlobStore)
- Same API as native
- Fastest feedback loop for development

### Desktop (macOS, Windows, Linux)
- Native file system
- ObjectBox persistence
- Useful for testing drag-drop, local file workflows

### All Platforms
- Use real APIs (Groq, Deepgram, Jina) - don't mock them
- If API fails, test fails (catches real issues)
- Test data persists across test runs; clean up explicitly

---

## Debugging a Failing E2E Test

### Test hangs
- Check `finder.evaluate()` - element might not exist yet
- Increase wait: `await tester.pumpAndSettle(timeout: Duration(seconds: 10))`
- Use `--headed` to see what's on screen

### Assertion fails
- Print screen: `expect(find.byType(Scaffold), findsOneWidget)` (will show tree)
- Check Invocation logs: `print(await invocationRepository.findAll())`
- Verify database state: `print(await entityRepository.findAll())`

### Service doesn't run
- Verify UI triggers the action: `await tester.tap(find.byIcon(Icons.mic))`
- Check service is wired: See PATTERNS.md "Service Architecture"
- Verify API keys are set (see `.claude/CLAUDE.md` "Build and Run")

### Feedback not stored
- Check `InvocationRepository.findByComponent()` finds it
- Verify feedback is passed: `invocation.feedback != null`
- Check AdaptationState updated: `adaptationStateRepository.findByScope()`

---

## CI Integration

All tests run on GitHub Actions for every commit:

```yaml
test:
  strategy:
    matrix:
      platform: [android, ios, chrome, macos, windows, linux]
  steps:
    - run: flutter test integration_test/ -d ${{ matrix.platform }}
```

Test failures block merge. No exceptions.

---

## When E2E Tests Are Done

A feature is done when:
- ✅ E2E test written (given/when/then user interaction)
- ✅ Test passes on all 6 platforms
- ✅ Invocation logs show real execution
- ✅ Feedback collection works (user can rate)
- ✅ AdaptationState updates from feedback
- ✅ Manual review confirms behavior matches intent (see `.claude/CLAUDE.md` ASD Workflow, "Verification" phase)

Then commit. No further testing needed.

---

## Why E2E Only?

**Traditional testing pyramid (unit → integration → E2E):**
- Catches bugs early
- Fast feedback loop
- Clear separation of concerns
- **Cost:** Mock/reality gap grows; mocks teach system wrong patterns

**Everything Stack E2E-only:**
- No mock/reality gap
- Real Invocation logs for real learning
- System learns from what it actually does
- Slower to fail during development (but closer to what users see)
- **Benefit:** Feedback is true signal, not noise

Since your system *learns* from execution, you want it learning from real execution, not mocked execution.

---

## References

- **ARCHITECTURE.md** - How Invocations are logged, how AdaptationState learns, execution fungibility
- **PATTERNS.md** - Service architecture, testing with mocks (if you need them), plugin pattern
- **.claude/CLAUDE.md** - ASD Workflow, verification gates, permissions for test automation
- **README.md** - Quick start, build commands, environment variables

See those for complete context.
