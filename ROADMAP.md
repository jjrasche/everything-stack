# Roadmap

Build order for everything-stack. Infrastructure first, then features.

## Constraints

- **Flutter**: 3.24.5 (pinned)
- **Platforms**: iOS, Android, Web for v1
- **File Handling**: Stream all files (no size threshold)
- **Tests**: Run on GitHub Actions, not locally
- **Deploy**: Firebase Hosting (web) + Firebase App Distribution (mobile)

---

## Phase 0: Infrastructure

**Goal**: CI/CD pipeline working. Governance loop enabled.

**Human must provide before this phase**:
- GitHub repository created
- Firebase project created
- Firebase service account JSON for CI

### 0.1 Minimal Flutter App
- [ ] Initialize Flutter project (3.24.5)
- [ ] Lock Flutter version via FVM
- [ ] Create minimal `lib/main.dart` (hello world)
- [ ] Create `.gitignore`
- [ ] Verify `flutter test` runs (even with no tests)

### 0.2 CI Pipeline
- [ ] Create `.github/workflows/ci.yml`
- [ ] Trigger on push/PR to any branch
- [ ] Setup Flutter on `ubuntu-latest`
- [ ] Run `flutter pub get`
- [ ] Run `flutter analyze`
- [ ] Run `flutter test`
- [ ] Verify workflow runs on push

### 0.3 CD Pipeline
- [ ] Create `.github/workflows/cd.yml`
- [ ] Trigger on merge to `main`
- [ ] Build web: `flutter build web`
- [ ] Deploy to Firebase Hosting
- [ ] Verify web app loads at Firebase URL

**Deliverable**: Push code -> CI runs tests -> Merge to main -> Web app deploys.

---

## Phase 1: Foundation

**Goal**: Core data model and local persistence.

### 1.1 Core Entities
- [ ] Implement `BaseEntity` abstract class
- [ ] Implement `Visibility` enum
- [ ] Implement `Note` entity (text-only)
- [ ] Add Isar annotations and generate schemas

### 1.2 Mixins
- [ ] Implement `Embeddable` mixin
- [ ] Implement `Temporal` mixin
- [ ] Implement `Taggable` mixin
- [ ] Apply mixins to Note entity

### 1.3 Repository Pattern
- [ ] Define abstract `Repository<T extends BaseEntity>`
- [ ] Implement `NoteRepository` with Isar
- [ ] Text search via Isar queries
- [ ] Reactive streams via `watch()`

### 1.4 Integration Tests
- [ ] Test CRUD operations
- [ ] Test text search
- [ ] Test persistence across restarts
- [ ] Tests run on GitHub Actions

**Deliverable**: Data layer working. Tests pass in CI.

---

## Phase 2: UI Foundation

**Goal**: Basic notes app UI on all platforms.

### 2.1 App Structure
- [ ] Setup MaterialApp with routing
- [ ] Create app theme (light mode)
- [ ] Navigation structure

### 2.2 Notes Feature
- [ ] Notes list screen
- [ ] Note detail/edit screen
- [ ] Create, update, delete flows
- [ ] Search bar with text search

### 2.3 State Management
- [ ] Setup BLoC for notes feature
- [ ] Wire repository to BLoC
- [ ] Reactive updates

### 2.4 E2E Tests
- [ ] BDD scenarios for note CRUD
- [ ] BDD scenarios for search
- [ ] Tests run on GitHub Actions

**Deliverable**: Working notes app. All local, no auth. Tests pass in CI.

---

## Phase 3: Auth

**Goal**: User authentication via Supabase.

**Human must provide before this phase**:
- Supabase project created
- Supabase URL and anon key in `.env`

### 3.1 Auth Service
- [ ] Configure Supabase client
- [ ] Implement signUp, signIn, signOut
- [ ] Auth state stream
- [ ] Secure storage for tokens

### 3.2 Auth UI
- [ ] Login screen
- [ ] Signup screen
- [ ] Auth guard for routes

