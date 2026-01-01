/// # SystemEventRepositoryObjectBoxAdapter
///
/// ObjectBox implementation of EventRepository for native platforms.
/// Persists SystemEvent objects to ObjectBox for long-term storage.
///
/// ## Design
/// - Events stored as SystemEventOB with JSON payload
/// - Queries indexed by correlationId and createdAt
/// - Batch operations for efficiency
/// - Full CRUD interface implementation
library;

import 'package:objectbox/objectbox.dart';
import 'dart:convert' show json;
import '../../core/event_repository.dart';
import '../../services/events/system_event.dart';
import '../../services/events/transcription_complete.dart';
import '../../services/events/error_occurred.dart';
import 'wrappers/system_event_ob.dart';

class SystemEventRepositoryObjectBoxAdapter implements EventRepository {
  final Store store;
  late Box<SystemEventOB> _box;

  SystemEventRepositoryObjectBoxAdapter(this.store) {
    _box = store.box<SystemEventOB>();
  }

  @override
  Future<void> save(SystemEvent event) async {
    final ob = _systemEventToOB(event);
    _box.put(ob);
  }

  @override
  Future<void> saveBatch(List<SystemEvent> events) async {
    final obs = events.map(_systemEventToOB).toList();
    _box.putMany(obs);
  }

  @override
  Future<List<SystemEvent>> getByCorrelationId(String correlationId) async {
    // Get all and filter (MVP - no generated query helpers yet)
    final all = _box.getAll();
    final filtered = all
        .where((ob) => ob.correlationId == correlationId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered.map(_obToSystemEvent).toList();
  }

  @override
  Future<List<T>> getByType<T extends SystemEvent>() async {
    // Get all and filter by type
    final eventType = T.toString();
    final all = _box.getAll();
    return all
        .where((ob) => ob.eventType == eventType)
        .map(_obToSystemEvent)
        .whereType<T>()
        .toList();
  }

  @override
  Future<List<SystemEvent>> getSince(DateTime timestamp) async {
    // Get all and filter by timestamp
    final all = _box.getAll();
    final filtered = all
        .where((ob) => ob.createdAt.isAfter(timestamp))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered.map(_obToSystemEvent).toList();
  }

  @override
  Future<List<SystemEvent>> getAll() async {
    final results = _box.getAll();
    return results.map(_obToSystemEvent).toList();
  }

  @override
  Future<bool> delete(String eventId) async {
    try {
      final id = int.tryParse(eventId);
      if (id != null && id > 0) {
        return _box.remove(id);
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clear() async {
    _box.removeAll();
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  @override
  Future<int> countByCorrelationId(String correlationId) async {
    final all = _box.getAll();
    return all.where((ob) => ob.correlationId == correlationId).length;
  }

  /// Convert SystemEvent to ObjectBox model
  SystemEventOB _systemEventToOB(SystemEvent event) {
    return SystemEventOB(
      eventType: event.eventType,
      correlationId: event.correlationId,
      createdAt: event.createdAt,
      jsonData: json.encode(_systemEventToJson(event)),
    );
  }

  /// Convert ObjectBox model to SystemEvent
  SystemEvent _obToSystemEvent(SystemEventOB ob) {
    final jsonData = json.decode(ob.jsonData) as Map<String, dynamic>;
    return _jsonToSystemEvent(jsonData);
  }

  /// Convert SystemEvent to JSON map
  Map<String, dynamic> _systemEventToJson(SystemEvent event) {
    final map = event.toJson();

    if (event is TranscriptionComplete) {
      map['transcript'] = event.transcript;
      map['durationMs'] = event.durationMs;
      map['confidence'] = event.confidence;
    } else if (event is ErrorOccurred) {
      map['source'] = event.source;
      map['message'] = event.message;
      map['errorType'] = event.errorType;
      map['stackTrace'] = event.stackTrace;
      map['severity'] = event.severity;
    }

    return map;
  }

  /// Convert JSON map to SystemEvent
  SystemEvent _jsonToSystemEvent(Map<String, dynamic> json) {
    final eventType = json['eventType'] as String?;

    if (eventType == 'TranscriptionComplete') {
      return TranscriptionComplete.fromJson(json);
    } else if (eventType == 'ErrorOccurred') {
      return ErrorOccurred.fromJson(json);
    } else {
      throw UnsupportedError('Unknown event type: $eventType');
    }
  }
}
