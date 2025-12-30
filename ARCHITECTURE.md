# Architecture

## Overview

Everything Stack provides complete application infrastructure for autonomous software development across all platforms (iOS, Android, Web, macOS, Windows, Linux). The architecture is built on proven patterns that enable small language models to focus on domain logic while the framework handles persistence, sync, platform abstraction, and cross-cutting concerns.

---

## Core Design Principles

### 1. Infrastructure Completeness Over Simplicity
The complexity of dual persistence (ObjectBox native + IndexedDB web), multi-platform blob storage, vector search, and offline-first sync is paid **once** in this template. Every application inherits that infrastructure without architectural decisions.

### 2. All Platforms Are First-Class
- iOS, Android, macOS, Windows, Linux, Web all have complete, tested implementations
- Same codebase runs on mobile, web, desktop, and headless server
- Platform-specific code is isolated to thin adaptation layers
- Domain entities and repositories are platform-agnostic
- Same test suite runs on all platforms

### 3. Domain Logic Only
AI models write:
- Domain entities (what data exists)
- Business logic (what operations are valid)
- BDD scenarios (what users can do)

They **never** choose databases, design sync protocols, or solve platform-specific storage.

### 4. Opinionated Architecture Removes Decision Fatigue
Every layer has one obvious choice:
- **Entities**: Extend `BaseEntity` with mixins
- **Repositories**: Extend `EntityRepository<T>`
- **Persistence**: ObjectBox (native) or IndexedDB (web)
- **Sync**: Supabase
- **Vector Search**: ObjectBox HNSW (native) or pure Dart (web)

### 5. Type Safety Everywhere (AI Safety)
All JSON blobs are typed at boundaries. No `dynamic` in public APIs.

---

## Execution Fungibility: The Plugin Pattern

Traditional architecture locks code to execution location: "This runs on mobile. That runs on server."

Everything Stack decouples execution location from business logic through pluggable service implementations.

### How It Works

Every service has multiple plugins (implementations). The system chooses which to use based on what works.

**Example: EmbeddingService**

```dart
// Service interface (domain logic)
abstract class EmbeddingService {
  Future<List<double>> embed(String text);
}

// Local plugin (on-device)
class LocalEmbeddingPlugin implements EmbeddingService {
  final _model = loadOnDeviceModel();

  @override
  Future<List<double>> embed(String text) async {
    return _model.predict(text);
  }
}

// Remote plugin (server-side)
class RemoteEmbeddingPlugin implements EmbeddingService {
  final _jinaClient = JinaClient();

  @override
  Future<List<double>> embed(String text) async {
    return _jinaClient.embed(text);
  }
}

// The magic: Plugin selection is trainable
class EmbeddingService {
  final _plugin = selectPlugin(); // Local or remote?

  static EmbeddingService selectPlugin({required AdaptationState? adaptation}) {
    // If adaptation learned "remote is faster" → use remote
    // If adaptation learned "local is more accurate" → use local
    // If no learning yet → use heuristic (device CPU, network speed, etc.)
    return adaptation?.pluginChoice == 'remote'
      ? RemoteEmbeddingPlugin()
      : LocalEmbeddingPlugin();
  }
}
```

### Every Execution is Logged

The Invocation log captures:
- **Component**: Which service ran (EmbeddingService, SpeakerMatcher, etc.)
- **Plugin**: Which implementation (LocalEmbeddingPlugin, RemoteEmbeddingPlugin)
- **Input/Output**: What was computed
- **Latency**: How fast (local 45ms, remote 120ms)
- **Accuracy**: Was it right? (user feedback)

### System Learns

Over time, the system observes tradeoffs:

```
EmbeddingService.local:
  - Latency: 45ms (fast)
  - Accuracy: 0.92 similarity score
  - Privacy: No network calls
  - Cost: CPU usage

EmbeddingService.remote:
  - Latency: 120ms (slower)
  - Accuracy: 0.89 similarity score
  - Privacy: Sends to server
  - Cost: Network + API fees
```