### 3.3 Integration
- [ ] Set ownerId on note creation
- [ ] Filter notes by current user
- [ ] Clear local data on logout

**Deliverable**: Users can sign up, log in, log out. Notes scoped to user.

---

## Phase 4: Cloud Sync

**Goal**: Notes sync between local and Supabase.

**Human must provide before this phase**:
- Supabase tables created (notes, edges)
- RLS policies applied

### 4.1 Supabase Schema
- [ ] Create `notes` table
- [ ] Add RLS policies
- [ ] Create indexes

### 4.2 Sync Service
- [ ] Queue changes locally
- [ ] Push queue when online
- [ ] Pull changes from Supabase
- [ ] Last-write-wins conflict resolution

### 4.3 Connectivity
- [ ] Detect online/offline
- [ ] Auto-sync when coming online
- [ ] Show sync status in UI

**Deliverable**: Notes sync across devices. Works offline.

---

## Phase 5: Semantic Search

**Goal**: Search notes semantically using embeddings.

**Human must provide before this phase**:
- Jina AI API key in `.env`

### 5.1 Embedding Service
- [ ] Jina AI API integration
- [ ] Batch embedding generation
- [ ] Rate limiting and retries

### 5.2 Embedding Generation
- [ ] Generate on note save
- [ ] Queue if offline
- [ ] Migration for existing notes

### 5.3 Vector Search
- [ ] Cosine similarity implementation
- [ ] `semanticSearch` in repository
- [ ] Top K results

### 5.4 Search UI
- [ ] Toggle between text/semantic search
- [ ] Display results

**Deliverable**: "Find notes about gardens" returns relevant results.

---

## Phase 6: Media Support

**Goal**: Images, audio, video with transcription.

**Human must provide before this phase**:
- Transcription API key in `.env`

### 6.1 Media Capture
- [ ] Image capture/picker
- [ ] Audio recording
- [ ] Video recording
- [ ] Stream all file bytes

### 6.2 Media Display
- [ ] Image viewer
- [ ] Audio player
- [ ] Video player

### 6.3 Transcription
- [ ] API integration
- [ ] Queue transcription jobs
- [ ] Update embedding after transcription

### 6.4 Media Sync
- [ ] Stream bytes to Supabase
- [ ] Queue for WiFi only
- [ ] Progressive sync

**Deliverable**: Capture and search media. Voice memos transcribed and searchable.

---

## Phase 7: Sharing

**Goal**: Share notes with other users.

### 7.1 Share Management
- [ ] Add users to sharedWith
- [ ] Update RLS for shared access
- [ ] Remove share

### 7.2 Share UI
- [ ] Share dialog
- [ ] Show shared users
- [ ] "Shared with me" view

### 7.3 Real-time
- [ ] Supabase Realtime subscriptions
- [ ] Live updates on shared notes

**Deliverable**: Share notes. Real-time updates.

---

## Phase 8: Mobile Distribution

**Goal**: iOS and Android on Firebase App Distribution.

### 8.1 iOS Build
- [ ] Configure signing
- [ ] Build for distribution
- [ ] CD deploys to Firebase App Distribution

### 8.2 Android Build
- [ ] Configure signing
- [ ] Build APK/AAB
- [ ] CD deploys to Firebase App Distribution

**Deliverable**: Mobile apps available for testing.

---

## Phase 9: Polish

**Goal**: Production-ready quality.

### 9.1 Error Handling
- [ ] User-friendly error messages
- [ ] Retry logic
- [ ] Offline indicators

### 9.2 Performance
- [ ] Lazy loading
- [ ] Pagination
- [ ] Memory optimization

### 9.3 Test Coverage
- [ ] >80% coverage
- [ ] All BDD scenarios passing

**Deliverable**: Ready for production.

---

## Success Criteria

v1 is complete when:

1. Create text note offline on phone, see it on web when online
2. Search "idea about gardens" finds relevant voice memo
3. Share note with another user, they see it instantly
4. Works on iOS, Android, Web
5. All BDD scenarios pass on GitHub Actions
6. Template documented for developers to clone
