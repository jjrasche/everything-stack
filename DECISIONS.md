# Architectural Decisions

**Why we chose the architecture we chose.**

This document explains the trade-offs and reasoning behind major architectural decisions. These are locked in decisions - understanding them helps you maintain and extend the system correctly.

---

## UUID vs Sequential IDs

**Decision**: UUID as primary key for all entities

**Rationale**:
- UUID is universal across offline devices (no coordination needed)
- No ID generation/sequencing required for sync
- Matches modern API design patterns
- Works seamlessly with distributed systems (v2 roadmap)

**Trade-off**:
- Slightly larger indices (negligible with modern databases)
- Slightly longer query time (still <1% impact)

**Why This Matters**:
When the system eventually syncs across multiple devices, each device generates its own IDs. UUIDs don't collide. Sequential IDs would require central coordination (defeats offline-first).

---

## Adapter-as-Repository vs ORM

**Decision**: Platform-specific adapters extend a common repository interface. Domain entities stay ORM-free.

**Pattern**:
```
Domain Entity (pure Dart, no decorators)
    ↓
Repository Interface (abstract CRUD methods)
    ↓
Platform Adapters
    ├─ ObjectBoxAdapter (native: iOS, Android, macOS, Windows, Linux)
    └─ IndexedDBAdapter (web: browser)
```

**Rationale**:
- Domain entities have **zero** ORM knowledge (@Entity, @Id, @Property all in adapters)
- Enables web compilation (no dart:ffi imports in domain code)
- Same entity works with ObjectBox, IndexedDB, or any future backend
- Platform-specific persistence details isolated, easy to swap

**Trade-off**:
- Manual serialization in adapter wrappers (ObjectBoxAdapter converts Entity → EntityOB)
- Two implementations to maintain (ObjectBox + IndexedDB)
- Can't use ORM generate-once patterns

**Why This Matters**:
Everything Stack must work on web. Web can't use dart:ffi (native libraries). If domain entities had @Entity decorators, they'd import dart:ffi indirectly. With adapters, domain code is platform-agnostic. We paid this cost once.

---

## Dual Persistence (ObjectBox + IndexedDB)

**Decision**: Native platforms use ObjectBox. Web uses IndexedDB. Same API via adapters.

**Why ObjectBox for Native**:
- Superior performance (8-12ms queries vs 50-200ms for alternatives)
- Native HNSW vector indexing (semantic search)
- Synchronous transactions (ACID guarantees)
- Production-grade on mobile

**Why IndexedDB for Web**:
- Only option on browser (no localStorage, no local SQL)
- Inherently async (no choice)
- Good enough performance (100-300ms operations)
- Offline storage capability

**Trade-off**:
- Two separate implementations
- IndexedDB is slower (3-5x)
- API differences hidden by adapters (complex abstraction)

**Why This Matters**:
Web and native have different persistence constraints. Can't use one database everywhere. This decision accepts the complexity cost and hides it behind adapters.

---

## Trainable Mixin Pattern

**Decision**: Generic `Trainable` mixin enables feedback loops on any entity.

**Pattern**:
```dart
class MyEntity with Trainable {
  Future<void> trainFromFeedback(String correlationId) async {
    // Feedback collected elsewhere
    // This method teaches the entity from that feedback
  }
}
```

**Rationale**:
- Decouples feedback collection from component implementation
- Enables feedback on any entity (Invocation, Turn, Feedback, AdaptationState)
- Shared interface across diverse components
- Feedback is first-class, not bolted on

**Trade-off**:
- Requires adapters to implement training queries (specific per backend)
- Mixin must work with heterogeneous entities (harder to type)

**Why This Matters**:
The entire learning system depends on "entities can learn from feedback." Making this a generic mixin (vs baked into specific types) means new entities can be trainable without framework changes.

---

## Turn Entity Inclusion

**Decision**: Keep Turn as atomic feedback boundary (not flatten to Event + Invocation only)

**What is a Turn?**
One complete conversational exchange:
- User speaks
- STT processes
- LLM generates response
- TTS speaks back
- User rates result

This is ONE turn. Three Invocations. One feedback.

**Why Turn Matters**:

1. **Feedback Collected at Turn Level**
   - User rates entire exchange ("Your response was unhelpful")
   - NOT rated per component ("STT was 90% confident, LLM was unsure, TTS sounded weird")
   - Without Turn, three feedback records (confusing, fragmented)

2. **Training is Systemic, Not Isolated**
   - "This turn failed" means these three components working together failed
   - STT might have misheard, LLM misunderstood, TTS mispronounced - systemic failure
   - Training components in isolation loses context ("why did STT fail?")

3. **Latency Tracking End-to-End**
   - `Turn.latencyMs` = "how long did user's interaction take?" (including network, scheduling, waiting)
   - `Invocation.latencyMs` = component time only (30-40% of user experience)
   - Users care about total experience, not component performance

