# Everything Stack

A clonable template for AI-native software development. Clone, initialize, build.

## Philosophy

This template embeds the Autonomous Software Development (ASD) paradigm. AI builds, humans govern. Infrastructure is solved once. Domain logic is fresh per project.

**Core beliefs:**
- One codebase across all platforms reduces what AI manages
- Opinionated choices eliminate decision fatigue
- Patterns solve common problems once, dormant until needed
- Documentation lives in code, co-located with implementation
- BDD scenarios are the contract between human intent and AI implementation

## What's Inside

**Infrastructure (use as-is):**
- `lib/core/` - Base entity and repository patterns
- `lib/patterns/` - Opt-in mixins (embeddings, temporal, ownership, versioning, location, edges)
- `lib/services/` - Embedding generation, sync management
- `test/harness/` - Parameterized test infrastructure

**Templates (fill in per project):**
- `docs/templates/VISION_TEMPLATE.md` - Discover why this project exists
- `docs/templates/ARCHITECTURE_TEMPLATE.md` - Define what gets built

**Guidance (read, don't modify):**
- `docs/asd/` - Principles, workflow, checkpoints
- `docs/testing/` - BDD approach and testing philosophy

**Example (delete after understanding):**
- `lib/example/` - One entity showing all patterns
- `test/scenarios/example_scenarios.dart` - One complete BDD cycle

## Quick Start

1. Clone this repo
2. Read `.claude/CLAUDE.md` for initialization instructions
3. Complete `docs/templates/VISION_TEMPLATE.md` with Claude AI (conversational)
4. Complete `docs/templates/ARCHITECTURE_TEMPLATE.md` with Claude AI
5. Tell Claude Code: "Initialize this as [your project name]"
6. Build features following ASD workflow

## Stack

| Layer | Choice |
|-------|--------|
| Language | Dart |
| Framework | Flutter (mobile, web, desktop, embedded) |
| Local DB | Isar |
| Cloud DB | Supabase (self-hosted or cloud) |
| AI Coder | Claude Code |
| CI | GitHub Actions |
| CD | Firebase App Distribution + Hosting |

## Platform Targets

- iOS / Android (mobile)
- Web (browser)
- macOS / Windows / Linux (desktop)
- Raspberry Pi / embedded Linux (IoT, kiosk)

Same codebase. Same tests. Platform-specific code isolated to thin adaptation layers.

## Testing

Tests follow a 4-layer approach. All layers run in CI.

**Unit Tests** - Service interfaces, mocks, algorithms
```bash
flutter test test/services/
```

**Integration Tests** - Cross-service workflows on Dart VM
```bash
flutter test test/integration/
```

**BDD Scenarios** - User-facing behavior (Gherkin format)
```bash
flutter test test/scenarios/
```

**Platform Verification** - Actual platform implementations
```bash
flutter test integration_test/ -d android   # Android emulator
flutter test integration_test/ -d chrome    # Web browser
flutter test integration_test/ -d macos     # Desktop
```

**Run all tests (CI):**
```bash
flutter test                    # Unit + integration + scenarios
flutter test integration_test/  # Platform verification (actual devices)
```

See `docs/testing/TESTING_APPROACH.md` for complete testing philosophy and patterns.
