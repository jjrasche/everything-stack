# Narrative Architecture Integration Guide

## Overview

Integrate NarrativeThinker, NarrativeRetriever, and NarrativeCheckpoint into the bootstrap and Intent Engine pipeline.

## 1. Bootstrap Wiring

Add to `lib/bootstrap.dart` after EmbeddingQueueService initialization:

```dart
// Import statements (at top)
import 'domain/narrative_entry.dart';
import 'domain/narrative_repository.dart';
import 'persistence/objectbox/narrative_objectbox_adapter.dart';
import 'services/narrative_thinker.dart';
import 'services/narrative_retriever.dart';
import 'services/narrative_checkpoint.dart';

// Global variables (with other service globals)
late NarrativeRepository _narrativeRepo;
late NarrativeThinker _narrativeThinker;
late NarrativeRetriever _narrativeRetriever;
late NarrativeCheckpoint _narrativeCheckpoint;

// Getters (with other service getters)
NarrativeRepository get narrativeRepository => _narrativeRepo;
NarrativeThinker get narrativeThinker => _narrativeThinker;
NarrativeRetriever get narrativeRetriever => _narrativeRetriever;
NarrativeCheckpoint get narrativeCheckpoint => _narrativeCheckpoint;

// In initializeEverythingStack, after EmbeddingQueueService init:
// 11. Initialize NarrativeRepository
final narrativeAdapter = NarrativeObjectBoxAdapter(_persistenceFactory!.store);
_narrativeRepo = NarrativeRepository.production(adapter: narrativeAdapter);
print('NarrativeRepository initialized');

// 12. Initialize NarrativeThinker
_narrativeThinker = NarrativeThinker(
  narrativeRepo: _narrativeRepo,
  groqService: GroqService.instance,
);
print('NarrativeThinker initialized');

// 13. Initialize NarrativeRetriever
_narrativeRetriever = NarrativeRetriever(
  narrativeRepo: _narrativeRepo,
  embeddingService: EmbeddingService.instance,
);
print('NarrativeRetriever initialized');

// 14. Initialize NarrativeCheckpoint
_narrativeCheckpoint = NarrativeCheckpoint(
  narrativeRepo: _narrativeRepo,
  retriever: _narrativeRetriever,
  groqService: GroqService.instance,
);
print('NarrativeCheckpoint initialized');
```

## 2. Create NarrativeObjectBoxAdapter

Create `lib/persistence/objectbox/narrative_objectbox_adapter.dart`:

```dart
import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/narrative_entry.dart';

class NarrativeObjectBoxAdapter extends PersistenceAdapter<NarrativeEntry> {
  final Store store;

  NarrativeObjectBoxAdapter(this.store);

  @override
  Future<int> create(NarrativeEntry entity) async {
    final box = store.box<NarrativeEntry>();
    return box.put(entity);
  }

  @override
  Future<NarrativeEntry?> read(int id) async {
    final box = store.box<NarrativeEntry>();
    return box.get(id);
  }

  @override
  Future<void> update(NarrativeEntry entity) async {
    final box = store.box<NarrativeEntry>();
    box.put(entity);
  }

  @override
  Future<void> delete(int id) async {
    final box = store.box<NarrativeEntry>();
    box.remove(id);
  }

  @override
  Future<List<NarrativeEntry>> readAll() async {
    final box = store.box<NarrativeEntry>();
    return box.getAll();
  }

  @override
  Future<NarrativeEntry?> readByUuid(String uuid) async {
    final box = store.box<NarrativeEntry>();
    final query = box.query(NarrativeEntry_.uuid.equals(uuid)).build();
    final result = query.findFirst();
    query.close();
    return result;
  }

  @override
  Future<void> deleteByUuid(String uuid) async {
    final box = store.box<NarrativeEntry>();
    final query = box.query(NarrativeEntry_.uuid.equals(uuid)).build();
    final result = query.findFirst();
    query.close();
    if (result != null) {
      box.remove(result.id);
    }
  }
}
```