User feedback ("I found what I needed" vs "That wasn't relevant") trains the system:

```dart
// If user says "this was right" more often for local → use local next time
// If user says "this was wrong" more often for remote → avoid remote
AdaptationState learns:
{
  'EmbeddingService.plugin_choice': {
    'local': 8/10 correct,
    'remote': 6/10 correct,
    → Choose local
  }
}
```

### Why This Matters

1. **Not Manually Decided**: You don't hand-code "use local for privacy, remote for power."
2. **Adaptive**: As workload changes, plugin selection adapts.
3. **Observable**: Invocation logs show which choices work.
4. **Trainable**: User feedback tunes the decisions.

Traditional approach: "Embeddings run server-side. Period."
Everything Stack: "Let's see what actually works for this user, this device, this workload."

---

## Type Safety & AI Safety

### Why This Matters for AI-Generated Code

When an LLM generates code without visible types, it can make assumptions that are wrong:
- Treating a transcription string as a token count
- Assuming metadata contains confidence when it contains component type
- Accessing fields that don't exist in a particular payload variant

**Example of unsafe code:**
```dart
// Bad: LLM can't see what's in payloadJson
final payload = jsonDecode(invocation.payloadJson);
final confidence = payload['confidence'];  // Might not exist!
```

**Example of safe code:**
```dart
// Good: LLM knows exactly what type this is
final sttPayload = STTInvocationPayload.fromJson(invocation.payloadJson);
final confidence = sttPayload.confidence;  // Type-safe, exists or throws
```

### How Everything Stack Enforces This

1. **Entity fields are never `dynamic`** - Even JSON blobs are `String` with type information elsewhere
2. **Payload types are separate classes** - `STTInvocationPayload`, `LLMInvocationPayload`, etc.
3. **Repository methods are generic over T** - `EntityRepository<T>` is type-safe, not `EntityRepository<dynamic>`
4. **UUID everywhere** - No ambiguity about ID types (always String, never int at boundary)
5. **No loose JSON structures** - metadata, data fields have defined schemas

This means:
- IDE autocomplete works correctly
- Tests catch type mismatches immediately
- LLM can't accidentally write code that assumes wrong field types
- New developers (or AIs) can't create data inconsistencies

---

## Domain Entities

Core entities represent the trainable conversation pipeline. Each is fully typed with no dynamic fields.

### Event
**Purpose**: Represents a system or user-triggered event
- **Fields**:
  - `correlationId: String` - Links all operations in a synchronous chain
  - `parentEventId: String?` - Links async chains (e.g., timer fires later under same parent event)
  - `source: String` - Who triggered: 'user', 'timer', 'system'
  - `timestamp: DateTime` - When event occurred
  - `payloadJson: String` - Event payload stored as JSON (schema varies by source)
- **Patterns**: None (leaf event data)
- **Persistence**: UUID as primary key
- **Notes**: Everything scopes to an event. Invocations, turns, feedback all trace back to the initiating event.

### Invocation
**Purpose**: Records a single component invocation with input, output, and metadata

An invocation is the atomic unit of work: one component receives input and produces output (success or failure).

- **Fields**:
  - `correlationId: String` - Links to Event
  - `componentType: String` - Which component: 'stt', 'llm', 'tts', 'context_manager'
  - `turnId: String?` - Links to Turn (for conversation context)
  - `success: bool` - Did it succeed?
  - `confidence: double` - How confident was the result? (0.0 to 1.0)
  - `input: String?` - What was requested (typed, component-specific)
  - `output: String?` - What was produced (typed, component-specific)
  - `metadata: Map<String, dynamic>` - Component-specific data (execution time, model used, etc.)
- **Patterns**:
  - `Trainable` - Can be trained from feedback
  - `Embeddable` - Has embeddings for semantic search
