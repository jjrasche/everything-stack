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
  - `eventId: String` - Links to Event (what triggered this?)
  - `componentType: String` - Which component: 'stt', 'llm', 'tts', 'context_selector'
  - `implementer: String?` - Which implementation ('groq', 'deepgram', etc.)
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

### Feedback
**Purpose**: Records user feedback on an invocation

Feedback enables day-one trainability. Every invocation can be fed back on.

- **Fields**:
  - `invocationId: String` - Which invocation this feedback is about
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
  - `trainFromFeedback(invocation, feedback)` - Train from feedback on an invocation
  - Can be mixed into any component
- **Used By**: All trainable components (STT, LLM, TTS, ContextSelector, etc.)
- **Notes**: Generic mixin providing shared training interface. Feedback is collected at invocation level, training happens at component level, adaptation state stores learned changes.

### Embeddable
**Enables**: Semantic search via vector embeddings
- **Methods**:
  - `generateEmbedding(text)` - Create vector from text
  - `updateEmbedding(vector)` - Store vector
  - `semanticSearch(queryVector)` - Find similar entities
- **Used By**: Invocation (search by semantic similarity)
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
  Event, Invocation, Feedback, AdaptationState (pure Dart, no decorators)
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
  // - findByContextType(componentType)
  // - findByIds(List<String>)
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

### Cross-Platform File Architecture

**CRITICAL CONSTRAINT**: Domain entities CANNOT have platform-specific decorators (e.g., ObjectBox `@Entity`, `@Id`, `@Property`) because they must compile for both native and web platforms.

#### Why This Matters

Web compilation fails if domain entity files import `package:objectbox/objectbox.dart`:
- ObjectBox depends on `dart:ffi` (Foreign Function Interface)
- `dart:ffi` does not exist on web platform
- Any file importing ObjectBox cannot be compiled to web

#### The Solution: Wrapper Pattern

All ObjectBox decorators live on **wrapper classes** in `lib/persistence/objectbox/wrappers/`:

```
Domain Entity (Pure Dart)
  ↓
lib/tools/regulation/entities/person.dart
  - NO imports of objectbox
  - NO @Entity, @Id, @Property decorators
  - Works on ALL platforms (native + web)

Wrapper Class (ObjectBox-Specific)
  ↓
lib/persistence/objectbox/wrappers/person_ob.dart
  - Imports package:objectbox/objectbox.dart
  - Has ALL @Entity, @Id, @Property decorators
  - Conversion methods: fromPerson(Person) / toPerson()
  - ONLY compiled for native platforms
```

#### File Organization Rules

1. **Domain entities** (`lib/tools/*/entities/*.dart`, `lib/domain/*.dart`):
   - Pure Dart classes extending BaseEntity
   - NO ObjectBox imports or decorators
   - NO conditional imports (e.g., `if (dart.library.io)`)
   - Compile for ALL platforms (native + web)

2. **ObjectBox wrappers** (`lib/persistence/objectbox/wrappers/*_ob.dart`):
   - Import `package:objectbox/objectbox.dart`
   - ALL ObjectBox decorators go here
   - Conversion methods to/from domain entity
   - ONLY compiled for native platforms (excluded from web builds)

3. **ObjectBox adapters** (`lib/persistence/objectbox/*_objectbox_adapter.dart`):
   - Extend `BaseObjectBoxAdapter<DomainEntity, WrapperOB>`
   - Implement `toOB(entity)` and `fromOB(ob)` conversion
   - ONLY compiled for native platforms

4. **IndexedDB adapters** (`lib/tools/*/adapters/*_indexeddb_adapter.dart`):
   - Extend `BaseIndexedDBAdapter<DomainEntity>`
   - Import domain entity directly (no wrappers needed)
   - ONLY compiled for web platform

5. **Adapter factories** (`lib/tools/*/repositories/*_adapter_native.dart`, `*_adapter_web.dart`):
   - Use conditional imports to select correct adapter:
     ```dart
     import 'adapter_native.dart' if (dart.library.html) 'adapter_web.dart';
     ```
   - Native factory returns ObjectBox adapter
   - Web factory returns IndexedDB adapter

#### Example: Person Entity

**Domain Entity** (Pure Dart):
```dart
// lib/tools/regulation/entities/person.dart
import '../../../core/base_entity.dart';

class Person extends BaseEntity {
  String name;
  String? role;
  String? notes;

  Person({required this.name, this.role, this.notes});
}
```

