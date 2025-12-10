# Testing Approach

## Philosophy

Tests are contracts. They define what the software does in human-readable and machine-executable terms. Code satisfies tests.

BDD scenarios (human-readable contracts) flow down to unit tests (implementation details). All must pass before merge.

The scenario is the source of truth for user-facing behavior. The unit test is the source of truth for technical correctness.

## Four Testing Layers

All tests run in CI. All must pass before merge to main.

### Layer 1: Unit Tests (test/services/)

**Purpose:** Test service interfaces, mocks, and algorithms in isolation.

**Characteristics:**
- Run on Dart VM (no platform dependencies)
- Fast (<1 second each)
- Test contracts and expected behavior
- Mock implementations validate interface contracts
- Real implementations tested for correctness

**Examples:**
- `test/services/blob_store_test.dart` - Tests MockBlobStore, streaming, CRUD operations
- `test/services/file_service_test.dart` - Tests MockFileService, MIME detection, compression logic
- `test/services/connectivity_service_test.dart` - Tests state transitions, stream emissions

**When to write:**
- Every service needs unit tests (mock + real stubs)
- Every algorithm needs tests (distance calc, search ranking)
- Every class needs tests (FileMetadata, Position)

**Command:** `flutter test test/services/`

### Layer 2: Integration Tests (test/integration/)

**Purpose:** Test how multiple services work together on Dart VM.

**Characteristics:**
- Run on Dart VM (no platform dependencies)
- Medium speed (~100ms to seconds)
- Cross-service contracts
- Combine unit-tested components in realistic workflows
- Still use mocks (no real platform dependencies)

**Examples:**
- `test/integration/blob_store_integration_test.dart` - FileService picks file, saves to BlobStore, loads and streams
- `test/integration/hnsw_index_integration_test.dart` - EmbeddingService generates embeddings, HnswIndex stores and searches them
- `test/integration/entity_repository_integration_test.dart` - Entity saved to repository, searched via UUID index

**When to write:**
- When feature requires multiple services together
- When unit tests don't cover the interaction
- When workflow is complex enough to warrant separate test

**Command:** `flutter test test/integration/`

### Layer 3: BDD Scenarios (test/scenarios/)

**Purpose:** Test user-facing behavior in Gherkin format.

**Characteristics:**
- Run on Dart VM or actual platform (depends on feature)
- Parameterized test data
- Gherkin syntax (Given/When/Then)
- Human-readable contracts
- Only written for features with UI or user interactions

**Examples:**
- `test/scenarios/note_creation.dart` - "Given empty notebook, When user creates note, Then note appears in list"
- `test/scenarios/semantic_search.dart` - "Given notes exist, When user searches semantically, Then similar notes rank highest"
- `test/scenarios/offline_sync.dart` - "Given app offline, When user edits, Then changes persist locally and sync when online"

**When to write:**
- Only for features with user-facing behavior
- Infrastructure services don't need scenarios (already have unit tests)
- After entity is designed and repository is implemented

**Command:** `flutter test test/scenarios/`

### Layer 4: Platform Verification (integration_test/)

**Purpose:** Verify platform-specific implementations work on actual platforms.

