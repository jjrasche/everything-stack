/// Native platform persistence initialization (ObjectBox)
///
/// This file is only imported on native platforms (Android, iOS, macOS, Windows, Linux).
/// It creates ObjectBox-based adapters for all repositories.
library;

import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';

import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback_repository.dart';
import '../core/event_repository.dart';
import '../core/enrichment_queue_repository.dart';
import '../core/trial_repository.dart';
import '../core/entity_repository.dart';
import '../core/invocation.dart';
import '../domain/audio_file.dart';
import '../persistence/objectbox/invocation_objectbox_adapter.dart';
import '../persistence/objectbox/adaptation_state_objectbox_adapter.dart';
import '../persistence/objectbox/feedback_objectbox_adapter.dart';
import '../persistence/objectbox/event_objectbox_adapter.dart';
import '../persistence/objectbox/enrichment_queue_objectbox_adapter.dart';
import '../persistence/objectbox/trial_objectbox_adapter.dart';
import '../persistence/objectbox/audio_file_objectbox_adapter.dart';
import 'objectbox_store_factory.dart';

/// Initialize persistence layer for native platforms using ObjectBox.
///
/// Creates and registers all repository adapters backed by ObjectBox.
/// Note: Handler wiring (like SemanticIndexableHandler) happens in bootstrap.dart
Future<void> initializePersistence(GetIt getIt) async {
  print('🔍 [persistence_NATIVE] Function called! (Native ObjectBox version)');
  print('   Passed getIt: ${getIt.hashCode}');
  print('   GetIt.instance: ${GetIt.instance.hashCode}');

  final store = await openObjectBoxStore();

  // Register store for direct access (TaskRepository needs it)
  // Register both with and without name for compatibility
  print('🔍 [persistence_native] Registering objectbox.Store in GetIt...');

  getIt.registerSingleton<Store>(store);
  print('   ✓ objectbox.Store registered (no instance name)');
  print('   Verify immediately: objectbox.Store registered? ${getIt.isRegistered<Store>()}');

  getIt.registerSingleton<Store>(store, instanceName: 'objectBoxStore');
  print('   ✓ Store registered (instanceName: objectBoxStore)');

  // Create and register adapters
  final invocationAdapter = InvocationObjectBoxAdapter(store);
  final adaptationStateAdapter = AdaptationStateObjectBoxAdapter(store);
  final feedbackAdapter = FeedbackObjectBoxAdapter(store);
  final trialAdapter = TrialObjectBoxAdapter(store);
  final audioFileAdapter = AudioFileObjectBoxAdapter(store);

  // Register InvocationRepository adapter
  // Handler wiring (like SemanticIndexableHandler) is done in bootstrap.dart
  getIt.registerSingleton<InvocationRepository<Invocation>>(invocationAdapter);

  getIt.registerSingleton<AdaptationStateRepository>(
    adaptationStateAdapter,
  );
  getIt.registerSingleton<FeedbackRepository>(
    feedbackAdapter,
  );
  getIt.registerSingleton<TrialRepository>(
    trialAdapter,
  );

  // Register AudioFile adapter (repository created later after EmbeddingService is ready)
  getIt.registerSingleton<AudioFileObjectBoxAdapter>(audioFileAdapter);

  // Create and register EnrichmentQueue adapter
  final enrichmentQueueAdapter = EnrichmentQueueObjectBoxAdapter(store);
  getIt.registerSingleton<EnrichmentQueueAdapter>(enrichmentQueueAdapter);
}

/// Create EventRepository for native platforms using ObjectBox.
Future<EventRepository> createEventRepository() async {
  final store = await openObjectBoxStore();
  return EventObjectBoxAdapter(store);
}

/// Close the ObjectBox store on disposal.
void disposePersistence(GetIt getIt) {
  try {
    final store = getIt<Store>();
    store.close();
  } catch (e) {
    // Store not registered, nothing to dispose
  }
}