**ObjectBox Wrapper** (Native Only):
```dart
// lib/persistence/objectbox/wrappers/person_ob.dart
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/regulation/entities/person.dart';

@Entity()
class PersonOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  String name;
  String? role;
  String? notes;

  PersonOB({required this.name, this.role, this.notes});

  factory PersonOB.fromPerson(Person person) => PersonOB(
    name: person.name,
    role: person.role,
    notes: person.notes,
  )..uuid = person.uuid;

  Person toPerson() {
    final person = Person(name: name, role: role, notes: notes);
    person.uuid = uuid;
    return person;
  }
}
```

**ObjectBox Adapter** (Native Only):
```dart
// lib/persistence/objectbox/person_objectbox_adapter.dart
class PersonObjectBoxAdapter extends BaseObjectBoxAdapter<Person, PersonOB> {
  @override
  PersonOB toOB(Person entity) => PersonOB.fromPerson(entity);

  @override
  Person fromOB(PersonOB ob) => ob.toPerson();
}
```

#### What NOT to Do

❌ **NEVER** add ObjectBox decorators directly to domain entities:
```dart
// lib/tools/regulation/entities/person.dart
import 'package:objectbox/objectbox.dart'; // ❌ BREAKS WEB COMPILATION

@Entity() // ❌ BREAKS WEB COMPILATION
class Person extends BaseEntity {
  @Id() // ❌ BREAKS WEB COMPILATION
  int id = 0;
  // ...
}
```

❌ **NEVER** use conditional imports in domain entities:
```dart
// lib/tools/regulation/entities/person.dart
import 'person_stub.dart' if (dart.library.io) 'person.dart'; // ❌ UNNECESSARY COMPLEXITY
```

✅ **ALWAYS** keep domain entities pure Dart:
```dart
// lib/tools/regulation/entities/person.dart
import '../../../core/base_entity.dart'; // ✅ Pure Dart

class Person extends BaseEntity {
  String name; // ✅ No decorators
  // ...
}
```

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
| Invocations/Event | <10 | Typical event triggers <10 invocations |
| Events/Day | <10,000 | Reasonable voice interaction volume |
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

See **DECISIONS.md** for the reasoning behind major architectural choices: UUID keys, adapter pattern, dual persistence, trainable mixins, type safety, execution fungibility, and infrastructure completeness.

DECISIONS.md explains the trade-offs that shaped this architecture.

---

## Documentation

- **README.md** - What is Everything Stack, current status, quick start
- **DECISIONS.md** - Why we chose this architecture (rationales and trade-offs)
- **PATTERNS.md** - How to build: entities, services, patterns, examples
- **TESTING.md** - How to test: E2E approach, platforms, debugging
- **docs/DEVELOPMENT.md** - Build details, Rust/FFI, debug server, dependency management
- **.claude/CLAUDE.md** - Project definition, permissions, architecture constraints

---

## Distribution Model

**Current approach:** Template repository (clone and fork). Maintain as fork to pull upstream infrastructure updates.

**Future evolution:** Extract stable infrastructure to a package when:
- Core infrastructure stabilizes (rare breaking changes)
- Multiple apps exist and benefit from shared updates
- Version management becomes necessary

---

## Future Considerations

### Memory Architecture Layers

Four distinct memory systems forming a pipeline from ephemeral context to persistent knowledge:

1. **Session Continuity Memory (Working Context)** - The "RAM"
   - Rolling, prioritized, append-only observation log of current session
   - Source-agnostic: conversation turns, articles, lyrics, overheard audio, any episodic input
   - NOT per-request context fetching. Sticky context that grows within a session
   - Two background processes (inspired by Mastra Observational Memory):
     - **Observer**: compresses raw input into dated, priority-tagged observations
     - **Reflector**: restructures observations when they exceed token threshold,
       combining related items and removing superseded information
   - Temporal anchoring: observation date, referenced date, relative offset
   - Stable prefix enables prompt caching (4-10x cost reduction on cached tokens)
   - Extraction point: atomic insights are extracted FROM this context, not from raw input
   - Scope: current ambient session (not tied to a single chat, spans all interactions)
   - Storage: ephemeral (in-memory), but observations persist until session ends
   - Research: Mastra OM (94.87% LongMemEval), Mem0 async refresh pattern
   - Status: **concept, not yet designed or implemented**

