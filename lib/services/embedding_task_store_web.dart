/// Web platform EmbeddingTaskStore (IndexedDB)
///
/// This file is only imported on web platforms.
library;

import 'package:get_it/get_it.dart';
import 'package:idb_shim/idb.dart';
import '../persistence/indexeddb/database_schema.dart';
import 'embedding_task_store.dart';

/// Create the appropriate store for web platforms (IndexedDB)
Future<EmbeddingTaskStore> createEmbeddingTaskStore() async {
  final getIt = GetIt.instance;
  final db = getIt<Database>(instanceName: 'indexedDB');
  return _IndexedDBEmbeddingTaskStore(db);
}

/// IndexedDB-based implementation of EmbeddingTaskStore
class _IndexedDBEmbeddingTaskStore implements EmbeddingTaskStore {
  final Database _db;

  _IndexedDBEmbeddingTaskStore(this._db);

  ObjectStore _getStore({String mode = idbModeReadWrite}) {
    final txn = _db.transaction(ObjectStores.embeddingTasks, mode);
    return txn.objectStore(ObjectStores.embeddingTasks);
  }

  @override
  Future<EmbeddingTaskData?> findByEntityUuid(String entityUuid) async {
    final txn = _db.transaction(ObjectStores.embeddingTasks, idbModeReadOnly);
    final store = txn.objectStore(ObjectStores.embeddingTasks);
    final index = store.index(Indexes.embeddingTasksEntityUuid);

    final value = await index.get(entityUuid);
    if (value == null) return null;

    return _fromJson(value as Map<String, dynamic>);
  }

  @override
  Future<int> getPendingCount() async {
    final txn = _db.transaction(ObjectStores.embeddingTasks, idbModeReadOnly);
    final store = txn.objectStore(ObjectStores.embeddingTasks);
    final index = store.index(Indexes.embeddingTasksStatus);

    return await index.count(TaskStatus.pending.index);
  }

  @override
  Future<List<EmbeddingTaskData>> getPendingTasks(int limit) async {
    final txn = _db.transaction(ObjectStores.embeddingTasks, idbModeReadOnly);
    final store = txn.objectStore(ObjectStores.embeddingTasks);
    final index = store.index(Indexes.embeddingTasksStatus);

    final results = <EmbeddingTaskData>[];
    final cursor =
        index.openCursor(key: TaskStatus.pending.index, autoAdvance: true);

    await for (final record in cursor) {
      if (results.length >= limit) break;
      final json = record.value as Map<String, dynamic>;
      results.add(_fromJson(json));
    }

    return results;
  }

  @override
  Future<void> save(EmbeddingTaskData data) async {
    final store = _getStore();
    final json = _toJson(data);

    if (data.id == 0) {
      // New record - let IndexedDB auto-generate ID
      final id = await store.add(json);
      data.id = id as int;
    } else {
      // Existing record - update
      await store.put(json);
    }
  }

  @override
  Future<void> delete(EmbeddingTaskData data) async {
    if (data.id > 0) {
      final store = _getStore();
      await store.delete(data.id);
    }
  }

  /// Convert JSON to EmbeddingTaskData
  EmbeddingTaskData _fromJson(Map<String, dynamic> json) {
    return EmbeddingTaskData(
      id: json['id'] as int? ?? 0,
      entityUuid: json['entityUuid'] as String,
      entityType: json['entityType'] as String,
      text: json['text'] as String,
      status: TaskStatus.values[json['status'] as int? ?? 0],
      retryCount: json['retryCount'] as int? ?? 0,
      enqueuedAt: json['enqueuedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['enqueuedAt'] as int)
          : DateTime.now(),
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastAttemptAt'] as int)
          : null,
      lastError: json['lastError'] as String?,
    );
  }

  /// Convert EmbeddingTaskData to JSON
  Map<String, dynamic> _toJson(EmbeddingTaskData data) {
    return {
      if (data.id > 0) 'id': data.id,
      'entityUuid': data.entityUuid,
      'entityType': data.entityType,
      'text': data.text,
      'status': data.status.index,
      'retryCount': data.retryCount,
      'enqueuedAt': data.enqueuedAt.millisecondsSinceEpoch,
      'lastAttemptAt': data.lastAttemptAt?.millisecondsSinceEpoch,
      'lastError': data.lastError,
    };
  }
}
