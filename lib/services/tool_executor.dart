/// # ToolExecutor
///
/// ## What it does
/// Executes tool calls by invoking in-app handlers. Replaces MCPClient.
/// Handles parallel execution and error reporting.
///
/// ## Flow
/// 1. Take List<ToolCall> from MCPExecutor
/// 2. For each tool call:
///    - Lookup handler via ToolRegistry
///    - Invoke handler directly (Dart function call)
///    - Catch any errors
/// 3. Execute all calls in parallel
/// 4. Return List<ToolResult> with successes/failures
///
/// ## Usage
/// ```dart
/// final executor = ToolExecutor(
///   registry: toolRegistry,
///   timeout: Duration(seconds: 30),
/// );
///
/// final results = await executor.executeToolCalls([
///   ToolCall(toolName: 'task.create', params: {...}),
///   ToolCall(toolName: 'timer.set', params: {...}),
/// ]);
///
/// for (final result in results) {
///   if (result.success) {
///     print('Tool ${result.toolName} succeeded: ${result.data}');
///   } else {
///     print('Tool ${result.toolName} failed: ${result.error}');
///   }
/// }
/// ```

import 'dart:async';

import 'tool_registry.dart';
import 'context_manager_result.dart';

class ToolExecutor {
  final ToolRegistry registry;
  final Duration timeout;

  ToolExecutor({
    required this.registry,
    this.timeout = const Duration(seconds: 30),
  });

  /// Execute multiple tool calls in parallel
  ///
  /// Returns results for all calls, even if some fail.
  /// Failed calls have success=false and error message populated.
  Future<List<ToolResult>> executeToolCalls(List<ToolCall> toolCalls) async {
    // Execute all calls in parallel
    final futures = toolCalls.map((call) => _executeSingleCall(call));
    return Future.wait(futures);
  }

  /// Execute a single tool call
  Future<ToolResult> _executeSingleCall(ToolCall toolCall) async {
    try {
      // Find handler for this tool
      final handler = registry.getHandler(toolCall.toolName);
      if (handler == null) {
        return ToolResult(
          toolName: toolCall.toolName,
          callId: toolCall.callId,
          success: false,
          error: 'No handler registered for tool: ${toolCall.toolName}',
          errorType: 'handler_not_found',
        );
      }

      // Execute handler with timeout
      final result = await handler(toolCall.params).timeout(timeout);

      return ToolResult(
        toolName: toolCall.toolName,
        callId: toolCall.callId,
        success: true,
        data: result,
      );
    } on TimeoutException {
      return ToolResult(
        toolName: toolCall.toolName,
        callId: toolCall.callId,
        success: false,
        error: 'Tool execution timeout after ${timeout.inSeconds}s',
        errorType: 'timeout',
      );
    } catch (e, stackTrace) {
      return ToolResult(
        toolName: toolCall.toolName,
        callId: toolCall.callId,
        success: false,
        error: 'Execution failed: $e',
        errorType: 'execution_error',
        errorDetails: stackTrace.toString(),
      );
    }
  }
}

/// Result of executing a tool
class ToolResult {
  final String toolName;
  final String? callId;
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;
  final String? errorType;
  final String? errorDetails;

  ToolResult({
    required this.toolName,
    this.callId,
    required this.success,
    this.data,
    this.error,
    this.errorType,
    this.errorDetails,
  });

  @override
  String toString() {
    if (success) {
      return 'ToolResult($toolName: success, data: $data)';
    } else {
      return 'ToolResult($toolName: failed, error: $error)';
    }
  }
}