2. **AtomicInsight (Semantic Memory)** - Long-term facts (the "database")
   - Persistent knowledge extracted from session continuity memory
   - Format: "[Fact]. Because [reason]."
   - Storage: database with embeddings for semantic search
   - Turn-by-turn extraction with deduplication (threshold: 0.7 cosine similarity)
   - Entity extraction as second pass (statistical/semantic, not LLM-based)
   - Consolidation: L0 (session) → L1 (week) → L2 (project/life) via emergent clustering
   - Hierarchy: domain tags (~10-20) and category tags (~50-200) enable reduced search space
   - Graph layer: entity resolution creates edges (insight↔entity, entity↔entity)
   - Inferred relations: semantic edges ("prefers", "because of") from context
   - Status: **extraction pipeline complete, consolidation/entity/graph not yet implemented**

3. **NarrativeEntry (Identity Memory)** - Who user is (deferred)
   - Identity, goals, values evolution
   - Scope: day -> week -> project -> life
   - Research: Amazon Bedrock AgentCore episodic memory, Mem0 preference/identity models

4. **MomentState (Emotional Context)** - Real-time affect (deferred)
   - Conversational posture, current focus/topic, engagement level
   - Inputs: voice prosody + emotion analysis + recent turns
   - Research: multi-modal emotion recognition, Hume AI empathic voice

### Memory Pipeline Flow

```
Episodic Input (songs, articles, conversations, any text)
    ↓
Session Continuity Memory (rolling prioritized context, sticky, append-only)
    ↓ Observer compresses, Reflector restructures
    ↓ extraction happens HERE
AtomicInsight Extraction (L0 session/day insights)
    ↓ second pass
Entity Extraction + Resolution (statistical, human-in-the-loop training)
    ↓ creates edges
Edge Creation (insight↔entity, entity↔entity)
    ↓ background batch
Consolidation (L0→L1→L2, emergent domain/category tags)
    ↓ enables
Hierarchical Retrieval (domain routing → category → specific insights + graph traversal)
```

### Entity Model in Memory

- Entities get ONE embedding (canonical description), not chunks
- Purpose: entity resolution (match new mentions against existing entities)
- Entities are reference points at the edge of semantic space, not searchable content
- Edge types: `mentions` (insight->entity), `relates_to` (entity<->entity),
  `parent_of` (L1->L0 consolidation provenance), `inferred` (semantic relations)

#### Entity Resolution Pipeline (No LLM Calls)

Based on Fellegi-Sunter framework: three-way decision (auto-merge, auto-separate, ask user).

Steps for each new entity mention:
1. **Blocking** (candidate generation): LSH over entity name embeddings OR phonetic keys
   to avoid O(n) comparison against all existing entities. Keep recall high, cut quadratic cost.
   At 1000 entities this is optional. At 50,000 it is mandatory.
2. **Feature computation** on candidate pairs:
   - String similarity (token overlap, edit distance)
   - Embedding cosine similarity (entity description embeddings)
   - Structural signals (shared graph neighbors, relation compatibility)
   - Temporal consistency (do two mentions plausibly co-refer at the same time?)
3. **Three-zone thresholding**:
   - Above high threshold -> auto-merge (conservative: bias toward low false-merges,
     because a wrong merge corrupts the graph and cascades into bad multi-hop retrieval)
   - Below low threshold -> auto-separate (new entity)
   - Between thresholds -> queue for human review in UI (tap-to-confirm)
4. **Active learning**: user confirmations train the matcher. Use entropy-based selection
   to pick the most informative pairs to surface. Keep a durable set of confirmed
   merges/splits as calibration data.

Implementation order: start with embedding similarity + two fixed thresholds.
Add blocking when entity count exceeds ~5000. Add active learning when enough
human judgments accumulate (~100+ decisions).

#### Bi-Temporal Entity Modeling

Steal from Zep/Graphiti. Each entity and relation carries two timelines:
- **System timeline**: `createdAt` / `expiredAt` (when the system learned or retired it)
- **Validity timeline**: `validFrom` / `validUntil` (when the fact was actually true)

Example: "I worked at Company X" -> validFrom=2020, validUntil=2023, createdAt=2026-02-16.
"I now work at Company Y" -> creates new entity relation, sets validUntil on old one.

This enables time-aware retrieval ("where did I work in 2021?") and retroactive
corrections without rewriting history. Treat "rename" as a new alias row, not a mutation.

