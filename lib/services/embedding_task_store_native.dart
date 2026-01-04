/// Native platform EmbeddingTaskStore (ObjectBox)
///
/// This file is only imported on native platforms.
library;

import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';
import '../objectbox.g.dart';
import 'embedding_task.dart';
import 'embedding_task_store.dart';

/// Create the appropriate store for native platforms (ObjectBox)
Future<EmbeddingTaskStore> createEmbeddingTaskStore() async {
  final getIt = GetIt.instance;
  final store = getIt<Store>(instanceName: 'objectBoxStore');
  return _ObjectBoxEmbeddingTaskStore(store);
}

/// ObjectBox-based implementation of EmbeddingTaskStore
class _ObjectBoxEmbeddingTaskStore implements EmbeddingTaskStore {
  final Store _store;
  late final Box<EmbeddingTask> _box;

  _ObjectBoxEmbeddingTaskStore(this._store) {
    _box = _store.box<EmbeddingTask>();
  }

  @override
  Future<EmbeddingTaskData?> findByEntityUuid(String entityUuid) async {
    final task = _box
        .query(EmbeddingTask_.entityUuid.equals(entityUuid))
        .build()
        .findFirst();
    return task != null ? _toData(task) : null;
  }

  @override
  Future<int> getPendingCount() async {
    return _box
        .query(EmbeddingTask_.dbTaskStatus.equals(TaskStatus.pending.index))
        .build()
        .count();
  }

  @override
  Future<List<EmbeddingTaskData>> getPendingTasks(int limit) async {
    final tasks = _box
        .query(EmbeddingTask_.dbTaskStatus.equals(TaskStatus.pending.index))
        .build()
        .find()
        .take(limit)
        .toList();
    return tasks.map(_toData).toList();
  }

  @override
  Future<void> save(EmbeddingTaskData data) async {
    final task = _fromData(data);
    final id = _box.put(task);
    data.id = id; // Update the ID for new records
  }

  @override
  Future<void> delete(EmbeddingTaskData data) async {
    if (data.id > 0) {
      _box.remove(data.id);
    }
  }

  /// Convert ObjectBox entity to pure data
  EmbeddingTaskData _toData(EmbeddingTask task) {
    return EmbeddingTaskData(
      id: task.id,
      entityUuid: task.entityUuid,
      entityType: task.entityType,
      text: task.text,
      status: task.status,
      retryCount: task.retryCount,
      enqueuedAt: task.enqueuedAt,
      lastAttemptAt: task.lastAttemptAt,
      lastError: task.lastError,
    );
  }

  /// Convert pure data to ObjectBox entity
  EmbeddingTask _fromData(EmbeddingTaskData data) {
    final task = EmbeddingTask(
      entityUuid: data.entityUuid,
      entityType: data.entityType,
      text: data.text,
      status: data.status,
      retryCount: data.retryCount,
      enqueuedAt: data.enqueuedAt,
      lastAttemptAt: data.lastAttemptAt,
      lastError: data.lastError,
    );
    task.id = data.id;
    return task;
  }
}