## 3. Intent Engine Integration

In your Intent Engine / Talker service, after classification:

```dart
// Get relevant narratives from NarrativeRetriever
final relevantNarratives = await narrativeRetriever.findRelevant(utterance);

// Format for prompt context
final narrativeContext = narrativeRetriever.formatForContext(relevantNarratives);

// Inject into Intent Engine prompt
final prompt = '''
User: $utterance

${narrativeContext}

// ... rest of Intent Engine prompt
''';
```

## 4. Narrative Thinker Integration

After Intent Engine completes classification:

```dart
// Extract narratives from turn
final newNarratives = await narrativeThinker.updateFromTurn(
  utterance: utterance,
  intentOutput: intentResult, // Full intent object with reasoning
  chatHistory: chatMessages,  // Recent messages for context
  previousNarratives: recentNarratives, // For deduplication
);

// Log what was learned
for (final entry in newNarratives) {
  logger.info('Narrative: ${entry.content} (${entry.scope})');
}
```

## 5. Training Checkpoint Integration

Trigger at time boundary or explicit user command:

```dart
// Trigger training
final delta = await narrativeCheckpoint.train();

// Show results to user
if (delta.hasChanges) {
  print('Training complete:');
  print('Added: ${delta.added.length}');
  print('Removed: ${delta.removed.length}');
  print('Promoted: ${delta.promoted.length}');
}

// Trainer observes deltas
await trainer.recordNarrativeDelta(delta);
```

## 5. Embedding Service Configuration

NarrativeRepository uses `EmbeddingService.instance` for semantic search. Configure at bootstrap:

```dart
// In bootstrap, pick ONE embedding provider:

// Option 1: Jina (if JINA_API_KEY set)
if (cfg.jinaApiKey != null) {
  EmbeddingService.instance = JinaEmbeddingService(apiKey: cfg.jinaApiKey);
}

// Option 2: Gemini (if GEMINI_API_KEY set)
else if (cfg.geminiApiKey != null) {
  EmbeddingService.instance = GeminiEmbeddingService(apiKey: cfg.geminiApiKey);
}

// Option 3: Local ONNX model (recommended for offline-first)
// else if (!kIsWeb) {
//   EmbeddingService.instance = OnnxEmbeddingService(modelPath: '...');
// }

// Default: NullEmbeddingService (embeddings disabled - semantic search unavailable)
```

**Key**: NarrativeRepository is agnostic about provider. Just inject whatever EmbeddingService is configured.

## 6. ObjectBox Model Update

Update `lib/objectbox.dart` to include `NarrativeEntry`:

```dart
import 'domain/narrative_entry.dart';

// In createStore function:
// Add NarrativeEntry to model
```

Run code generation:
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Architecture Summary

```
User Input
    ↓
[STT/Chat] → [Intent Engine]
    ↓
[NarrativeThinker] ← retrieves previous narratives
    ↓
Updates Session/Day (auto-saved)
    ↓
[NarrativeRetriever] → provides context for next turn
    ↓
[Training Checkpoint] (on boundary) ← observes user edits
    ↓
[Trainer] learns from deltas
```

### Data Flow

1. **Thinker**: utterance + intent + history → Groq → extract entries → save
2. **Retriever**: query → semantic search → top-5 relevant
3. **Checkpoint**: review Session/Day + refine Project/Life → deltas
4. **Trainer**: observes deltas, learns user intent distribution

### Scope Independence

- Session: Always created, resets on app close
- Day: Auto-creates at first entry after midnight
- Week: Auto-creates at first entry after Monday
- Project: User-created, persists until archived
- Life: Singleton, identity layer, never auto-reset

### Storage Pattern

Entries stored in ObjectBox with embedding vectors. Archival via soft delete (isArchived flag). Semantic search uses cosine similarity with configurable threshold (default 0.65).