Action: add `validFrom: DateTime?` and `validUntil: DateTime?` to BaseEntity or as an
opt-in mixin (like Embeddable). Decision deferred until Entity implementation phase.

### Consolidated Insight Provenance

- L0 insights archived (not deleted) after consolidation into L1
- Provenance tracked via `parent_of` edges (L1 -> source L0s)
- Enables reprocessing if consolidation algorithm improves
- Rare episodic recall: sometimes the specific detail matters, not the abstraction

### Hybrid Retrieval

Two-stage architecture validated across Zep, H-MEM, SimpleMem, GraphRAG, RAPTOR:

**Stage A: High Recall, Cheap (candidate generation)**
1. Domain/category routing narrows semantic search space (hierarchy descent)
2. Semantic ANN within matched categories (HNSW, 8-12ms)
3. Graph traversal expands from seed entities (1-2 hops, bounded)
4. Fallback: if hierarchical results are sparse (<3 candidates), run unfiltered
   semantic search. Hierarchy fragmentation silently kills recall without this.

**Stage B: Precision (reranking + context construction)**
1. Merge unique candidates from semantic + graph paths
2. Score fusion via RRF (Reciprocal Rank Fusion) as default:
   `score(d) = sum(1 / (k + rank_r(d)))` across ranked lists
   Parameter-light, no training data needed, works out of the box.
3. Graduate to learned convex combination (`alpha * semantic + (1-alpha) * graph`)
   when enough retrieval judgments accumulate from human-in-the-loop confirmations.
4. Context construction: summaries for L1/L2, raw content for L0 when detail needed.

**Score Fusion Implementation Order:**
- Phase 1: RRF only. No training. Ship it.
- Phase 2: Log retrieval results + user feedback as calibration data.
- Phase 3: Learn alpha (single scalar) via logistic regression over feature vector
  (cosine similarity, BM25, graph hop distance, recency, entity-type match).

**Query-Adaptive Traversal Depth:**
- Current `EdgeRepository.traverse()` takes fixed depth 1-3. No neighbor cap.
- Action: add `maxNeighborsPerHop` parameter to `traverse()` to prevent hub blowup.
  High-degree nodes (e.g., "Flutter" entity with 200 edges) explode BFS without caps.
- Action: add query complexity estimator (entity count + keyword count in query).
  Simple factual queries -> 1-hop. Multi-entity or reasoning queries -> 2-3 hops.
  SimpleMem validates this adaptive approach.

**Known Failure Modes (design around these):**
- Entity resolution errors cascade into graph traversal. Mitigated by conservative
  merge thresholds (see Entity Resolution Pipeline above).
- Hub bias in BFS. Mitigated by `maxNeighborsPerHop` cap, sort neighbors by salience.
- Hierarchy fragmentation drops recall. Mitigated by unfiltered fallback.
- Summarization errors lose detail. Mitigated by retaining L0 provenance
  and fetching raw insights when L1/L2 summaries are ambiguous.

**Benchmarks for validation:**
- Zep: 71.2% vs 60.2% baseline (LongMemEval), 1.6k vs 115k context tokens
- H-MEM: +14.98 F1 over flat, +21.25 multi-hop, <100ms vs 400ms+ at scale
- SimpleMem: +26.4% F1 with consolidation, large token usage reduction
- Target: measure on exported golden conversations once retrieval pipeline exists

**Research reference:** `docs/RESEARCH_HYBRID_RETRIEVAL.md` for full literature survey

---

## Workflows (Phase 5D+)

Automated grouping of tasks with conditional logic and decision points. Inherently trainable.

```
Workflow = Sequence of Tasks + Decision Logic + Trainable Aspects
```

### Integration with Coordinator
- Workflows appear as tools in ToolSelector
- LLM can select individual tasks OR `workflow.invoke_workflow_name`
- Each task in workflow creates an Invocation (same as individual tool)
- Conditional branches log as `workflow_decision` invocations
- Feedback on workflow success/failure trains future selection

### Trainable Aspects
- Task ordering (feedback: "too slow" -> parallelize)
- Task selection (feedback: "didn't need this task" -> adjust conditional)
- Conditional thresholds (feedback: "send agenda for longer meetings" -> adjust threshold)
- LLM tool selection (feedback: "wrong workflow" -> lower confidence)

Workflows improve through user feedback only, no autonomous self-training.

---

**Last Updated**: February 14, 2026