- **Persistence**: UUID as primary key
- **Notes**: Input and output are fully typed at the component level (STTInvocationPayload, LLMInvocationPayload, etc.)

### Turn
**Purpose**: Atomic boundary for user feedback and training

A Turn represents one complete conversational exchange: user speaks → STT processes → LLM responds → TTS plays. This boundary is crucial because:

1. **Feedback is collected at Turn level, not component level** - User rates the entire exchange: "Your response was unhelpful." They're not rating STT separately from LLM separately from TTS. Without Turn, you'd store one feedback per invocation (confusing - which one matters?) or reconstruct the boundary from Invocations (lossy, error-prone).

2. **Training is systemic, not isolated** - When feedback says "this turn failed", you're saying "these three components working together failed." STT might have misheard, LLM misunderstood, TTS mispronounced - but the failure was systemic. Without Turn, you train components in isolation, losing that context.

3. **Performance metrics matter at interaction granularity** - `Turn.latencyMs` is "how long did the user's interaction take?" That includes network, scheduling, waiting for responses. If you only track `Invocation.latencyMs`, you miss 30% of the time (overhead between components). Users care about total experience, not component performance in isolation.

4. **markedForFeedback is the feedback queue** - Where does "this needs human review" live? If it's on Invocation, you could have 3 items in the feedback queue from one user interaction (confusing). If it's on Turn, you have one item per exchange (clear).

5. **Query patterns matter** - "Show me failed turns" or "Turns with >5s latency" are gold for debugging. Without Turn, you need complex reconstructions from scattered Invocations.

- **Fields**:
  - `correlationId: String` - Ties together all invocations in this exchange
  - `conversationId: String` - FK to Conversation
  - `sttInvocationId: String?`, `llmInvocationId: String?`, `ttsInvocationId: String?` - Links to invocations
  - `result: String` - 'success', 'error', 'partial'
  - `errorMessage: String?`, `failureComponent: String?` - Debug info
  - `latencyMs: int` - Total turn time (ms)
  - `markedForFeedback: bool` - User marked this for review
  - `markedAt: DateTime?`, `feedbackTrainedAt: DateTime?` - Feedback lifecycle
- **Patterns**:
  - `Trainable` - Can be trained from feedback
  - `Temporal` - Turn sequence in conversation
- **Persistence**: UUID as primary key
- **Notes**: Turn is the feedback boundary. Remove it, and you atomize feedback, lose training context, and make queries harder.

### Feedback
**Purpose**: Records user feedback on an invocation or turn

Feedback enables day-one trainability. Every invocation and turn can be fed back on.

- **Fields**:
  - `invocationId: String?` - Which invocation this feedback is about (nullable for turn-level feedback)
  - `turnId: String?` - Which turn this feedback is about (nullable for background feedback)
  - `componentType: String` - Which component this feedback trains
  - `rating: int` - 1-5 rating
  - `comment: String?` - User's text feedback
  - `feedbackType: String` - 'correction', 'suggestion', 'clarification'
- **Patterns**:
  - `Trainable` - Feedback itself can be trained (meta-feedback)
- **Persistence**: UUID as primary key
- **Notes**: Feedback is the signal. Everything else is structure to collect, store, and act on feedback.

### AdaptationState
**Purpose**: Stores learned adaptations for each component

As the system collects feedback, components improve by learning from that feedback. AdaptationState tracks learned behavior.

- **Fields**:
  - `componentType: String` - Which component this trains: 'stt', 'llm', 'tts', 'context_manager'
  - `scope: String` - 'global' (all users) or 'user' (personalized)
  - `userId: String?` - User ID if scope='user'
  - `data: Map<String, dynamic>` - Component-specific learned state (thresholds, preferred models, etc.)
  - `version: int` - Conflict resolution via optimistic locking
- **Patterns**:
  - `Trainable` - Can be trained from feedback