**Characteristics:**
- Run on actual platforms (Android emulator, iOS simulator, Chrome browser, desktop)
- Integration test package (Flutter's native integration testing)
- NOT BDD (no Gherkin, no human-readable scenarios)
- Technical validation only
- Minimal - just prove the abstraction works

**Examples:**
- `integration_test/blob_store_platform_test.dart` - FileSystemBlobStore writes/reads files correctly on Android
- `integration_test/blob_store_web_test.dart` - IndexedDBBlobStore persists to IndexedDB on web
- `integration_test/location_service_test.dart` - LocationService gets GPS coordinates on Android

**When to write:**
- Only for services with platform-specific implementations
- After platform implementation is done
- Minimal tests - don't duplicate unit test coverage

**Command:**
```bash
flutter test integration_test/ -d android  # Run on Android emulator
flutter test integration_test/ -d chrome   # Run on web
flutter test integration_test/ -d macos    # Run on macOS desktop
```

## Testing Pyramid

```
    Manual QA (top)
    ↓ First-time validation only, validates tests themselves

    BDD Scenarios (Layer 3)
    ↓ User-facing behavior, parameterized test data

    Integration Tests (Layer 2)
    ↓ Cross-service workflows on Dart VM

    Unit Tests (Layer 1, bottom)
    ↓ Service interfaces, algorithms, classes

    Platform Verification (Layer 4, side)
    ↓ Platform-specific implementations on actual devices
```

Unit tests are abundant (every service). Integration tests are selective (complex workflows). Scenarios are sparse (only UI features). Platform verification is minimal (just prove it works).

## Running Tests

**All tests (CI environment):**
```bash
flutter test                    # Unit + integration (Dart VM)
flutter test integration_test/  # Platform verification (actual devices)
```

**Locally:**
```bash
flutter test test/              # Unit + integration only
flutter test test/services/     # Just services
flutter test test/integration/  # Just cross-service
flutter test test/scenarios/    # Just BDD scenarios
flutter test integration_test/ -d chrome  # Just web platform verification
```

## Scenario Structure

Use Gherkin syntax. Keep scenarios behavior-focused, not implementation-focused.

**Good - describes behavior:**
```gherkin
Scenario: Successful tool borrow
  Given a tool "Circular Saw" is available
  When user requests to borrow "Circular Saw"
  Then the borrow request is created
  And the tool owner is notified
```

**Bad - describes implementation:**
```gherkin
Scenario: Successful tool borrow
  Given tool with id "tool_123" exists in database
  When POST /api/borrow with toolId "tool_123"
  Then response status is 201
  And notification record inserted
```

## Scenario Location

Scenarios live with their tests in `test/scenarios/`. Each feature gets one file containing:

1. Gherkin scenarios as string constants
2. Parameterized test data
3. Test implementations

```dart
// test/scenarios/tool_borrowing.dart

/// Feature: Tool Borrowing
/// 
/// Scenario: Successful borrow request
///   Given a tool "Circular Saw" is available
///   And user "Jim" is verified
///   When Jim requests to borrow "Circular Saw"
///   Then the tool status changes to "pending"
///   And the owner receives a notification
const scenarioSuccessfulBorrow = '''
  Given a tool "Circular Saw" is available
  And user "Jim" is verified
  When Jim requests to borrow "Circular Saw"
  Then the tool status changes to "pending"
  And the owner receives a notification
''';

// Test data for parameterized runs
final borrowTestCases = [
  BorrowTestCase(tool: 'Circular Saw', user: 'Jim', expectedStatus: 'pending'),
  BorrowTestCase(tool: 'Drill', user: 'Alice', expectedStatus: 'pending'),
];

// Actual test implementation
void main() {
  group('Tool Borrowing', () {
    for (final testCase in borrowTestCases) {
      test('Successful borrow: ${testCase.tool} by ${testCase.user}', () async {
        // Given
        await createTool(testCase.tool, status: 'available');
        await createUser(testCase.user, verified: true);
        
        // When
        await requestBorrow(testCase.user, testCase.tool);
        
        // Then
        expect(await getToolStatus(testCase.tool), testCase.expectedStatus);
        expect(await hasNotification(toolOwner), isTrue);
      });
    }
  });
}
```

## Test Pyramid

```
    Manual QA (top)
    ↓ First-time validation only, validates tests themselves
    
    E2E/Scenario Tests (primary)
    ↓ Every BDD scenario has a test
    
    Integration Tests (secondary)
    ↓ DB/API layer, only when E2E insufficient
    
    Unit Tests (minimal)
    ↓ Complex algorithms only, E2E covers most cases
```

E2E tests are primary. They validate the contract. Unit tests are for genuinely complex logic that's hard to test through E2E.

## Testing Each Pattern

Each pattern in `lib/patterns/` has a testing approach:

**Embeddable:** Semantic similarity tests. Create entities with known content, verify similar content clusters, dissimilar content separates. Golden set or LLM-as-judge.

**Temporal:** Time-based query tests. Create entities with various timestamps, verify queries return correct time ranges.

**Ownable:** Isolation tests. Create entities owned by different users, verify users only see their own data.

**Versionable:** History tests. Modify entity multiple times, verify version history is correct and complete.

**Locatable:** Proximity tests. Create entities at known locations, verify distance queries return correct results.

**Edgeable:** Traversal tests. Create entity graph, verify edge queries return correct paths.

## CI Integration

GitHub Actions runs tests on every push. All platforms must pass.

```yaml
test:
  strategy:
    matrix:
      platform: [web, ios, android]
  steps:
    - run: flutter test
```

Test failures block merge. AI iterates until green.

## Manual QA Role

Manual QA validates tests, not features. When a feature is first implemented:

1. Review deployed behavior
2. Does it match the scenario?
3. If yes, tests are correct - they become regression suite
4. If no, tests are wrong - fix tests, re-implement

After validation, you never manually QA that scenario again. Tests catch regressions.
