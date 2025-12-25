/// # TaskIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for Task entities.
/// Handles CRUD operations for web platform.
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final adapter = TaskIndexedDBAdapter(db);
/// final repo = TaskRepository(adapter: adapter);
/// ```

import 'package:idb_shim/idb.dart';
import '../../../persistence/indexeddb/base_indexeddb_adapter.dart';
import '../../../persistence/indexeddb/database_init.dart';
import '../entities/task.dart';

class TaskIndexedDBAdapter extends BaseIndexedDBAdapter<Task> {
  TaskIndexedDBAdapter(Database db) : super(db);

  /// Factory constructor for lazy initialization on web platform
  static Future<TaskIndexedDBAdapter> create() async {
    final db = await openIndexedDatabase();
    return TaskIndexedDBAdapter(db);
  }

  @override
  String get objectStoreName => 'tasks';

  @override
  Task fromJson(Map<String, dynamic> json) => Task.fromJson(json);

  // ============ Task-Specific Query Methods ============

  /// Find incomplete tasks
  Future<List<Task>> findIncomplete() async {
    final all = await findAll();
    return all.where((task) => !task.completed).toList();
  }

  /// Find completed tasks
  Future<List<Task>> findCompleted() async {
    final all = await findAll();
    return all.where((task) => task.completed).toList();
  }

  /// Find overdue tasks
  Future<List<Task>> findOverdue() async {
    final all = await findAll();
    final now = DateTime.now();
    return all.where((task) {
      if (task.completed || task.dueDate == null) return false;
      return task.dueDate!.isBefore(now);
    }).toList();
  }

  /// Find tasks by priority
  Future<List<Task>> findByPriority(String priority) async {
    final all = await findAll();
    return all
        .where((task) => task.priority == priority && !task.completed)
        .toList();
  }

  /// Find tasks by owner
  Future<List<Task>> findByOwner(String userId) async {
    final all = await findAll();
    return all.where((task) => task.ownerId == userId).toList();
  }
}
