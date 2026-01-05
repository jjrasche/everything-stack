/// # EventIndexedDBAdapter
///
/// IndexedDB adapter for Event entity persistence on web platform.
library;

import 'package:idb_shim/idb_browser.dart';
import '../../core/event_repository.dart';
import '../../domain/event.dart';

class EventIndexedDBAdapter implements EventRepository {
  final Database db;

  EventIndexedDBAdapter(this.db);

  Future<ObjectStore> _getStore() async {
    final txn = db.transaction('events', 'readwrite');
    return txn.objectStore('events');
  }

  @override
  Future<void> save(Event event) async {
    final store = await _getStore();
    await store.put({
      'uuid': event.uuid,
      'id': event.id,
      'createdAt': event.createdAt.toIso8601String(),
      'updatedAt': event.updatedAt.toIso8601String(),
      'syncId': event.syncId,
      'eventType': event.eventType,
      'correlationId': event.correlationId,
      'parentEventId': event.parentEventId,
      'source': event.source,
      'timestamp': event.timestamp.toIso8601String(),
      'payloadJson': event.payloadJson,
    });
  }

  @override
  Future<void> saveBatch(List<Event> events) async {
    final store = await _getStore();
    for (final event in events) {
      await store.put({
        'uuid': event.uuid,
        'id': event.id,
        'createdAt': event.createdAt.toIso8601String(),
        'updatedAt': event.updatedAt.toIso8601String(),
        'syncId': event.syncId,
        'eventType': event.eventType,
        'correlationId': event.correlationId,
        'parentEventId': event.parentEventId,
        'source': event.source,
        'timestamp': event.timestamp.toIso8601String(),
        'payloadJson': event.payloadJson,
      });
    }
  }

  @override
  Future<List<Event>> getByCorrelationId(String correlationId) async {
    final store = await _getStore();
    final index = store.index('correlationId');
    final records = await index.getAll(correlationId) as List;
    return records.map(_fromJson).toList();
  }

  @override
  Future<List<Event>> getByType(String eventType) async {
    final store = await _getStore();
    final index = store.index('eventType');
    final records = await index.getAll(eventType) as List;
    return records.map(_fromJson).toList();
  }

  @override
  Future<List<Event>> getSince(DateTime timestamp) async {
    final store = await _getStore();
    final all = await store.getAll() as List;
    return all
        .map(_fromJson)
        .where((e) => e.createdAt.isAfter(timestamp))
        .toList();
  }

  @override
  Future<List<Event>> getAll() async {
    final store = await _getStore();
    final records = await store.getAll() as List;
    return records.map(_fromJson).toList();
  }

  @override
  Future<bool> delete(String uuid) async {
    final store = await _getStore();
    try {
      await store.delete(uuid);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clear() async {
    final store = await _getStore();
    await store.clear();
  }

  @override
  Future<int> count() async {
    final store = await _getStore();
    return await store.count() as int;
  }

  @override
  Future<int> countByCorrelationId(String correlationId) async {
    final events = await getByCorrelationId(correlationId);
    return events.length;
  }

  Event _fromJson(Map<String, dynamic> json) {
    final event = Event(
      eventType: json['eventType'] as String? ?? '',
      correlationId: json['correlationId'] as String? ?? '',
      source: json['source'] as String? ?? '',
      payloadJson: json['payloadJson'] as String? ?? '{}',
      parentEventId: json['parentEventId'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
    event.id = json['id'] as int? ?? 0;
    event.uuid = json['uuid'] as String? ?? '';
    event.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    event.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    event.syncId = json['syncId'] as String?;
    return event;
  }
}
