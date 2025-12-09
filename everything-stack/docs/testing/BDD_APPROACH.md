# BDD Testing Approach

## Philosophy

BDD scenarios are contracts. They define what the software does in human-readable terms. Tests implement those contracts. Code satisfies tests.

The scenario is the source of truth. If behavior doesn't match scenario, either the code is wrong or the scenario needs updating.

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
