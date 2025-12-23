/// # Task Tool Handlers
///
/// ## What it does
/// Registers task tools (create, update, complete, delete) with ToolRegistry.
/// Each handler is a Dart function that operates on TaskRepository.
///
/// ## Tools
/// - task.create: Create a new task
/// - task.update: Update an existing task
/// - task.complete: Mark a task as completed
/// - task.delete: Delete a task
///
/// ## Usage
/// ```dart
/// final registry = ToolRegistry();
/// registerTaskTools(registry, taskRepo);
/// ```

import '../../../services/tool_registry.dart';
import '../repositories/task_repository.dart';
import '../entities/task.dart';

/// Register all task tools with the registry
void registerTaskTools(ToolRegistry registry, TaskRepository taskRepo) {
  // task.create
  registry.register(
    ToolDefinition(
      name: 'task.create',
      namespace: 'task',
      description: 'Create a new task with title, optional priority, and optional due date',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'The task title',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'medium', 'high'],
            'description': 'Task priority (default: medium)',
          },
          'dueDate': {
            'type': 'string',
            'format': 'date-time',
            'description': 'ISO 8601 due date (optional)',
          },
          'description': {
            'type': 'string',
            'description': 'Longer task description (optional)',
          },
        },
        'required': ['title'],
      },
    ),
    (params) async {
      final task = Task(
        title: params['title'] as String,
        priority: params['priority'] as String? ?? 'medium',
        dueDate: params['dueDate'] != null
            ? DateTime.parse(params['dueDate'] as String)
            : null,
        description: params['description'] as String?,
      );

      await taskRepo.save(task);

      return {
        'success': true,
        'id': task.uuid,
        'title': task.title,
        'priority': task.priority,
        'status': 'created',
      };
    },
  );

  // task.update
  registry.register(
    ToolDefinition(
      name: 'task.update',
      namespace: 'task',
      description: 'Update an existing task by UUID',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'Task UUID',
          },
          'title': {
            'type': 'string',
            'description': 'New title (optional)',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'medium', 'high'],
            'description': 'New priority (optional)',
          },
          'dueDate': {
            'type': 'string',
            'format': 'date-time',
            'description': 'New due date ISO 8601 (optional)',
          },
          'description': {
            'type': 'string',
            'description': 'New description (optional)',
          },
        },
        'required': ['id'],
      },
    ),
    (params) async {
      final taskId = params['id'] as String;
      final task = await taskRepo.findByUuid(taskId);

      if (task == null) {
        return {
          'success': false,
          'error': 'Task not found',
          'id': taskId,
        };
      }

      if (params['title'] != null) {
        task.title = params['title'] as String;
      }
      if (params['priority'] != null) {
        task.setPriority(params['priority'] as String);
      }
      if (params['dueDate'] != null) {
        task.dueDate = DateTime.parse(params['dueDate'] as String);
        task.touch();
      }
      if (params['description'] != null) {
        task.description = params['description'] as String;
        task.touch();
      }

      await taskRepo.save(task);

      return {
        'success': true,
        'id': task.uuid,
        'title': task.title,
        'priority': task.priority,
        'status': 'updated',
      };
    },
  );

  // task.complete
  registry.register(
    ToolDefinition(
      name: 'task.complete',
      namespace: 'task',
      description: 'Mark a task as completed',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'Task UUID',
          },
        },
        'required': ['id'],
      },
    ),
    (params) async {
      final taskId = params['id'] as String;
      final task = await taskRepo.findByUuid(taskId);

      if (task == null) {
        return {
          'success': false,
          'error': 'Task not found',
          'id': taskId,
        };
      }

      task.complete();
      await taskRepo.save(task);

      return {
        'success': true,
        'id': task.uuid,
        'title': task.title,
        'completed': true,
        'completedAt': task.completedAt?.toIso8601String(),
        'status': 'completed',
      };
    },
  );

  // task.delete
  registry.register(
    ToolDefinition(
      name: 'task.delete',
      namespace: 'task',
      description: 'Delete a task permanently',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'Task UUID',
          },
        },
        'required': ['id'],
      },
    ),
    (params) async {
      final taskId = params['id'] as String;
      final task = await taskRepo.findByUuid(taskId);

      if (task == null) {
        return {
          'success': false,
          'error': 'Task not found',
          'id': taskId,
        };
      }

      await taskRepo.delete(task.id!);

      return {
        'success': true,
        'id': taskId,
        'status': 'deleted',
      };
    },
  );
}
