/// # TaskRepository
///
/// ## What it does
/// Repository for Task entities. Manages user tasks/todos.
///
/// ## Usage
/// ```dart
/// final adapter = TaskObjectBoxAdapter(store);
/// final repo = TaskRepository(adapter: adapter);
///
/// // Find incomplete tasks
/// final incomplete = await repo.findIncomplete();
///
/// // Find tasks for a user
/// final userTasks = await repo.findByOwner('user_123');
/// ```

import '../../../core/entity_repository.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../services/embedding_service.dart';
import '../entities/task.dart'
    if (dart.library.html) '../../../bootstrap/task_stub.dart';

class TaskRepository extends EntityRepository<Task> {
  TaskRepository({
    required PersistenceAdapter<Task> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Task-specific queries ============

  /// Find all incomplete tasks, ordered by due date
  Future<List<Task>> findIncomplete() async {
    final all = await findAll();
    final incomplete = all.where((task) => task.isIncomplete).toList();
    incomplete.sort((a, b) {
      // High priority first
      if (a.isHighPriority != b.isHighPriority) {
        return a.isHighPriority ? -1 : 1;
      }
      // Then by due date (nulls last)
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return incomplete;
  }

  /// Find completed tasks
  Future<List<Task>> findCompleted() async {
    final all = await findAll();
    return all.where((task) => task.completed).toList()
      ..sort((a, b) => (b.completedAt ?? b.updatedAt)
          .compareTo(a.completedAt ?? a.updatedAt));
  }

  /// Find overdue tasks
  Future<List<Task>> findOverdue() async {
    final all = await findAll();
    return all.where((task) => task.isOverdue).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  /// Find tasks due today
  Future<List<Task>> findDueToday() async {
    final all = await findAll();
    return all.where((task) => task.isDueToday).toList();
  }

  /// Find tasks due soon (within 24 hours)
  Future<List<Task>> findDueSoon() async {
    final all = await findAll();
    return all.where((task) => task.isDueSoon).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  /// Find high priority tasks
  Future<List<Task>> findHighPriority() async {
    final all = await findAll();
    return all
        .where((task) => task.isHighPriority && task.isIncomplete)
        .toList();
  }

  /// Find tasks by priority
  Future<List<Task>> findByPriority(String priority) async {
    final all = await findAll();
    return all
        .where((task) => task.priority == priority && task.isIncomplete)
        .toList();
  }

  /// Find tasks owned by a user
  Future<List<Task>> findByOwner(String userId) async {
    final all = await findAll();
    return all.where((task) => task.ownerId == userId).toList();
  }

  /// Find tasks accessible to a user (owned or shared)
  Future<List<Task>> findAccessibleBy(String userId) async {
    final all = await findAll();
    return all.where((task) => task.isAccessibleBy(userId)).toList();
  }

  /// Find tasks created by a specific tool invocation
  Future<List<Task>> findByCorrelationId(String correlationId) async {
    final all = await findAll();
    return all
        .where((task) => task.invocationCorrelationId == correlationId)
        .toList();
  }
}
