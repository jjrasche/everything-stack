# ASD Workflow

## Phase 1: Foundation

Foundation is discovery. Done conversationally, ideally in Claude AI (chat interface) rather than Claude Code. The goal is divergent exploration before convergent execution.

### Vision Discovery

Work through `docs/templates/VISION_TEMPLATE.md` with Claude. This is a conversation, not a form. Explore:

- What problem exists?
- Who feels this pain?
- What does success look like?
- What are we NOT building?

Output: `VISION.md` - living document, referenced by all future work.

### Architecture Discovery

Work through `docs/templates/ARCHITECTURE_TEMPLATE.md` with Claude. Given the vision, explore:

- Which patterns from Everything Stack apply?
- What entities exist in this domain?
- What are the integration points?
- What scale do we anticipate?

Output: `ARCHITECTURE.md` - technical boundaries, referenced before implementation.

### Feasibility Validation

Before committing to build, validate:

- Can the stack support the vision?
- Are there technical unknowns that need spikes?
- Is the scope realistic?

This may surface architecture changes. Iterate until confident.

## Phase 2: Roadmap

Convert vision into sequenced work. Each roadmap item is a feature that can be:

- Described as BDD scenario
- Implemented independently
- Validated in isolation
- Deployed incrementally

Output: `ROADMAP.md` - ordered list of features with brief descriptions.

## Phase 3: Build Loop

For each roadmap item, repeat:

### 3.1 Write Scenario

Human writes Gherkin scenario describing desired behavior. Focus on WHAT happens, not HOW.

```gherkin
Feature: Tool borrowing
  Scenario: Successful borrow request
    Given a tool "Circular Saw" is available
    And user "Jim" is verified
    When Jim requests to borrow "Circular Saw"
    Then the tool status changes to "pending"
    And the owner receives a notification
```

### 3.2 AI Writes Test

AI reads scenario, proposes parameterized test implementation. Human approves test plan before AI implements.

### 3.3 AI Implements

AI writes code until tests pass. No human intervention on implementation details. CI validates cross-platform.

### 3.4 Human Validates

Human reviews deployed behavior. Does it match intent? If yes, merge. If no, refine scenario and loop.

## Phase Transitions

**Foundation → Roadmap:** When Vision and Architecture feel stable. You can always return to refine.

**Roadmap → Build:** When at least one feature is clear enough for a scenario.

**Build → Ship:** When tests pass and behavior validated. Continuous - each feature ships independently.

## Divergent vs Convergent

Foundation phase is divergent. Explore possibilities, question assumptions, consider alternatives. Claude AI excels here - conversational, exploratory.

Build phase is convergent. Execute against defined contracts. Claude Code excels here - precise, iterative, test-driven.

Don't rush foundation to get to building. The quality of foundation determines quality of everything after.

## Infrastructure vs Features

**Features** (user-facing): BDD scenarios in Gherkin, E2E tests

**Infrastructure** (internal services): Unit test specifications first
- Write test file describing expected behavior
- Each public method gets test cases for: happy path, edge cases, error cases
- Tests document the contract
- Implementation satisfies tests