- **Persistence**: UUID as primary key with version control
- **Notes**: Version field enables multi-device sync (optimistic locking). Scope enables personalization. Data is component-defined.

---

## Patterns (Opt-In Mixins)

### Trainable
**Enables**: User feedback loops to train components
- **Methods**:
  - `trainFromFeedback(correlationId)` - Train from feedback on this turn
  - Can be mixed into any entity
- **Used By**: Invocation, Turn, Feedback, AdaptationState
- **Notes**: Generic mixin providing shared training interface. Feedback is collected at Event/Invocation/Turn level, training happens at Turn/Component level, adaptation state stores learned changes.

### Embeddable
**Enables**: Semantic search via vector embeddings
- **Methods**:
  - `generateEmbedding(text)` - Create vector from text
  - `updateEmbedding(vector)` - Store vector
  - `semanticSearch(queryVector)` - Find similar entities
- **Used By**: Invocation (search by semantic similarity across turns)
- **Notes**: Native (ObjectBox HNSW) and Web (pure Dart) implementations included

### Temporal (Not Used Yet)
**Enables**: Due dates, scheduling, recurrence
- Future expansion for scheduling features

### Ownable (Not Used Yet)
**Enables**: Multi-user isolation
- Future expansion for team/organization features

### Versionable (Partial)
**Enables**: Change history and conflict resolution
- Implemented for AdaptationState (version field for optimistic locking)

---

## Persistence Layer

### Design Pattern: Adapter-as-Repository

Domain entities are **pure Dart** (no ORM decorators). Platform-specific persistence details live entirely in adapters:

```
Domain Layer
  Event, Invocation, Turn, Feedback, AdaptationState (pure Dart, no decorators)
        ↓
Repository Layer
  EntityRepository<T> (generic CRUD + handlers + lifecycle hooks)
        ↓
Adapter Layer
  BaseIndexedDBAdapter<T> (IndexedDB queries)
  BaseObjectBoxAdapter<T, OB> (ObjectBox queries)
        ↓
Database Layer
  IndexedDB (web)
  ObjectBox (native)
```

### UUID as Primary Key

All entities use `uuid: String` as primary key:
- **Benefit**: UUID is universal, not sequential in databases. No coordination needed across devices.
- **Method Signature**: `findById(String uuid)` - primary method
- **Legacy**: `findByIntId(int id)` - deprecated but supported
- **Enforcement**: Updated PersistenceAdapter interface to reflect UUID-based design

### IndexedDB Adapter (Web)

```dart
class InvocationIndexedDBAdapter extends BaseIndexedDBAdapter<Invocation>
    implements InvocationRepository<Invocation> {
  // Provides all async queries for web platform
  // - findByTurn(turnId)
  // - findByContextType(componentType)
  // - findByIds(List<String>)
  // - deleteByTurn(turnId)
}
```

**Notes**:
- IndexedDB is inherently async (no synchronous transactions)
- Transaction methods throw UnsupportedError
- Vector search uses pure Dart HNSW implementation (no native libraries on web)

### ObjectBox Adapter (Native)

```dart
class InvocationObjectBoxAdapter
    extends BaseObjectBoxAdapter<Invocation, InvocationOB>
    implements InvocationRepository<Invocation> {
  // Wrapper pattern: Domain Invocation ←→ ObjectBox InvocationOB
  // - toOB(entity) converts domain to wrapper
  // - fromOB(ob) converts wrapper back to domain
  // Provides all sync+async queries for native platforms
}
```

**Notes**:
- Wrappers (InvocationOB, TurnOB, etc.) have @Entity annotations
- Domain entities stay clean for web compilation (no dart:ffi imports)
- Supports synchronous transactions for data consistency guarantees

### Repository Interface

All repositories extend `EntityRepository<T>`:

