/// # Task Tools
///
/// Tool functions for task management.
/// Registered with ToolRegistry and called by ToolExecutor.

import '../../services/tool_registry.dart';
import 'repositories/task_repository.dart';
import 'entities/task.dart';

// ============ Tool Functions ============

/// Create a new task
Future<Map<String, dynamic>> taskCreate(
  Map<String, dynamic> params,
  TaskRepository repo,
) async {
  final title = params['title'] as String?;
  if (title == null || title.isEmpty) {
    throw ArgumentError('Task title is required');
  }

  final task = Task(
    title: title,
    priority: params['priority'] as String? ?? 'medium',
    dueDate: params['dueDate'] != null
        ? DateTime.parse(params['dueDate'] as String)
        : null,
    description: params['description'] as String?,
  );

  await repo.save(task);
  return task.toJson();
}

/// Complete a task
Future<Map<String, dynamic>> taskComplete(
  Map<String, dynamic> params,
  TaskRepository repo,
) async {
  final taskId = params['taskId'] as String?;
  if (taskId == null || taskId.isEmpty) {
    throw ArgumentError('taskId is required');
  }

  final task = await repo.findByUuid(taskId);
  if (task == null) {
    throw ArgumentError('Task not found: $taskId');
  }

  task.complete();
  await repo.save(task);
  return task.toJson();
}

/// List tasks with optional filter
Future<Map<String, dynamic>> taskList(
  Map<String, dynamic> params,
  TaskRepository repo,
) async {
  final filter = params['filter'] as String? ?? 'all';

  final tasks = switch (filter) {
    'incomplete' => await repo.findIncomplete(),
    'completed' => await repo.findCompleted(),
    'overdue' => await repo.findOverdue(),
    'today' => await repo.findDueToday(),
    'soon' => await repo.findDueSoon(),
    'high_priority' => await repo.findHighPriority(),
    _ => await repo.findAll(),
  };

  return {
    'filter': filter,
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'count': tasks.length,
  };
}

// ============ Tool Registration ============

/// Register all task tools with the registry
void registerTaskTools(ToolRegistry registry, TaskRepository repo) {
  registry.register(
    ToolDefinition(
      name: 'task.create',
      namespace: 'task',
      description: 'Create a new task with title, optional priority and due date',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'Task title',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'medium', 'high'],
            'description': 'Task priority level',
          },
          'dueDate': {
            'type': 'string',
            'format': 'date-time',
            'description': 'Optional due date in ISO 8601 format',
          },
          'description': {
            'type': 'string',
            'description': 'Optional task description',
          },
        },
        'required': ['title'],
      },
    ),
    (params) => taskCreate(params, repo),
  );

  registry.register(
    ToolDefinition(
      name: 'task.complete',
      namespace: 'task',
      description: 'Mark a task as complete',
      parameters: {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'UUID of the task to complete',
          },
        },
        'required': ['taskId'],
      },
    ),
    (params) => taskComplete(params, repo),
  );

  registry.register(
    ToolDefinition(
      name: 'task.list',
      namespace: 'task',
      description: 'List tasks with optional filter',
      parameters: {
        'type': 'object',
        'properties': {
          'filter': {
            'type': 'string',
            'enum': ['all', 'incomplete', 'completed', 'overdue', 'today', 'soon', 'high_priority'],
            'description': 'Filter for which tasks to return',
          },
        },
      },
    ),
    (params) => taskList(params, repo),
  );
}
