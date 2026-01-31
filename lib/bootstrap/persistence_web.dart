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
import '../persistence/indexeddb/invocation_indexeddb_adapter.dart';
import '../persistence/indexeddb/chunk_indexeddb_adapter.dart';
import '../persistence/indexeddb/adaptation_state_indexeddb_adapter.dart';
import '../persistence/indexeddb/feedback_indexeddb_adapter.dart';
import '../persistence/indexeddb/event_indexeddb_adapter.dart';
import '../persistence/indexeddb/enrichment_queue_indexeddb_adapter.dart';
import '../persistence/indexeddb/trial_indexeddb_adapter.dart';
import 'indexeddb_factory.dart';

/// Initialize persistence layer for web platform using IndexedDB.
///
/// Creates and registers all repository adapters backed by IndexedDB.
Future<void> initializePersistence(GetIt getIt) async {
  print('🔍 [persistence_WEB] Function called! (IndexedDB version)');
  print('   Passed getIt: ${getIt.hashCode}');
  print('   GetIt.instance: ${GetIt.instance.hashCode}');

  final db = await openIndexedDB();

  // Create and register adapters
  final invocationAdapter = InvocationIndexedDBAdapter(db);
  final adaptationStateAdapter = AdaptationStateIndexedDBAdapter(db);
  final feedbackAdapter = FeedbackIndexedDBAdapter(db);
  final trialAdapter = TrialIndexedDBAdapter(db);

  // Register repositories in GetIt
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

  // Create and register EnrichmentQueue adapter
  final enrichmentQueueAdapter = EnrichmentQueueIndexedDBAdapter(db);
  getIt.registerSingleton<EnrichmentQueueAdapter>(enrichmentQueueAdapter);

  // Register stub ChunkRepository (semantic search disabled on web)
  final chunkAdapter = ChunkObjectBoxAdapter(null);
  getIt.registerSingleton<ChunkRepository>(chunkAdapter);
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
