# Everything Stack

**A semantic layer for execution and learning.**

Everything Stack is complete application infrastructure that decouples WHERE code runs from WHAT the system learns. You write your logic once. The system decides where it lives based on what works. Every execution is logged. The system learns which execution choices led to better results. Over time, architecture adapts itself.

## Three Core Properties

### Execution Fungible
Services don't care where they run. Embedding extraction runs on-device one day, server the next. The Invocation log captures both. Learning treats them the same.

### Learning Persistent
Every execution logged: what happened, why we think it happened, what the user thought. Feedback flows back. System learns which execution choices produce better results. Over time, architecture reshapes itself.

### Self-Adapting
System observes its own performance, gets feedback, adapts. Not randomly. Empirically. You don't pre-decide "embeddings run server-side." You experiment. Logs show tradeoffs. System learns them.

---

## Quick Start

```bash
git clone <repo>
cp .env.example .env          # Add API keys (GROQ_API_KEY, DEEPGRAM_API_KEY, JINA_API_KEY)
flutter run -d windows         # Or: android, ios, chrome, macos, linux
flutter test                   # Unit tests (no API keys needed)
flutter test integration_test/ -d chrome  # E2E tests
```

---

## How It Works

### For AI Models
1. Define entities (`lib/domain/`)
2. Write E2E tests (`integration_test/`)
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

The loop: **execute -> log -> learn -> adapt -> execute (better)**

See ARCHITECTURE.md for the complete entity model.

---

## Stack

| Layer | Choice |
|-------|--------|
| Language | Dart 3.x |
| Framework | Flutter (mobile, web, desktop) |
| Native DB | ObjectBox |
| Web DB | IndexedDB |
| Sync | Supabase |
| Vector Search | HNSW (semantic, 8-12ms) |
| AI Services | Groq (LLM), Deepgram (STT), Jina (embeddings) |
| Testing | Flutter E2E (no mocks) |
| CI | GitHub Actions |

---

## Documentation

- **ARCHITECTURE.md** - Entity model, persistence, plugins, sync, scale
- **PATTERNS.md** - How to build: entities, services, testing, examples
- **TESTING.md** - E2E testing: no mocks, real persistence, all platforms
- **DECISIONS.md** - Rationale for major architectural choices
- **docs/DEVELOPMENT.md** - Build details, Rust/FFI, debug server, dependency management
- **.claude/CLAUDE.md** - Project definition, permissions, architecture constraints

### Template Usage
See `docs/DEVELOPMENT.md` for initializing this template for a new project.

---

## What Works
- Dual persistence: ObjectBox (native) + IndexedDB (web) with identical schemas
- Semantic search: HNSW vector indexing, 8-12ms queries
- Offline-first: changes persist locally, sync when online
- All 6 platforms: iOS, Android, macOS, Windows, Linux, Web
- Version history: reconstruct past state from deltas
- Graph relationships: link entities, multi-hop queries
- AtomicInsight extraction pipeline with auto-improving prompts
- Trainable mixin pattern for feedback collection
- 372+ integration tests passing

---

## License

MIT
