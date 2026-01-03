/// # SystemEventRepositoryObjectBoxAdapter Stub for Web Platform
///
/// This file is a stub that provides a no-op implementation for Web platform
/// where ObjectBox is not available.
/// Real implementation uses ObjectBox on native platforms.
library;

import '../../bootstrap/objectbox_stub.dart'
    if (dart.library.io) 'package:objectbox/objectbox.dart';
import '../../core/event_repository.dart';
import '../../services/events/system_event.dart';

/// Stub SystemEventRepositoryObjectBoxAdapter for Web platform
class SystemEventRepositoryObjectBoxAdapter implements EventRepository {
  final Store store;

  SystemEventRepositoryObjectBoxAdapter(this.store);

  @override
  Future<void> save(SystemEvent event) async {}

  @override
  Future<void> saveBatch(List<SystemEvent> events) async {}

  @override
  Future<List<SystemEvent>> getByCorrelationId(String correlationId) async =>
      [];

  @override
  Future<List<T>> getByType<T extends SystemEvent>() async => [];

  @override
  Future<List<SystemEvent>> getSince(DateTime timestamp) async => [];

  @override
  Future<List<SystemEvent>> getAll() async => [];

  @override
  Future<bool> delete(String eventId) async => false;

  @override
  Future<void> clear() async {}

  @override
  Future<int> count() async => 0;

  @override
  Future<int> countByCorrelationId(String correlationId) async => 0;
}