4. **Feedback Queue is Clear**
   - `Turn.markedForFeedback` = user requested review
   - Without Turn: three items in queue from one interaction (confusing)
   - With Turn: one item per exchange (clear, actionable)

5. **Query Patterns Matter**
   - "Show me failed turns" = one query
   - "Show me turns with >5s latency" = actionable insight
   - Without Turn: reconstruct from scattered Invocations (lossy)

**Alternative (Rejected)**: Flatten to Event + Invocation only
- Loses atomic feedback boundary
- Makes queries harder (reconstruct turn from invocations)
- Fragments training context (per-component feedback)
- Removes latency tracking at interaction level

**Trade-off**:
- Additional entity (more schema, more storage)
- Must maintain Turn←→Invocation relationship

**Why This Matters**:
Feedback is the core of the learning system. Where feedback lives shapes everything: training, queries, debugging. Atomic turns make feedback actionable.

---

## Type Safety Everywhere (AI Safety)

**Decision**: All JSON blobs are typed at boundaries. No `dynamic` in public APIs.

**Why This Matters for AI-Generated Code**:

When an LLM generates code without visible types:
```dart
// BAD: LLM can't see what's in payloadJson
final payload = jsonDecode(invocation.payloadJson);
final confidence = payload['confidence'];  // Might not exist!
```

With explicit types:
```dart
// GOOD: LLM knows exactly what type this is
final sttPayload = STTInvocationPayload.fromJson(invocation.payloadJson);
final confidence = sttPayload.confidence;  // Type-safe, exists or throws
```

**How We Enforce It**:
1. Entity fields are never `dynamic` (even JSON blobs are `String` with schema info elsewhere)
2. Payload types are separate classes (`STTInvocationPayload`, `LLMInvocationPayload`, etc.)
3. Repository methods generic over `T` (not `EntityRepository<dynamic>`)
4. UUID everywhere (no ambiguity: always `String`, never `int`)
5. No loose JSON structures (metadata, data have defined schemas)

**Benefits**:
- IDE autocomplete works
- Tests catch type mismatches immediately
- LLM can't accidentally write code that assumes wrong types
- New developers (or AIs) can't create data inconsistencies

**Trade-off**:
- More boilerplate (payload classes for each component type)
- More serialization code (auto-generated where possible)

**Why This Matters**:
Everything Stack is designed for AI to build on. AI-generated code is fragile without guardrails. Enforcing types is a guardrail.

---

## Execution Fungibility (Plugin Pattern)

**Decision**: Services have pluggable implementations. System chooses plugin based on what works.

**Example: EmbeddingService**

Every service can have multiple implementations:
- Local (on-device, private, fast for small models)
- Remote (server, scalable, powerful models)
- Hybrid (try local first, fall back to remote)

Plugin choice is logged in Invocation, user feedback trains the selection.

**Why This Matters**:

Traditional: "Embeddings run server-side. Period."

Everything Stack: "Let's see which execution context works best for this user, this device, this workload. Adapt based on feedback."

**Trade-off**:
- Every service needs multiple implementations
- Plugin selection adds complexity
- Training infrastructure required (not yet implemented)

**Why This Matters**:
Decoupling execution location from logic enables:
- Privacy-conscious users (run local)
- Power-constrained devices (run remote)
- Bandwidth-constrained networks (run local)
- Accuracy requirements (run remote for better models)

Users don't need separate codebases. Same app adapts.

---

## All Platforms First-Class

**Decision**: iOS, Android, macOS, Windows, Linux, Web - all must work completely. Not "native-first with web later."

**Why**:
- User might want desktop (macOS, Windows, Linux)
- User might want web (browser, no install)
- Template is incomplete if any platform doesn't work
- Complexity of cross-platform abstraction is paid once

**Trade-off**:
- Two persistence backends (ObjectBox + IndexedDB)
- Platform detection/routing code
- Six different test targets in CI
- Must test on emulators/simulators for all platforms

**Why This Matters**:
Small teams can't afford platform-specific codebases. Everything Stack is designed for teams that build once, deploy everywhere. This decision forces completeness.

---

## Infrastructure Completeness Over Simplicity

**Decision**: If any application might need a capability, this template provides it.

**Examples**:
- Offline-first (complexity paid once)
- Dual persistence (complexity paid once)
- Vector search (complexity paid once)
- Semantic indexing (complexity paid once)
- Trainable feedback system (complexity paid once)

**Why**:
Small model building an app doesn't need to solve infrastructure. It needs to write business logic. Everything Stack absorbs infrastructure complexity.

**Trade-off**:
- Template is larger than minimal
- Not every app uses every feature
- More to learn, maintain, test

**Why This Matters**:
This is a template for AI agents building apps. AI is good at business logic, bad at infrastructure decisions. Make all infrastructure decisions upfront, in one place.

---

**Last Updated**: December 26, 2025