```dart
abstract class EntityRepository<T extends BaseEntity> {
  // CRUD Operations
  Future<T?> findByUuid(String uuid);        // Primary UUID lookup
  Future<T> getByUuid(String uuid);          // With exception
  @deprecated
  Future<T?> findById(int id);               // Legacy int lookup

  Future<List<T>> findAll();
  Future<T> save(T entity);                  // With lifecycle hooks

  Future<bool> deleteByUuid(String uuid);    // Primary delete
  @deprecated
  Future<bool> delete(int id);               // Legacy delete

  // Queries
  Future<List<T>> findUnsynced();            // For sync service
  Future<int> count();

  // Semantic Search
  Future<List<T>> semanticSearch(
    List<double> queryVector,
    {int limit = 10, double minSimilarity = 0.0}
  );
  Future<void> rebuildIndex(
    Future<List<double>?> Function(T) generateEmbedding
  );
}
```

---

## Semantic Search (Vector Embeddings)

### How It Works

Invocations can be embedded (converted to vectors) and searched by semantic similarity. This enables queries like:
- "Find all invocations where the LLM gave uncertain responses"
- "Find all STT invocations with similar acoustic characteristics"
- "Find turns where feedback was negative for similar reasons"

### Embedding Storage

- **Native**: Stored in ObjectBox with native HNSW indexing
- **Web**: Stored in IndexedDB, searched via pure Dart HNSW implementation
- **Database**: Embeddings stored alongside invocations (not separate table)

### Semantic Index Lifecycle

```dart
// 1. Generate embeddings for existing invocations
adapter.rebuildIndex((invocation) async {
  // LLM provider generates embedding from invocation content
  return await embeddingService.generate(invocation.output);
});

// 2. On new save, embedding is auto-generated
await invocationRepo.save(invocation);
// → Framework calls embeddingService if Embeddable
// → Stores embedding alongside entity

// 3. Search by semantic similarity
final results = await invocationRepo.semanticSearch(
  queryVector,
  limit: 10,
  minSimilarity: 0.7,
);
```

### Vector Types

Different component types have different embedding semantics:
- **STT Invocations**: Embeddings of transcribed text (acoustic+semantic)
- **LLM Invocations**: Embeddings of response text (semantic meaning)
- **TTS Invocations**: Embeddings of audio characteristics (prosody, voice)
- **ContextManager Invocations**: Embeddings of context state (what did the system know?)

Each component defines its own embedding strategy while the framework handles storage and search.

---

## Platform Targets

### Mobile (iOS, Android)
- **Storage**: ObjectBox (native SQLite-like performance)
- **Vector Search**: HNSW via ObjectBox native indexing
- **Sync**: Supabase
- **Blob Storage**: Firebase Cloud Storage (via Supabase integration)

### Web (Browser)
- **Storage**: IndexedDB (browser API)
- **Vector Search**: Pure Dart HNSW (no native libs required)
- **Sync**: Supabase with IndexedDB offline fallback
- **Blob Storage**: Supabase Storage (S3-compatible)

### Desktop (macOS, Windows, Linux)
- **Storage**: ObjectBox (native performance)
- **Vector Search**: HNSW via ObjectBox
- **Sync**: Supabase
- **Blob Storage**: Filesystem + Supabase sync

### All Platforms
Same codebase, same tests, platform-specific implementation isolated to:
- `lib/bootstrap/` - Platform detection and initialization
- `lib/persistence/objectbox/` - ObjectBox adapters (native only)
- `lib/persistence/indexeddb/` - IndexedDB adapters (web only)

---

## Data & Sync

### Offline-First
All platforms work completely offline:
- Local database (ObjectBox/IndexedDB) is source of truth
- Sync service pushes local changes when online
- Conflicts resolved via version numbers (AdaptationState) or last-write-wins

### Single-Device vs Multi-Device Sync

**Current (v1)**: Single device per user
- Supabase is backup/archive, not active sync
- Offline works completely, syncs when online

**Multi-Device (Capable, Implementation Incomplete)**: Same user across multiple clients

