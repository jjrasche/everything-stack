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
import '../core/turn_repository.dart';
import '../core/event_repository.dart';
import '../domain/invocation.dart' as domain_invocation;
import '../persistence/objectbox/invocation_objectbox_adapter.dart';
import '../persistence/objectbox/adaptation_state_objectbox_adapter.dart';
import '../persistence/objectbox/feedback_objectbox_adapter.dart';
import '../persistence/objectbox/turn_objectbox_adapter.dart';
import '../persistence/objectbox/system_event_objectbox_adapter.dart';
import 'objectbox_store_factory.dart';

/// Initialize persistence layer for native platforms using ObjectBox.
///
/// Creates and registers all repository adapters backed by ObjectBox.
Future<void> initializePersistence(GetIt getIt) async {
  final store = await openObjectBoxStore();

  // Register store for direct access (TaskRepository needs it)
  getIt.registerSingleton<Store>(store, instanceName: 'objectBoxStore');

  // Create and register adapters
  final invocationAdapter = InvocationObjectBoxAdapter(store);
  final adaptationStateAdapter = AdaptationStateObjectBoxAdapter(store);
  final feedbackAdapter = FeedbackObjectBoxAdapter(store);
  final turnAdapter = TurnObjectBoxAdapter(store);

  // Register repositories in GetIt
  getIt.registerSingleton<InvocationRepository<domain_invocation.Invocation>>(
    invocationAdapter,
  );
  getIt.registerSingleton<AdaptationStateRepository>(
    adaptationStateAdapter,
  );
  getIt.registerSingleton<FeedbackRepository>(
    feedbackAdapter,
  );
  getIt.registerSingleton<TurnRepository>(
    turnAdapter,
  );
}

/// Create EventRepository for native platforms using ObjectBox.
Future<EventRepository> createEventRepository() async {
  final store = await openObjectBoxStore();
  return SystemEventRepositoryObjectBoxAdapter(store);
}

/// Close the ObjectBox store on disposal.
void disposePersistence(GetIt getIt) {
  try {
    final store = getIt<Store>(instanceName: 'objectBoxStore');
    store.close();
  } catch (e) {
    // Store not registered, nothing to dispose
  }
}
