# Claude Code Configuration

## Project Type
Everything Stack template - Dart/Flutter cross-platform application

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

- Every feature needs a BDD scenario
- Scenarios live in `test/scenarios/`
- Use parameterized tests from `test/harness/`
- E2E tests validate scenarios
- All platforms must pass before merge

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
- Offline-first with Isar, sync via Supabase
- Cross-platform code only - no platform-specific logic outside adapters
