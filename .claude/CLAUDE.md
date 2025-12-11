# Claude Code Configuration

## Project Type
Everything Stack template - Dart/Flutter cross-platform application

## Non-Negotiable Principles

**Read these first. They override all other guidance.**

1. **ALL platforms are first-class.** Android, iOS, macOS, Windows, Linux, Web. Not "native-first with web later." If you're implementing a feature that only works on some platforms, you're not done.

2. **Infrastructure completeness over simplicity.** If asking "do we really need X?" - the answer is probably yes. Complexity is paid once in this template so applications don't pay it.

3. **Domain developers write domain logic only.** No architectural decisions. No persistence layer design. No platform-specific code outside adapters.

4. **No platform shortcuts.** "Just for Android" or "web can come later" is not acceptable. Universal or don't build it.

## Foundation Documents
- Vision: `docs/templates/VISION_TEMPLATE.md` (complete before building)
- Architecture: `docs/templates/ARCHITECTURE_TEMPLATE.md` (complete before building)
- Patterns: `lib/patterns/` (read structured comments before using)
- ASD Workflow: `docs/asd/WORKFLOW.md` (follow for all features)

## Project Initialization

When instructed to initialize this template for a new project:

1. **Delete example code:**
   - Remove `lib/example/` directory
   - Remove `test/scenarios/example_scenarios.dart`

2. **Update project identity:**
   - Update `pubspec.yaml`: name, description, version
   - Replace this README.md with project-specific content
   - Update `.github/workflows/ci.yml` if project name changed

3. **Preserve infrastructure:**
   - Keep `lib/core/`, `lib/patterns/`, `lib/services/`
   - Keep `test/harness/`
   - Keep `docs/asd/`, `docs/testing/`

4. **Create domain structure:**
   - Add entities to `lib/domain/`
   - Add scenarios to `test/scenarios/`

## Development Workflow

Follow ASD workflow for all features:

1. **Plan against foundation** - Read VISION.md and ARCHITECTURE.md before implementing
2. **Write BDD scenario** - Gherkin format in `test/scenarios/`
3. **Implement tests** - Parameterized tests using harness
4. **Implement feature** - Until tests pass
5. **Commit and push** - CI validates cross-platform

## Pattern Usage

Before using any pattern from `lib/patterns/`:
1. Read the structured comment block at top of file
2. Understand what it enables
3. Understand testing approach
4. Check integration notes

Patterns are opt-in. Add `with PatternName` to entity only if needed.

## Testing Requirements

Testing follows a 4-layer approach. All layers run in CI. All must pass before merge.

**Layer 1: Unit Tests (test/services/)**
- Service interfaces, mocks, algorithms
- Every service needs mock + real stub implementation
- Run on Dart VM

**Layer 2: Integration Tests (test/integration/)**
- Cross-service workflows
- How services work together
- Still use mocks, run on Dart VM
- Only when unit tests don't cover the interaction

**Layer 3: BDD Scenarios (test/scenarios/)**
- User-facing behavior only
- Gherkin format (Given/When/Then)
- Parameterized test data
- Only for features with UI or user interactions

**Layer 4: Platform Verification (integration_test/)**
- Platform-specific implementations on actual platforms
- Android emulator, iOS simulator, Chrome browser, desktop
- NOT BDD - technical validation only
- Minimal tests - just prove the abstraction works

**Read:** `docs/testing/TESTING_APPROACH.md` (formerly BDD_APPROACH.md) for complete guidance and examples

## Permissions

**Run without asking:**
- Read operations (file viewing, grep, find)
- Test commands (`flutter test`)
- Build commands (`flutter build`)
- Lint and format
- Git commit, push, branch, PR creation

**Ask before:**
- Deleting files outside `lib/domain/` and `test/scenarios/`
- Modifying pattern files in `lib/patterns/`
- Modifying base infrastructure in `lib/core/`
- Changing CI/CD configuration
- Adding new dependencies to pubspec.yaml

## Architecture Constraints

- All entities extend `BaseEntity`
- All repositories extend `EntityRepository`
- File storage uses bytes-in-database pattern (no filesystem)
- Offline-first with ObjectBox (native) + IndexedDB (web), sync via Supabase
- Cross-platform code only - no platform-specific logic outside adapters
- Dual persistence: adapters implement common interfaces, domain code is platform-agnostic
