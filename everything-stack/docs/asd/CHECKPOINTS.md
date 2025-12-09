# ASD Checkpoints

Checkpoints are moments where AI pauses for human input. They prevent runaway implementation and maintain governance.

## Mandatory Checkpoints

### Before Implementation Starts

**STOP after scenario written.** AI proposes test plan, waits for approval. This catches misunderstanding before code exists.

Human verifies: Does this test plan actually validate the scenario? Are edge cases covered? Is the scope right?

### After Tests Pass

**STOP after CI green.** AI has implemented and tests pass. Human validates deployed behavior.

Human verifies: Does the actual behavior match my intent? Is the UX right? Any surprises?

### Before Architecture Changes

**STOP before modifying patterns.** If implementation seems to require changes to `lib/core/` or `lib/patterns/`, pause.

Human decides: Is this a gap in the template? A misunderstanding of the feature? A scope creep?

### Before New Dependencies

**STOP before adding to pubspec.yaml.** AI proposes dependency, explains why needed, lists alternatives considered.

Human decides: Is this necessary? Is it maintained? Does it align with stack philosophy?

## Optional Checkpoints

### Complex Logic

For features involving complex business rules, AI can checkpoint mid-implementation to verify understanding.

### Multi-Step Features

For features requiring multiple scenarios, AI can checkpoint after each scenario to confirm direction.

### Uncertainty

If AI is uncertain about approach, it should checkpoint rather than guess. Better to ask than to build wrong.

## Checkpoint Format

When AI reaches a checkpoint:

1. State what was completed
2. State what comes next
3. Ask specific question requiring human input
4. Wait for response before proceeding

Bad: "I've made some progress, let me know what you think."

Good: "Scenario implemented, tests passing. Before I move to the next roadmap item, please verify the borrow flow in the deployed preview matches your intent. Specifically: does the notification timing feel right?"

## Skipping Checkpoints

Checkpoints exist for governance. Skipping them trades safety for speed.

Acceptable to skip: After trust is established on a specific feature type, human may say "implement all CRUD scenarios without stopping."

Never skip: Architecture changes, new dependencies, first implementation of a new pattern.


### Before Writing Implementation

**STOP after test file created.** Tests should compile but fail. This proves:
- You understand the interface
- You've thought through edge cases
- The contract is defined

Only proceed to implementation after test file exists and fails appropriately.