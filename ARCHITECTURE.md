# Architecture

## Non-Negotiable Principles

These principles govern all architectural decisions. They are not suggestions.

**Universal Platform Support:** Android, iOS, macOS, Windows, Linux, Web. ALL platforms are first-class. Not "native-first with web as afterthought." If a platform isn't fully supported, the template is incomplete.

**Infrastructure Completeness:** If ANY application might need a feature, it's in the template. Authentication, persistence, file storage, semantic search, sync, offline-first - all solved. Complexity is a feature, not a bug. It's paid once here, not N times across applications.

**No Architectural Decisions for Domain Developers:** Developers (human or AI) never choose between ObjectBox vs Drift vs Isar. That decision is made. They configure domain entities and write business logic.

**When to Add vs Remove:**
- **Add:** Any infrastructure pattern that 2+ applications might need
- **Remove:** Never remove platform support or infrastructure capability to "simplify"
- **Question:** If you're asking "do we really need X?" - the answer is probably yes

## Stack

| Layer | Choice |
|-------|--------|
| Language | Dart |
| Framework | Flutter (iOS, Android, Web, macOS, Windows, Linux) |
| Local DB | ObjectBox (native) + IndexedDB (web) |
| Cloud DB | Supabase (Postgres + Auth + Realtime) |
| Vector Search | ObjectBox @HnswIndex (native) + pure Dart HNSW (web) |
| Embeddings | Jina AI API |
| Transcription | API (Deepgram or similar) |
| CI | GitHub Actions |
| CD | Firebase App Distribution (mobile) + Firebase Hosting (web) |

## CI/CD Infrastructure

Infrastructure must exist before feature development. The governance loop cannot run without it.

### GitHub Actions CI

**File**: `.github/workflows/ci.yml`

**Triggers**: Push or PR to any branch

**What it does**:
1. Checkout code
2. Setup Flutter (pinned version)
3. Run `flutter pub get`
4. Run `flutter analyze`
5. Run `flutter test`
6. Report results to PR

**Runner**: `ubuntu-latest` (Linux)

Tests run remotely on GitHub Actions, not locally. Local development is for writing code; CI validates it.

### GitHub Actions CD

**File**: `.github/workflows/cd.yml`

**Triggers**: Merge to `main` branch

**What it does**:
1. Build web: `flutter build web`
2. Deploy web to Firebase Hosting
3. Build Android: `flutter build apk` (or app bundle)
4. Deploy Android to Firebase App Distribution
5. Build iOS: `flutter build ios` (requires macOS runner)
6. Deploy iOS to Firebase App Distribution

**Runners**:
- Web/Android: `ubuntu-latest`
- iOS: `macos-latest`

### Required Secrets (GitHub)

```
FIREBASE_SERVICE_ACCOUNT     # Firebase CI/CD authentication
FIREBASE_PROJECT_ID          # Firebase project identifier
```

## Platforms

iOS, Android, Web for v1. Desktop (macOS, Windows, Linux) for v2.

## Auth

Supabase Auth. Email/password. User creates account, gets isolated data.

## Data Model

### BaseEntity

```dart
abstract class BaseEntity {
  String id;
  DateTime createdAt;
  DateTime updatedAt;
  String ownerId;
  List<String> sharedWith;
  Visibility visibility; // private, shared, public
}
```

### Note Entity

```dart
class Note extends BaseEntity with Embeddable, Temporal, Taggable {
  String? text;
  Uint8List? bytes;
  String? mimeType;
  String? fileName;
  String? transcription;
  List<String> tags;
  DateTime? dueAt;
  DateTime? remindAt;
  Float32List? embedding;

  @override
  String toEmbeddingInput() => text ?? transcription ?? '';
}
```

### Mixins

**Embeddable**: `embedding` field + `toEmbeddingInput()` override.

**Temporal**: `dueAt`, `remindAt` for time-based features.

**Taggable**: `List<String> tags` for categorization.

**Versionable** (v2): Change history.

### Edges

```dart
class Edge {
  String id;
  String sourceType;
  String sourceId;
  String targetType;
  String targetId;
  String edgeType;
  String? createdBy; // 'user' or 'ai'
  DateTime createdAt;
}
```

## Persistence

**Native (iOS, Android, macOS, Windows, Linux):** ObjectBox. High-performance, offline-first, native vector search via @HnswIndex.

**Web:** IndexedDB (via idb_shim). Persists to browser storage. Vector search via pure Dart HNSW implementation.

**Remote:** Supabase. Sync when online. Metadata immediate, blobs queued.

**Abstraction:** Platform-specific adapters implement common interfaces. Domain code doesn't know which persistence layer it's using.

**Files**: All file data stored as bytes in entity fields. Stream all files when reading/writing to avoid memory issues. This applies to every file regardless of size - there is no threshold.

## File Streaming

All file I/O must be streamed. Do not load entire files into memory.

**Reading**: Stream bytes from ObjectBox/IndexedDB/Supabase in chunks.

**Writing**: Stream bytes to ObjectBox/IndexedDB/Supabase in chunks.

**Why**: Consistent behavior regardless of file size. No need to distinguish "large" vs "small" files.

## Row Level Security

```sql
CREATE POLICY "own_notes" ON notes
  FOR ALL USING (auth.uid() = owner_id);

CREATE POLICY "shared_notes" ON notes
  FOR SELECT USING (auth.uid() = ANY(shared_with));
```

## Search

**Text search**: ObjectBox queries (native) / IndexedDB filtering (web). Works offline.

**Semantic search**: Embeddings via Jina AI API. Local similarity search via ObjectBox @HnswIndex (native) or pure Dart HNSW (web).

## Testing Strategy

| Phase Type | Where Tests Run | What Gets Tested |
|------------|-----------------|------------------|
| Infrastructure | GitHub Actions | Pipeline itself succeeds |
| Data Layer | GitHub Actions | Integration tests (repository CRUD, search) |
| UI | GitHub Actions | E2E tests (BDD scenarios) |
| Sync | GitHub Actions | E2E tests with mocked network |

Tests always run on GitHub Actions. Local runs are optional for debugging.

## Project Structure

```
lib/
  main.dart
  app.dart
  core/
    entities/
    mixins/
    repositories/
    services/
  features/
    notes/
    search/
    auth/
    settings/
test/
  integration/
  e2e/
.github/
  workflows/
    ci.yml
    cd.yml
```

## External Services

These require human setup (Claude cannot create accounts):

| Service | Purpose | Credentials Needed |
|---------|---------|-------------------|
| GitHub | Code hosting, CI/CD | Repo access |
| Supabase | Auth, database, realtime | URL, anon key, service role key |
| Firebase | Hosting, app distribution | Project ID, service account |
| Jina AI | Embeddings | API key |
| Deepgram (or similar) | Transcription | API key |

All credentials go in `.env` (local) and GitHub Secrets (CI/CD).
