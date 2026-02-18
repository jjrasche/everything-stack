# Everything Stack

Cross-platform application infrastructure (Dart/Flutter). Decouples where code runs from what the system learns. Every execution is logged; the system adapts from feedback.

## Stack
- Language: Dart 3.x / Flutter (iOS, Android, macOS, Windows, Linux, Web)
- Database: ObjectBox (native) + IndexedDB (web)
- Sync: Supabase (future)
- Search: HNSW vector index (8-12ms queries)
- AI: Groq (LLM), Deepgram (STT), Jina (embeddings)

## Commands
```bash
cp .env.example .env              # Create env (debug mode only)
flutter run -d windows            # Run on any platform
flutter test                      # Unit tests (no API keys needed)
flutter test integration_test/ -d windows  # E2E tests
flutter analyze                   # Lint
```

## Architecture

### Key Directories
- `lib/core/` - Base entity, repository, debug, platform detection
- `lib/domain/` - Pure Dart entities (no ORM decorators)
- `lib/services/` - Business logic, extraction, training, coordinator
- `lib/tools/` - Self-contained domains (regulation, task, timer) with own entities/repos/adapters
- `lib/persistence/` - ObjectBox (native) + IndexedDB (web) adapters
- `lib/patterns/` - Opt-in mixins (Trainable, Embeddable, Temporal, etc.)
- `lib/io/` - Communication substrate (WebSocket, protocols, channels)
- `lib/bootstrap/` - GetIt DI container setup, platform-specific initialization

### Data Flow
Event -> Coordinator -> LLM (with context + voice traits) -> Tool execution -> Persistence. Enrichment pipeline indexes entities asynchronously. Invocation logs feed adaptation.

## Non-Negotiable Principles
1. ALL platforms first-class. If it only works on some platforms, it's not done.
2. Infrastructure completeness over simplicity. Complexity paid once in the template.
3. Domain developers write domain logic only. No persistence design, no platform code.
4. Entities are pure Dart. ORM decorators belong in adapters only.

## Permissions
**Run without asking:** read ops, `flutter test`, `flutter build`, lint, git commit/push/branch/PR
**Ask before:** deleting files outside `lib/domain/` and `test/scenarios/`, modifying `lib/patterns/` or `lib/core/`, changing CI, adding dependencies

## Architecture Constraints
- All entities extend `BaseEntity`, all repos extend `EntityRepository`
- No `dynamic` in public APIs. Typed payloads at boundaries.
- File storage: bytes-in-database (no filesystem)
- IO layer handles ALL external communication (see `lib/io/README.md`)
- Every package in `pubspec.yaml` must support all 6 platforms
- Use `debugPrint()` (no Logger class exists)

## Global References
Read from `~/.claude/references/` when relevant:
- `coding-standards.md` - Naming, comments, test patterns
- `dart-flutter.md` - Widget lifecycle, platform quirks, state
- `flutter-workflow.md` - Hot reload, background run, debug workflow

## Current Work: Memory Encoder Pipeline
6-stage encoder: normalize -> segment -> cohere -> classify -> decontextualize -> dedup.
**SLM-first**: build on-device ONNX runner, run zero-shot, evaluate, fine-tune. NO LLM calls for stages that can use SLMs.
Phase 1 (normalize + segment) complete. **Phase 2 (cohere SLM) is next.**
Read `.claude/plans/encoder-golden-data-stage-by-stage.md` for full plan and instructions. Do NOT enter plan mode — execute directly.

## Project References
- `ARCHITECTURE.md` - Entity model, persistence, plugins, sync, scale
- `PATTERNS.md` - How to build: entities, services, testing, examples
- `TESTING.md` - E2E testing: no mocks, real persistence, all platforms
- `DECISIONS.md` - Rationale for major architectural choices
- `docs/DEVELOPMENT.md` - Build details, Rust/FFI, debug server, dependency management
- `.claude/plans/encoder-golden-data-stage-by-stage.md` - Stage-by-stage encoder golden data plan
