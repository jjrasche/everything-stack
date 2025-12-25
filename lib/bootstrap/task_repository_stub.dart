/// # TaskRepository Stub (Web)
///
/// Stub implementation for web platform.
/// Real implementation is in tools/task/repositories/task_repository.dart

import 'task_stub.dart';

class TaskRepository {
  TaskRepository({required dynamic adapter});

  Future<Task?> findByUuid(String uuid) async => null;
  Future<List<Task>> findAll() async => [];
  Future<List<Task>> findIncomplete() async => [];
  Future<List<Task>> findCompleted() async => [];
  Future<List<Task>> findOverdue() async => [];
  Future<List<Task>> findDueToday() async => [];
  Future<List<Task>> findDueSoon() async => [];
  Future<Task> save(Task task) async => task;
}
