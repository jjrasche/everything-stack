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

  // TODO: Inject actual tool handlers here
  // For now, all tools are stubs

  ToolExecutor({
    required this.invocationRepo,
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

  /// Execute tool by namespace (stub implementations)
  Future<ToolExecutionResult> _executeToolByNamespace({
    required String namespace,
    required String toolName,
    required Map<String, dynamic> params,
    required String callId,
    required String correlationId,
  }) async {
    // TODO: Implement real tool handlers
    // For now, all tools return stub success

    // Example: if (namespace == 'task' && toolName == 'create') { ... }

    return ToolExecutionResult(
      toolName: '$namespace.$toolName',
      success: true,
      data: {
        'message': 'Tool execution stubbed - implement real handler',
        'params': params,
        'callId': callId,
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
