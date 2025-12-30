# Everything Stack

**A semantic layer for execution and learning.**

Everything Stack is complete application infrastructure that decouples WHERE code runs from WHAT the system learns. You write your logic once. The system decides where it lives based on what works. Every execution is logged. The system learns which execution choices led to better results. Over time, architecture adapts itself.

## Three Core Properties

### Execution Fungible
Services don't care where they run. Embedding extraction runs on-device one day, server the next. The Invocation log captures both. Learning treats them the same.

### Learning Persistent
Every execution logged: what happened, why we think it happened, what the user thought. Feedback flows back. System learns which execution choices → better results. Over time, architecture reshapes itself.

### Self-Adapting
System observes its own performance, gets feedback, adapts. Not randomly. Empirically. You don't pre-decide "embeddings run server-side." You experiment. Logs show tradeoffs. System learns them.

---

## Current Implementation Status

### ✅ What Works
- **Dual persistence:** ObjectBox (native) + IndexedDB (web) with identical schemas
- **Semantic search:** HNSW vector indexing, 8-12ms queries
- **Offline-first:** Changes persist locally, sync when online
- **All platforms:** iOS, Android, macOS, Windows, Linux, Web
- **Version history:** Reconstruct past state from deltas
- **Graph relationships:** Link entities, multi-hop queries
- **372 integration tests passing**

### ⚠️ Partial
- **Narrative services:** Core extraction working (3 tests), ObjectBox integration pending
- **Phase 6 trainable components:** Migration underway (~60% done), mixin-based pattern
- **Execution fungibility plugins:** Blueprint exists, not yet implemented
- **Learning adaptation loop:** AdaptationState model defined, training not yet active

### ❌ Not Started
- **Remote execution:** Service plugin selection not yet trainable
- **Multi-device sync:** v2 roadmap
- **Team collaboration:** v3 roadmap

---

## Quick Start

```bash
# 1. Clone
git clone <repo>

# 2. Create environment
cp .env.example .env
# Edit .env with your Groq API key, etc.

# 3. Run on any platform
flutter run -d android    # Android emulator
flutter run -d ios        # iOS simulator
flutter run -d chrome     # Web browser
flutter run -d macos      # macOS desktop
flutter run -d windows    # Windows desktop
flutter run -d linux      # Linux desktop

# 4. Run tests
flutter test              # All tests (uses mocks)
flutter test integration_test/ -d chrome  # E2E on web
```

---

## How It Works

### For AI Models
When a small model builds an app on Everything Stack:
1. Define entities (lib/domain/)
2. Write E2E tests (integration_test/)
3. Implement features until tests pass
4. Never choose databases, design sync, or solve platform problems
5. Application works on all platforms

### For the System
Every execution creates an Invocation:
- Component that ran (service name)
- Input/output (what it did)
- Execution context (local vs remote)
- User feedback (what they thought)
- Next time: AdaptationState guides decisions

See ARCHITECTURE.md for complete entity model.

---

## Stack

| Layer | Choice |
|-------|--------|
| Language | Dart |
| Framework | Flutter (mobile, web, desktop) |
| Native DB | ObjectBox |
| Web DB | IndexedDB |
| Sync | Supabase |
| Vector Search | HNSW (semantic) |
| AI Services | Groq (LLM), Deepgram (speech), Jina (embeddings) |
| Testing | Flutter (unit/integration/E2E) |
| CI | GitHub Actions |

---

## Documentation

**Foundation Documents:**
- **README.md** (you are here) - What is this, current status, quick start
- **ARCHITECTURE.md** - How it works: semantic layer, invocations, adaptation, execution fungibility
- **PATTERNS.md** - How to build: entities, services, testing, plugins, examples
- **TESTING.md** - How to test: E2E approach, platforms, debugging
- **.claude/CLAUDE.md** - Project initialization, permissions, build commands

**For New Projects:**
- **docs/templates/VISION_TEMPLATE.md** - Discover why your project exists
- **docs/templates/ARCHITECTURE_TEMPLATE.md** - Define what gets built

---

## Testing

Test your code through real E2E execution. No mocks. What you test is what ships.

E2E tests generate real Invocation logs that feed the learning system. Mocks generate fake signals.

**All Platforms:**
```bash
flutter test integration_test/ -d android   # Android emulator
flutter test integration_test/ -d ios       # iOS simulator
flutter test integration_test/ -d chrome    # Web browser
flutter test integration_test/ -d macos     # macOS desktop
flutter test integration_test/ -d windows   # Windows desktop
flutter test integration_test/ -d linux     # Linux desktop
```

See TESTING.md for complete E2E testing patterns.

---

## Core Philosophy

**Infrastructure completeness over simplicity.** Dual persistence, multi-platform abstractions, vector search, offline sync - complexity is paid ONCE in this template. Every application built on it inherits that infrastructure.

**All platforms are first-class.** Android, iOS, macOS, Windows, Linux, Web. Not native-first with web later. Complete or don't build it.

**Domain logic only.** When a small model builds an app, it defines entities and writes business logic. It never chooses databases, designs sync, or solves platform problems. Those are already solved.

---

## Why This Matters

Traditional architectures are static. You design once. It stays that way.

Everything Stack makes architecture a first-class learnable thing. The system observes its own performance, gets feedback, reshapes itself. Not randomly. Empirically.

The power isn't in any single layer. It's in the loop:
**execute → log → learn → adapt → execute (better next time)**

---

## Recent Changes

**Phase 6: Trainable Components** - Migrating from interface-based to mixin-based pattern
- Services now support pluggable implementations (local vs remote)
- Feedback collection automatic
- Next: Train plugin selection based on performance

**Consolidated Documentation** - Reduced from 41 files to 6 core docs
- Removed 4-layer testing pyramid (E2E only)
- Made execution fungibility explicit
- Added learning architecture overview

---

## Getting Started

1. Read ARCHITECTURE.md (understand how it works)
2. Read PATTERNS.md (learn how to build with it)
3. Read TESTING.md (understand E2E approach)
4. Run a test: `flutter test integration_test/ -d chrome`
5. Clone this as a new project: `git clone <repo> my-app`
6. Replace this README with project-specific content
7. Delete lib/example/ and test/scenarios/example_scenarios.dart
8. Add your entities to lib/domain/
9. Add your E2E tests to integration_test/
10. Implement until tests pass

See .claude/CLAUDE.md for project initialization checklist.

---

## License

MIT - Use as template for your own applications.

---

## Questions?

See ARCHITECTURE.md for how execution fungibility works.
See PATTERNS.md for service and entity patterns.
See TESTING.md for testing approach.
See .claude/CLAUDE.md for initialization and build commands.
