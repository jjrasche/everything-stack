/// Web platform persistence initialization (IndexedDB)
///
/// This file is only imported on web platform.
/// It creates IndexedDB-based adapters for all repositories.
library;

import 'package:get_it/get_it.dart';

import '../core/invocation_repository.dart';
import '../core/invocation.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback_repository.dart';
import '../core/event_repository.dart';
import '../core/enrichment_queue_repository.dart';
import '../core/trial_repository.dart';
import '../core/chunk_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../domain/audio_file.dart';
import '../domain/atomic_insight.dart';
import '../persistence/indexeddb/invocation_indexeddb_adapter.dart';
import '../persistence/indexeddb/chunk_indexeddb_adapter.dart';
import '../persistence/indexeddb/adaptation_state_indexeddb_adapter.dart';
import '../persistence/indexeddb/feedback_indexeddb_adapter.dart';
import '../persistence/indexeddb/event_indexeddb_adapter.dart';
import '../persistence/indexeddb/enrichment_queue_indexeddb_adapter.dart';
import '../persistence/indexeddb/trial_indexeddb_adapter.dart';
import '../persistence/indexeddb/audio_file_indexeddb_adapter.dart';
import '../persistence/indexeddb/atomic_insight_indexeddb_adapter.dart';
import '../persistence/indexeddb/prompt_version_indexeddb_adapter.dart';
import '../persistence/indexeddb/proposition_indexeddb_adapter.dart';
import '../domain/prompt_version.dart';
import '../domain/proposition.dart';
import 'indexeddb_factory.dart';

/// Initialize persistence layer for web platform using IndexedDB.
///
/// Creates and registers all repository adapters backed by IndexedDB.
Future<void> initializePersistence(GetIt getIt) async {
  print('🔍 [persistence_WEB] Function called! (IndexedDB version)');
  print('   Passed getIt: ${getIt.hashCode}');
  print('   GetIt.instance: ${GetIt.instance.hashCode}');

  final db = await openIndexedDB();

  final invocationAdapter = InvocationIndexedDBAdapter(db);
  final adaptationStateAdapter = AdaptationStateIndexedDBAdapter(db);
  final feedbackAdapter = FeedbackIndexedDBAdapter(db);
  final trialAdapter = TrialIndexedDBAdapter(db);

  getIt.registerSingleton<InvocationRepository<Invocation>>(
    invocationAdapter,
  );
  getIt.registerSingleton<AdaptationStateRepository>(
    adaptationStateAdapter,
  );
  getIt.registerSingleton<FeedbackRepository>(
    feedbackAdapter,
  );
  getIt.registerSingleton<TrialRepository>(
    trialAdapter,
  );

  final enrichmentQueueAdapter = EnrichmentQueueIndexedDBAdapter(db);
  getIt.registerSingleton<EnrichmentQueueAdapter>(enrichmentQueueAdapter);

  // Register stub ChunkRepository (semantic search disabled on web)
  final chunkAdapter = ChunkObjectBoxAdapter(null);
  getIt.registerSingleton<ChunkRepository>(chunkAdapter);

  // Register AudioFile adapter (repository created later after EmbeddingService is ready)
  // Using PersistenceAdapter<AudioFile> for platform-agnostic access
  final audioFileAdapter = AudioFileIndexedDBAdapter(db);
  getIt.registerSingleton<PersistenceAdapter<AudioFile>>(audioFileAdapter);

  final atomicInsightAdapter = AtomicInsightIndexedDBAdapter(db);
  getIt.registerSingleton<PersistenceAdapter<AtomicInsight>>(atomicInsightAdapter);

  final promptVersionAdapter = PromptVersionIndexedDBAdapter(db);
  getIt.registerSingleton<PersistenceAdapter<PromptVersion>>(promptVersionAdapter);

  final propositionAdapter = PropositionIndexedDBAdapter(db);
  getIt.registerSingleton<PersistenceAdapter<Proposition>>(propositionAdapter);
}

/// Create EventRepository for web platform using IndexedDB.
Future<EventRepository> createEventRepository() async {
  final db = await openIndexedDB();
  return EventIndexedDBAdapter(db);
}

/// No-op disposal for web (IndexedDB cleanup handled by browser).
void disposePersistence(GetIt getIt) {
  // IndexedDB cleanup is handled by the browser
}