The architecture **enables** multi-device - Supabase provides the cloud backend, repositories support sync, adapters are stateless. But the implementation needs:

1. **Conflict Resolution** - If Device A and Device B both update AdaptationState simultaneously:
   - A sets threshold=0.8
   - B sets threshold=0.9
   - Which one is correct?

   Currently: `AdaptationState.version` handles single-device optimistic locking. Multi-device needs:
   - `lastModified: DateTime` on each update
   - A rule: "later timestamp wins" (last-write-wins)
   - Or a CRDT library for smart merging

2. **Subscription/Notification** - Device A saves → pushes to Supabase → Device B... doesn't know anything happened.
   - Could poll, but wasteful and latent
   - Supabase Realtime exists but isn't wired in
   - Needs subscription handler or periodic polling

3. **RLS Configuration** - The code assumes single user. Supabase requires Row Level Security:
   ```sql
   -- Device A's data should only be visible to Device A
   CREATE POLICY "Users can only access their own data"
   ON adaptation_state
   USING (auth.uid() = user_id);
   ```

4. **lastModified Field** - To know which update won:
   ```dart
   AdaptationState {
     data: {...},
     version: 1,  // Single-device only
     lastModified: DateTime.now(),  // Missing - needed for multi-device
     lastModifiedBy: String,  // Missing - which device?
   }
   ```

**To Enable Multi-Device (Minimal)**:
```dart
// 1. Add timestamp
AdaptationState.lastModified = DateTime.now()

// 2. Merge logic
if (remote.lastModified > local.lastModified) {
  // Remote is newer, use it
} else {
  // Keep local
}

// 3. Supabase RLS (config, not code)

// 4. Polling or subscribe
while (true) {
  await pullRemoteChanges();
  await Future.delayed(Duration(seconds: 5));
}
```

**Bottom line**: Supabase gives you 90%. Framework gives you 80%. You're missing 10% (conflict resolution code) + config (RLS).

### Sync Flow

```
Offline Changes
    ↓
findUnsynced() queries adapter
    ↓
SyncService posts to Supabase
    ↓
Remote updated
    ↓
Entities marked synchronized
    ↓
(Future: Device B polls/subscribes and pulls changes)
```

---

## External Integrations

### Supabase (Cloud Backend)
- **Purpose**: Remote backup, future multi-user/multi-device sync, RLS enforcement
- **Integration**: SyncService, AdaptationState versioning, RLS for team features
- **Failure Mode**: App continues offline, syncs when online
- **Cost**: Generous free tier, scales with data

### AI Services (Pluggable)
The architecture supports any AI service. Service selection is domain-logic (not architectural):
- **STT**: Whisper, local models, native frameworks
- **LLM**: Claude, Groq, OpenAI, local models, on-device
- **TTS**: Eleven Labs, Google Cloud TTS, native frameworks
- **Embeddings**: OpenAI, Cohere, open-source models

New adapters can be added without framework changes.

### Embedding Generation
- **Purpose**: Enable semantic search on invocations and turns
- **Service**: Any provider via EmbeddingService interface
- **Storage**: Embeddings stored in ObjectBox/IndexedDB with entities
- **On-Device**: Pure Dart HNSW allows offline semantic search (no API calls)

---

## Scale Assumptions

| Dimension | Assumption | Rationale |
|-----------|-----------|-----------|
| Users | Single user per device (v1) | Multi-user requires CRDT sync, not yet implemented |
| Data/User | <1GB per device | ObjectBox/IndexedDB support multi-GB datasets |
| Invocations/Turn | <100 | Typical conversation stays <50 invocations |
| Turns/Day | <10,000 | Reasonable voice interaction volume |
| Conversation History | <1 year | Can be archived/pruned for storage |
| Embedding Dimension | 1536 (OpenAI) or lower | Most HNSW implementations support this well |

