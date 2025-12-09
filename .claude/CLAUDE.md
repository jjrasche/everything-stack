# CLAUDE.md

## Before Anything

Read and understand:
1. VISION.md - why this exists
2. ARCHITECTURE.md - technical constraints and infrastructure requirements

Then propose ROADMAP.md for human approval. Do not proceed until approved.

## Critical Rule

Infrastructure (CI/CD/deploy pipeline) must exist before feature development. Without it, the governance loop cannot run. The roadmap must begin with infrastructure setup.

## Workflow Per Phase

### Step 1: Check Infrastructure

Before starting any feature phase, verify:
- [ ] Git remote configured?
- [ ] CI pipeline exists and runs?
- [ ] CD pipeline exists and deploys?
- [ ] Credentials configured (.env)?

If any are missing, infrastructure phase must complete first.

### Step 2: Draft Testable Scenarios

What you draft depends on the phase type:

| Phase Type | Draft Format |
|------------|--------------|
| Infrastructure | Checklist of what must exist |
| Data Layer | Integration test descriptions |
| UI | BDD Gherkin scenarios |

Output: "Phase [name] scenarios:" followed by scenarios.

**STOP. Wait for human to reply "approved."**

### Step 3: Implement

Build until tests pass. Run tests locally.

- Infrastructure phases: Manual verification that pipelines work
- Data layer phases: `flutter test test/integration/`
- UI phases: `flutter test test/e2e/`

### Step 4: Commit

Commit to feature branch: `phase-X-description`

Output: "Tests passing. Committed to branch [name]. Commit: [hash]"

**STOP. Wait for human to verify.**

### Step 5: Human Verification

Human will verify based on phase type:
- Infrastructure phases: Trigger deploy, confirm app loads
- Data layer phases: Review CI results, confirm tests pass
- UI phases: Test on device/browser, confirm behavior matches scenarios

Only proceed after human confirms.

## Mandatory Checkpoints

Three STOPs per phase. Do not proceed without explicit human approval:

1. **After drafting scenarios** → STOP → Wait for "approved"
2. **After tests pass** → STOP → Wait for human to verify
3. **After human confirms** → Proceed to next phase

If unclear, ask. Default is STOP.

## Test Types

Match test type to what exists:

| What Exists | Test Type |
|-------------|-----------|
| Infrastructure only | Pipeline success is the test |
| Data layer (entities, repositories) | Integration tests |
| UI (screens, interactions) | E2E BDD scenarios |

Do not write E2E UI scenarios for phases without UI. Do not pretend to test what doesn't exist.

## CI/CD Pipeline (Explicit)

**Tests run remotely on GitHub Actions, not locally.** The governance loop is:

1. Push to feature branch
2. GitHub Actions runs `flutter test` on Linux runner
3. Tests must pass before merge to main
4. Merge to main triggers deployment

**Deployment targets:**
- **Web**: Firebase Hosting
- **iOS**: Firebase App Distribution (TestFlight later)
- **Android**: Firebase App Distribution (Play Store later)

The CI workflow (`.github/workflows/ci.yml`) must:
- Trigger on push/PR to any branch
- Run `flutter test`
- Report results to PR

The CD workflow (`.github/workflows/cd.yml`) must:
- Trigger on merge to main
- Build for web, iOS, Android
- Deploy to Firebase

## Code Standards

- Dart/Flutter idioms
- Single codebase, platform-specific code in thin adapters only
- All entities extend BaseEntity
- Use mixins for opt-in patterns
- Repository pattern for all data access
- Files as bytes, stream all files (not just large ones)

## Commits

- One logical change per commit
- Format: `feat|fix|refactor|test|docs|infra: description`
- Reference phase in commit body

## When Stuck

- Re-read ARCHITECTURE.md
- Ask for clarification
- Do not add dependencies without approval
- Do not change architecture without approval

## Infrastructure Dependencies

Some phases require external setup that Claude cannot do:

| Requirement | Who Does It | When Needed |
|-------------|-------------|-------------|
| GitHub repo creation | Human | Phase 0 |
| Supabase project creation | Human | Phase 0 |
| Firebase project creation | Human | Phase 0 |
| API keys in .env | Human | Phase 0 |
| App Store / Play Store setup | Human | Production |

If a phase needs something Claude cannot create, output what's needed and STOP.


## Development Order (NON-NEGOTIABLE)

For ANY new code:
1. Write test file FIRST
2. Run tests - verify they FAIL (red)
3. Write implementation
4. Run tests - verify they PASS (green)
5. Refactor if needed

If you find yourself writing implementation before tests, STOP and correct course