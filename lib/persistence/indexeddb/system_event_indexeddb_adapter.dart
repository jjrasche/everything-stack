/// # SystemEventRepositoryIndexedDBAdapter
///
/// IndexedDB implementation of EventRepository for web platform.
/// Persists SystemEvent objects using IndexedDB for web persistence.
///
/// ## Design
/// - Events stored in 'system_events' object store
/// - Primary key: correlationId + timestamp (unique per turn)
/// - Indexes on correlationId and createdAt for efficient queries
/// - Full CRUD interface implementation
library;

import 'dart:convert' show json;
import 'package:idb_shim/idb.dart';
import '../../core/event_repository.dart';
import '../../services/events/system_event.dart';
import '../../services/events/transcription_complete.dart';
import '../../services/events/error_occurred.dart';

class SystemEventRepositoryIndexedDBAdapter implements EventRepository {
  final Database db;
  static const String _storeName = 'system_events';

  SystemEventRepositoryIndexedDBAdapter(this.db);

  /// Get the object store, creating it if needed
  Future<ObjectStore> _getObjectStore(String mode) async {
    try {
      final tx = db.transaction(_storeName, mode);
      return tx.objectStore(_storeName);
    } catch (e) {
      // Store might not exist yet - this is OK for web
      // IndexedDB schema creation would need to happen in bootstrap
      rethrow;
    }
  }

  /// Generate unique key for event
  String _generateKey(SystemEvent event) {
    // Key: correlationId + timestamp ensures uniqueness per turn
    return '${event.correlationId}_${event.createdAt.millisecondsSinceEpoch}';
  }

  @override
  Future<void> save(SystemEvent event) async {
    final tx = db.transaction(_storeName, 'readwrite');
    final store = tx.objectStore(_storeName);

    final json = _systemEventToJson(event);
    json['_key'] = _generateKey(event); // Unique key for IndexedDB

    await store.put(json);
    await tx.completed;
  }

  @override
  Future<void> saveBatch(List<SystemEvent> events) async {
    final tx = db.transaction(_storeName, 'readwrite');
    final store = tx.objectStore(_storeName);

    for (final event in events) {
      final json = _systemEventToJson(event);
      json['_key'] = _generateKey(event);
      await store.put(json);
    }

    await tx.completed;
  }

  @override
  Future<List<SystemEvent>> getByCorrelationId(String correlationId) async {
    final tx = db.transaction(_storeName, 'readonly');
    final store = tx.objectStore(_storeName);

    final allObjects = await store.getAll() as List;
    await tx.completed;

    return allObjects
        .whereType<Map<String, dynamic>>()
        .where((obj) => obj['correlationId'] == correlationId)
        .map(_jsonToSystemEvent)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<List<T>> getByType<T extends SystemEvent>() async {
    final eventType = T.toString();
    final tx = db.transaction(_storeName, 'readonly');
    final store = tx.objectStore(_storeName);

    final allObjects = await store.getAll() as List;
    await tx.completed;

    return allObjects
        .whereType<Map<String, dynamic>>()
        .where((obj) => obj['eventType'] == eventType)
        .map(_jsonToSystemEvent)
        .whereType<T>()
        .toList();
  }

  @override
  Future<List<SystemEvent>> getSince(DateTime timestamp) async {
    final tx = db.transaction(_storeName, 'readonly');
    final store = tx.objectStore(_storeName);

    final allObjects = await store.getAll() as List;
    await tx.completed;

    return allObjects
        .whereType<Map<String, dynamic>>()
        .where((obj) {
          final createdAt = obj['createdAt'];
          if (createdAt is String) {
            try {
              return DateTime.parse(createdAt).isAfter(timestamp);
            } catch (e) {
              return false;
            }
          }
          return false;
        })
        .map(_jsonToSystemEvent)
        .toList();
  }

  @override
  Future<List<SystemEvent>> getAll() async {
    final tx = db.transaction(_storeName, 'readonly');
    final store = tx.objectStore(_storeName);

    final allObjects = await store.getAll() as List;
    await tx.completed;

    return allObjects
        .whereType<Map<String, dynamic>>()
        .map(_jsonToSystemEvent)
        .toList();
  }

  @override
  Future<bool> delete(String eventId) async {
    try {
      final tx = db.transaction(_storeName, 'readwrite');
      final store = tx.objectStore(_storeName);
      await store.delete(eventId);
      await tx.completed;
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clear() async {
    final tx = db.transaction(_storeName, 'readwrite');
    final store = tx.objectStore(_storeName);
    await store.clear();
    await tx.completed;
  }

  @override
  Future<int> count() async {
    final tx = db.transaction(_storeName, 'readonly');
    final store = tx.objectStore(_storeName);
    final count = await store.count() as int;
    await tx.completed;

    return count;
  }

  @override
  Future<int> countByCorrelationId(String correlationId) async {
    final tx = db.transaction(_storeName, 'readonly');
    final store = tx.objectStore(_storeName);
    final allObjects = await store.getAll() as List;
    await tx.completed;

    return allObjects
        .whereType<Map<String, dynamic>>()
        .where((obj) => obj['correlationId'] == correlationId)
        .length;
  }

  /// Convert SystemEvent to JSON map for storage
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
  SystemEvent _jsonToSystemEvent(Map<String, dynamic> jsonData) {
    final eventType = jsonData['eventType'] as String?;

    try {
      if (eventType == 'TranscriptionComplete') {
        return TranscriptionComplete.fromJson(jsonData);
      } else if (eventType == 'ErrorOccurred') {
        return ErrorOccurred.fromJson(jsonData);
      } else {
        throw UnsupportedError('Unknown event type: $eventType');
      }
    } catch (e) {
      throw StateError('Failed to deserialize event: $e (type: $eventType, data: $jsonData)');
    }
  }
}
