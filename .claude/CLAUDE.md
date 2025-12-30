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
- What is Everything Stack: `README.md` (overview + current status)
- How it works: `ARCHITECTURE.md` (semantic layer, execution fungibility, learning)
- How to build: `PATTERNS.md` (entities, services, adaptation, examples)
- How to test: `TESTING.md` (E2E testing, platforms, learning signals)
- Templates for new projects: `docs/templates/` (VISION_TEMPLATE.md, ARCHITECTURE_TEMPLATE.md)

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

Test your code through real E2E execution. No mocks. What you test is what ships.

E2E tests generate real Invocation logs that feed the learning system. The system learns from what it actually does, not from mock behavior.

**What to test:**
- ✅ Every user-facing feature (message, rating, action)
- ✅ Every end result (entity created, updated, deleted)
- ✅ Every adaptation loop (feedback → system learns)
- ✅ Every platform (iOS, Android, Web, macOS, Windows, Linux)

**How to test:**
- Real components, real services, real persistence
- No test doubles or mocks
- Run on actual device or emulator
- Every test generates an Invocation log

**Command:** `flutter test integration_test/ -d {platform}`

**Read:** `TESTING.md` for complete guidance on E2E testing patterns and platform setup

## Build and Run

### Local Development
```bash
# 1. Create .env from template
cp .env.example .env

# 2. Edit .env with your actual API keys
# GROQ_API_KEY=your_actual_groq_key
# DEEPGRAM_API_KEY=your_actual_deepgram_key
# JINA_API_KEY=your_actual_jina_key

# 3. Run on any platform (loads .env in debug mode)
flutter run -d windows  # Windows
flutter run -d macos    # macOS
flutter run -d ios      # iOS simulator
flutter run -d android  # Android emulator
flutter run -d chrome   # Web
```

**Note:** `.env` file is loaded **only in debug mode** via `flutter_dotenv`. Fallback chain: `.env` → `.env.example` → compile-time env vars.

### Testing
```bash
flutter test                           # All tests (uses mocks, no API keys)
flutter test integration_test/ -d ios  # Platform verification
```

### Building for Deployment
```bash
# Pass API keys as --dart-define (keys baked into binary)
flutter build apk \
  --dart-define=GROQ_API_KEY=${{ secrets.GROQ_API_KEY }} \
  --dart-define=DEEPGRAM_API_KEY=${{ secrets.DEEPGRAM_API_KEY }}

flutter build ipa \
  --dart-define=GROQ_API_KEY=xxx \
  --dart-define=DEEPGRAM_API_KEY=xxx

flutter build macos --dart-define=... # macOS
flutter build windows --dart-define=... # Windows
flutter build web --dart-define=...   # Web
```

### Environment Variables (Priority Order)

**Debug Mode (Local Development):**
1. `.env` file (runtime, debug only)
2. `.env.example` fallback (if .env missing)
3. `--dart-define` (compile-time)
4. OS env vars (CI/CD agents)

**Release Mode (Production):**
- `--dart-define` only (compile-time, baked into binary)
- NO file-based loading (prevents accidental secret commits)

**CI/CD:** Set secrets in GitHub → pass to build as `--dart-define=GROQ_API_KEY=${{ secrets.GROQ_API_KEY }}`

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
- **Entities are pure Dart classes with NO ORM-specific decorators** (@Entity, @Id, @Property, @Transient)
  - ObjectBox decorators belong in adapters only, not domain entities
  - This ensures web compilation succeeds (no dart:ffi imports in domain code)
  - Same entity works with ObjectBox, IndexedDB, or other backends
- File storage uses bytes-in-database pattern (no filesystem)
- Offline-first with ObjectBox (native) + IndexedDB (web), sync via Supabase
- Cross-platform code only - no platform-specific logic outside adapters
- Dual persistence: adapters implement common interfaces, domain code is platform-agnostic
- See `lib/tools/README.md` for tool domain architecture and ORM decorator separation

## Current Work

This section tracks active development, blockers, and work in progress. It changes daily. **When a feature is finished, delete it from this section.** If the work is architecturally significant, document the decision in DECISIONS.md instead.

### Active Development
- Trainable component migration (9 components to mixin pattern, ~60% done)
- ContextManager service integration
- Invocation logging wired throughout pipeline

### Blockers
- ContextManager blueprint exists (.claude/ARCHITECTURE_TRANSITION.md), implementation pending
- Plugin selection training: Invocation logs captured, feedback training loop not yet active
- Multi-device sync: requires Supabase schema updates + conflict resolution

### What's Working
- Event/Invocation/Turn entity model (typed, no dynamic fields)
- Dual persistence (ObjectBox native, IndexedDB web) with identical schemas
- Semantic search (HNSW, 8-12ms queries)
- Offline-first architecture with Supabase sync
- Trainable mixin pattern for feedback collection
- Plugin pattern for execution fungibility (local vs remote, not yet trainable)
- All 6 platforms (iOS, Android, macOS, Windows, Linux, Web)
- 372 integration tests passing, E2E approach

---

## Workflows (Phase 5D+)

**Definition:** Automated grouping of tasks with conditional logic and decision points. Inherently trainable, triggered by user, LLM selection, or system automation.

**Key Pattern:**
```
Workflow = Sequence of Tasks + Decision Logic + Trainable Aspects
```

**Integration with Coordinator:**
- Workflows appear as tools in ToolSelector
- LLM can select: individual tasks OR workflow.invoke_workflow_name
- Each task in workflow creates Invocation (same as individual tool)
- Conditional branches log as workflow_decision invocations
- Feedback on workflow success/failure trains future selection

**Tool Selection Logging (Trainable):**
When LLM chooses tools (including workflows), log:
```dart
Invocation(
  componentType: 'tool_selector',
  output: {
    'selected_tools': [
      {
        'tool': 'workflow.prepare_meeting',
        'confidence': 0.92,
        'reasoning': 'User asked to prepare meeting - handles all prep tasks'
      }
    ]
  },
)
```

**Invocation Types in Workflows:**
- `workflow_task` - individual task execution
- `workflow_decision` - conditional branch taken
- `tool_selector` - LLM chose this workflow (includes reasoning)

**Trainable Aspects:**
- Task ordering (feedback: "too slow" → parallelize)
- Task selection (feedback: "didn't need this task" → adjust conditional)
- Conditional thresholds (feedback: "send agenda for longer meetings" → adjust threshold)
- LLM tool selection (feedback: "wrong workflow" → lower confidence)

**NOT Self-Modifying:** Workflows improve through user feedback only, no autonomous self-training.
