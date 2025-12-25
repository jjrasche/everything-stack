/// # ToolExecutor
///
/// ## What it does
/// Executes tools requested by the LLM.
/// Handles tool invocation, parameter validation, and result formatting.
///
/// ## Tool Call Flow
/// 1. LLM returns: {toolCalls: [{toolName: 'task.create', params: {title: 'Buy milk'}}]}
/// 2. ToolExecutor validates and executes each tool
/// 3. Returns: {results: [{toolName: 'task.create', success: true, data: {...}}]}
/// 4. Results sent back to LLM for further action
///
/// ## Tool Registry
/// Tools are discovered via:
/// - Namespace -> available tools
/// - Tool name -> handler function
///
/// For now, tools are stubbed. Real implementations will be added later.

import '../domain/invocation.dart';
import '../core/invocation_repository.dart';
import '../tools/task/repositories/task_repository.dart'
    if (dart.library.html) '../bootstrap/task_repository_stub.dart';
import '../tools/task/entities/task.dart'
    if (dart.library.html) '../bootstrap/task_stub.dart';

/// Result of a single tool execution
class ToolExecutionResult {
  final String toolName;
  final bool success;
  final dynamic data; // Tool-specific result
  final String? error;
  final int? latencyMs;

  ToolExecutionResult({
    required this.toolName,
    required this.success,
    this.data,
    this.error,
    this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'success': success,
        'data': data,
        'error': error,
        'latencyMs': latencyMs,
      };
}

/// Tool call request from LLM
class ToolCall {
  final String toolName;
  final Map<String, dynamic> params;
  final String callId;
  final double confidence;