### What Would Break Current Architecture
- **>100M edges** - Edgeable pattern needs optimization
- **Real-time multi-user <100ms latency** - Requires CRDT sync + WebSocket subscriptions
- **Geographic distribution** - Edge deployments need regional Supabase replicas
- **Offline-first with aggressive merging** - Version numbers sufficient for AdaptationState only

---

## Security & Privacy

### Data Sensitivity
- **Low**: Conversation metadata (timestamps, component names)
- **Medium**: Transcriptions, LLM responses (user content)
- **High**: User feedback, adaptation state (models user behavior)

### Access Control
Single-user by design. Team features would require:
- User authentication (Supabase Auth)
- Role-based access control (RBAC) via RLS
- Encryption at rest (SQLCipher for ObjectBox, encryption middleware for IndexedDB)

### Compliance
Default implementation has **no special security**. Applications requiring HIPAA, GDPR, etc. must add:
- Field-level encryption
- Audit logging
- Data retention policies
- PII scrubbing before Supabase sync

---

## Lifecycle & Bootstrap

### Initialization Order
```dart
1. setupEverythingStack() - Initialize adapters
   ├─ kIsWeb? → IndexedDB + adapters
   └─ Native? → ObjectBox + adapters

2. Register repositories in GetIt
   ├─ InvocationRepository<Invocation>
   ├─ FeedbackRepository
   ├─ TurnRepository
   └─ AdaptationStateRepository

3. Register services
   ├─ EmbeddingService (if semantic search enabled)
   ├─ SyncService (if Supabase enabled)
   └─ Custom services
```

### Platform Detection
```dart
if (kIsWeb) {
  // Web: IndexedDB
} else if (defaultTargetPlatform == TargetPlatform.android) {
  // Android: ObjectBox
} else if (defaultTargetPlatform == TargetPlatform.iOS) {
  // iOS: ObjectBox
} // etc. for macOS, Windows, Linux
```

---

## Extension Points

### Adding New Entities
1. Create domain entity extending `BaseEntity`
2. Create repository interface extending `EntityRepository<T>`
3. Add ObjectBox wrapper with @Entity annotations (if native support needed)
4. Implement IndexedDB adapter extending `BaseIndexedDBAdapter<T>`
5. Implement ObjectBox adapter extending `BaseObjectBoxAdapter<T, OB>`

### Adding New Patterns
1. Create mixin in `lib/patterns/`
2. Mix into entities that need it
3. Implement in both adapters if database-specific logic needed
4. Add tests to `test/services/` and `test/scenarios/`

### Adding New Services
1. Create service interface in `lib/services/`
2. Implement for each platform (if needed)
3. Register in bootstrap via GetIt
4. Inject into repositories via handlers or constructor

---

## Testing Strategy

### E2E Testing Approach

All tests are end-to-end. Real components, real services, real persistence.

E2E tests generate real Invocation logs that feed the learning system. The system learns from what it actually does, not mock behavior.

See TESTING.md for complete E2E patterns, platforms, and debugging.

---

## Why These Decisions?

See **DECISIONS.md** for the reasoning behind major architectural choices: UUID keys, adapter pattern, dual persistence, trainable mixins, Turn entities, type safety, execution fungibility, and infrastructure completeness.

DECISIONS.md explains the trade-offs that shaped this architecture.

---

## Documentation

- **README.md** - What is Everything Stack, current status, quick start
- **DECISIONS.md** - Why we chose this architecture (rationales and trade-offs)
- **PATTERNS.md** - How to build: entities, services, patterns, examples
- **TESTING.md** - How to test: E2E approach, platforms, debugging
- **.claude/CLAUDE.md** - Project initialization, permissions, current work, build commands
- **lib/patterns/README.md** - Pattern usage and integration guide
- **lib/bootstrap.dart** - Service initialization and platform detection
- **lib/persistence/README.md** - Adapter implementation details

---

**Last Updated**: December 26, 2025
**Status**: Current state architecture. For work in progress, blockers, and active development, see .claude/CLAUDE.md
