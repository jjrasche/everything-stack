/// Web platform persistence initialization (IndexedDB)
///
/// This file is only imported on web platform.
/// It creates IndexedDB-based adapters for all repositories.
library;

import 'package:get_it/get_it.dart';

import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback_repository.dart';
import '../core/turn_repository.dart';
import '../core/event_repository.dart';
import '../domain/invocation.dart' as domain_invocation;
import '../persistence/indexeddb/invocation_indexeddb_adapter.dart';
import '../persistence/indexeddb/adaptation_state_indexeddb_adapter.dart';
import '../persistence/indexeddb/feedback_indexeddb_adapter.dart';
import '../persistence/indexeddb/turn_indexeddb_adapter.dart';
import '../persistence/indexeddb/system_event_indexeddb_adapter.dart';
import 'indexeddb_factory.dart';

/// Initialize persistence layer for web platform using IndexedDB.
///
/// Creates and registers all repository adapters backed by IndexedDB.
Future<void> initializePersistence(GetIt getIt) async {
  final db = await openIndexedDB();

  // Create and register adapters
  final invocationAdapter = InvocationIndexedDBAdapter(db);
  final adaptationStateAdapter = AdaptationStateIndexedDBAdapter(db);
  final feedbackAdapter = FeedbackIndexedDBAdapter(db);
  final turnAdapter = TurnIndexedDBAdapter(db);

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

/// Create EventRepository for web platform using IndexedDB.
Future<EventRepository> createEventRepository() async {
  final db = await openIndexedDB();
  return SystemEventRepositoryIndexedDBAdapter(db);
}

/// No-op disposal for web (IndexedDB cleanup handled by browser).
void disposePersistence(GetIt getIt) {
  // IndexedDB cleanup is handled by the browser
}