  ToolCall({
    required this.toolName,
    required this.params,
    required this.callId,
    this.confidence = 1.0,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      toolName: json['toolName'] as String,
      params: json['params'] as Map<String, dynamic>,
      callId: json['callId'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'params': params,
        'callId': callId,
        'confidence': confidence,
      };
}

/// Executes LLM-requested tools
class ToolExecutor {
  final InvocationRepository<Invocation> invocationRepo;
  final TaskRepository? taskRepository;

  ToolExecutor({
    required this.invocationRepo,
    this.taskRepository,
  });

  /// Execute a tool call
  Future<ToolExecutionResult> executeTool(
    ToolCall toolCall, {
    required String correlationId,
  }) async {
    final startTime = DateTime.now();

    try {
      // Parse tool name (format: "namespace.toolName")
      final parts = toolCall.toolName.split('.');
      if (parts.length != 2) {
        return ToolExecutionResult(
          toolName: toolCall.toolName,
          success: false,
          error: 'Invalid tool name format',
        );
      }

      final namespace = parts[0];
      final toolName = parts[1];

      // Execute based on namespace
      final result = await _executeToolByNamespace(
        namespace: namespace,
        toolName: toolName,
        params: toolCall.params,
        callId: toolCall.callId,
        correlationId: correlationId,
      );

      return ToolExecutionResult(
        toolName: toolCall.toolName,
        success: result.success,
        data: result.data,
        error: result.error,
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      return ToolExecutionResult(
        toolName: toolCall.toolName,
        success: false,
        error: e.toString(),
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    }
  }

  /// Execute multiple tool calls
  Future<List<ToolExecutionResult>> executeTools(
    List<ToolCall> toolCalls, {
    required String correlationId,
  }) async {
    final results = <ToolExecutionResult>[];

    for (final toolCall in toolCalls) {
      final result = await executeTool(
        toolCall,
        correlationId: correlationId,
      );
      results.add(result);
    }

    return results;
  }

  /// Execute tool by namespace
  Future<ToolExecutionResult> _executeToolByNamespace({
    required String namespace,
    required String toolName,
    required Map<String, dynamic> params,
    required String callId,
    required String correlationId,
  }) async {
    try {
      // Task tools
      if (namespace == 'task') {
        if (toolName == 'create') {
          return await _handleTaskCreate(params, correlationId);
        } else if (toolName == 'complete') {
          return await _handleTaskComplete(params, correlationId);
        } else if (toolName == 'list') {
          return await _handleTaskList(params, correlationId);
        }
      }
      // Timer tools
      else if (namespace == 'timer') {
        if (toolName == 'set') {
          return await _handleTimerSet(params, correlationId);
        } else if (toolName == 'cancel') {
          return await _handleTimerCancel(params, correlationId);
        } else if (toolName == 'list') {
          return await _handleTimerList(params, correlationId);
        }
      }
      // Media tools
      else if (namespace == 'media') {
        if (toolName == 'search') {
          return await _handleMediaSearch(params, correlationId);
        } else if (toolName == 'download') {
          return await _handleMediaDownload(params, correlationId);
        }
      }
      // Subscription tools
      else if (namespace == 'subscription') {
        if (toolName == 'subscribe') {
          return await _handleSubscribe(params, correlationId);
        } else if (toolName == 'unsubscribe') {
          return await _handleUnsubscribe(params, correlationId);
        } else if (toolName == 'list') {
          return await _handleSubscriptionList(params, correlationId);
        }
      }

      return ToolExecutionResult(
        toolName: '$namespace.$toolName',
        success: false,
        error: 'Unknown tool: $namespace.$toolName',
      );
    } catch (e) {
      return ToolExecutionResult(
        toolName: '$namespace.$toolName',
        success: false,
        error: e.toString(),
      );
    }
  }

  // ============ Task Tool Handlers ============

  Future<ToolExecutionResult> _handleTaskCreate(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final title = params['title'] as String?;
    if (title == null || title.isEmpty) {
      return ToolExecutionResult(
        toolName: 'task.create',
        success: false,
        error: 'Task title is required',
      );
    }

    if (taskRepository == null) {
      return ToolExecutionResult(
        toolName: 'task.create',
        success: false,
        error: 'Task repository not available',
      );
    }

    try {
      final task = Task(
        title: title,
        priority: params['priority'] as String? ?? 'medium',
        dueDate: params['dueDate'] != null
            ? DateTime.parse(params['dueDate'] as String)
            : null,
        description: params['description'] as String?,
      );

      final savedTask = await taskRepository!.save(task);

      return ToolExecutionResult(
        toolName: 'task.create',
        success: true,
        data: {
          'taskId': savedTask.uuid,
          'id': savedTask.id,
          'title': savedTask.title,
          'priority': savedTask.priority,
          'dueDate': savedTask.dueDate?.toIso8601String(),
          'description': savedTask.description,
          'completed': savedTask.completed,
          'createdAt': savedTask.createdAt.toIso8601String(),
        },
      );
    } catch (e) {
      return ToolExecutionResult(
        toolName: 'task.create',
        success: false,
        error: 'Failed to create task: $e',
      );
    }
  }

  Future<ToolExecutionResult> _handleTaskComplete(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final taskId = params['taskId'] as String?;
    if (taskId == null) {
      return ToolExecutionResult(
        toolName: 'task.complete',
        success: false,
        error: 'Task ID is required',
      );
    }

    if (taskRepository == null) {
      return ToolExecutionResult(
        toolName: 'task.complete',
        success: false,
        error: 'Task repository not available',
      );
    }

    try {
      final task = await taskRepository!.findByUuid(taskId);
      if (task == null) {
        return ToolExecutionResult(
          toolName: 'task.complete',
          success: false,
          error: 'Task not found: $taskId',
        );
      }

      task.complete();
      final updatedTask = await taskRepository!.save(task);

      return ToolExecutionResult(
        toolName: 'task.complete',
        success: true,
        data: {
          'taskId': updatedTask.uuid,
          'id': updatedTask.id,
          'title': updatedTask.title,
          'completed': updatedTask.completed,
          'completedAt': updatedTask.completedAt?.toIso8601String(),
        },
      );
    } catch (e) {
      return ToolExecutionResult(
        toolName: 'task.complete',
        success: false,
        error: 'Failed to complete task: $e',
      );
    }
  }

  Future<ToolExecutionResult> _handleTaskList(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final filter = params['filter'] ?? 'all'; // all, incomplete, completed

    if (taskRepository == null) {
      return ToolExecutionResult(
        toolName: 'task.list',
        success: false,
        error: 'Task repository not available',
      );
    }

    try {
      final List<Task> tasks;

      switch (filter) {
        case 'incomplete':
          tasks = await taskRepository!.findIncomplete();
          break;
        case 'completed':
          tasks = await taskRepository!.findCompleted();
          break;
        case 'overdue':
          tasks = await taskRepository!.findOverdue();
          break;
        case 'today':
          tasks = await taskRepository!.findDueToday();
          break;
        case 'soon':
          tasks = await taskRepository!.findDueSoon();
          break;
        default: // 'all'
          tasks = await taskRepository!.findAll();
      }

      return ToolExecutionResult(
        toolName: 'task.list',
        success: true,
        data: {
          'filter': filter,
          'tasks': tasks
              .map((task) => {
                    'id': task.id,
                    'uuid': task.uuid,
                    'title': task.title,
                    'priority': task.priority,
                    'dueDate': task.dueDate?.toIso8601String(),
                    'description': task.description,
                    'completed': task.completed,
                    'completedAt': task.completedAt?.toIso8601String(),
                    'createdAt': task.createdAt.toIso8601String(),
                  })
              .toList(),
          'count': tasks.length,
        },
      );
    } catch (e) {
      return ToolExecutionResult(
        toolName: 'task.list',
        success: false,
        error: 'Failed to list tasks: $e',
      );
    }
  }

  // ============ Timer Tool Handlers ============

  Future<ToolExecutionResult> _handleTimerSet(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final label = params['label'] as String? ?? 'Timer';
    final minutes = (params['minutes'] as num?)?.toInt() ?? 1;
    final durationSeconds = minutes * 60;

    return ToolExecutionResult(
      toolName: 'timer.set',
      success: true,
      data: {
        'timerId': 'timer_${DateTime.now().millisecondsSinceEpoch}',
        'label': label,
        'durationSeconds': durationSeconds,
        'endsAt': DateTime.now().add(Duration(seconds: durationSeconds)).toIso8601String(),
        'status': 'running',
      },
    );
  }

  Future<ToolExecutionResult> _handleTimerCancel(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final timerId = params['timerId'] as String?;
    if (timerId == null) {
      return ToolExecutionResult(
        toolName: 'timer.cancel',
        success: false,
        error: 'Timer ID is required',
      );
    }

    return ToolExecutionResult(
      toolName: 'timer.cancel',
      success: true,
      data: {
        'timerId': timerId,
        'status': 'cancelled',
        'cancelledAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<ToolExecutionResult> _handleTimerList(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    return ToolExecutionResult(
      toolName: 'timer.list',
      success: true,
      data: {
        'activeTimers': [],
        'count': 0,
      },
    );
  }

  // ============ Media Tool Handlers ============

  Future<ToolExecutionResult> _handleMediaSearch(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final query = params['query'] as String?;
    if (query == null || query.isEmpty) {
      return ToolExecutionResult(
        toolName: 'media.search',
        success: false,
        error: 'Search query is required',
      );
    }

    return ToolExecutionResult(
      toolName: 'media.search',
      success: true,
      data: {
        'query': query,
        'results': [],
        'count': 0,
        'message': 'Media search available (connect to media repository)',
      },
    );
  }

  Future<ToolExecutionResult> _handleMediaDownload(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final mediaId = params['mediaId'] as String?;
    if (mediaId == null) {
      return ToolExecutionResult(
        toolName: 'media.download',
        success: false,
        error: 'Media ID is required',
      );
    }

    return ToolExecutionResult(
      toolName: 'media.download',
      success: true,
      data: {
        'mediaId': mediaId,
        'status': 'queued',
        'startedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  // ============ Subscription Tool Handlers ============

  Future<ToolExecutionResult> _handleSubscribe(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final sourceUrl = params['sourceUrl'] as String?;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      return ToolExecutionResult(
        toolName: 'subscription.subscribe',
        success: false,
        error: 'Source URL is required',
      );
    }

    return ToolExecutionResult(
      toolName: 'subscription.subscribe',
      success: true,
      data: {
        'subscriptionId': 'sub_${DateTime.now().millisecondsSinceEpoch}',
        'sourceUrl': sourceUrl,
        'sourceType': params['sourceType'] ?? 'unknown',
        'name': params['name'],
        'status': 'active',
      },
    );
  }

  Future<ToolExecutionResult> _handleUnsubscribe(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final subscriptionId = params['subscriptionId'] as String?;
    if (subscriptionId == null) {
      return ToolExecutionResult(
        toolName: 'subscription.unsubscribe',
        success: false,
        error: 'Subscription ID is required',
      );
    }

    return ToolExecutionResult(
      toolName: 'subscription.unsubscribe',
      success: true,
      data: {
        'subscriptionId': subscriptionId,
        'status': 'inactive',
        'unsubscribedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<ToolExecutionResult> _handleSubscriptionList(
    Map<String, dynamic> params,
    String correlationId,
  ) async {
    final active = params['active'] ?? true;

    return ToolExecutionResult(
      toolName: 'subscription.list',
      success: true,
      data: {
        'filter': active ? 'active' : 'all',
        'subscriptions': [],
        'count': 0,
      },
    );
  }

  /// Record tool execution invocation
  Future<void> recordToolExecution({
    required String correlationId,
    required ToolCall toolCall,
    required ToolExecutionResult result,
  }) async {
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'tool_executor',
      success: result.success,
      confidence: toolCall.confidence,
      input: {
        'toolName': toolCall.toolName,
        'params': toolCall.params,
      },
      output: {
        'result': result.toJson(),
      },
    );

    await invocationRepo.save(invocation);
  }
}
