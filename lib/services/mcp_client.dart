/// # MCPClient
///
/// ## What it does
/// Executes tool calls by routing them to MCP servers via HTTP.
/// Handles parallel execution and error reporting.
///
/// ## Flow
/// 1. Take List<ToolCall> from ContextManager
/// 2. For each tool call:
///    - Lookup MCP server via MCPServerRegistry
///    - POST to server's /tools/call endpoint
///    - Parse response
/// 3. Execute all calls in parallel
/// 4. Return List<MCPToolResult> with successes/failures
///
/// ## Usage
/// ```dart
/// final client = MCPClient(
///   registry: mcpServerRegistry,
///   timeout: Duration(seconds: 30),
/// );
///
/// final results = await client.executeToolCalls([
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

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'mcp_server_registry.dart';
import 'context_manager_result.dart';

class MCPClient {
  final MCPServerRegistry registry;
  final Duration timeout;

  MCPClient({
    required this.registry,
    this.timeout = const Duration(seconds: 30),
  });

  /// Execute multiple tool calls in parallel
  ///
  /// Returns results for all calls, even if some fail.
  /// Failed calls have success=false and error message populated.
  Future<List<MCPToolResult>> executeToolCalls(List<ToolCall> toolCalls) async {
    // Execute all calls in parallel
    final futures = toolCalls.map((call) => _executeSingleCall(call));
    return Future.wait(futures);
  }

  /// Execute a single tool call
  Future<MCPToolResult> _executeSingleCall(ToolCall toolCall) async {
    try {
      // Find MCP server for this tool
      final server = registry.findServer(toolCall.toolName);
      if (server == null) {
        return MCPToolResult(
          toolName: toolCall.toolName,
          callId: toolCall.callId,
          success: false,
          error: 'No MCP server registered for tool: ${toolCall.toolName}',
          errorType: 'server_not_found',
        );
      }

      // Make HTTP POST to server
      final response = await http
          .post(
            Uri.parse(server.url('/tools/call')),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': toolCall.toolName,
              'params': toolCall.params,
              'call_id': toolCall.callId,
            }),
          )
          .timeout(timeout);

      // Parse response
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MCPToolResult(
          toolName: toolCall.toolName,
          callId: toolCall.callId,
          success: true,
          data: data,
        );
      } else if (response.statusCode >= 500) {
        return MCPToolResult(
          toolName: toolCall.toolName,
          callId: toolCall.callId,
          success: false,
          error: 'MCP server error: ${response.statusCode} - ${response.body}',
          errorType: 'server_error',
        );
      } else if (response.statusCode == 400) {
        // Client error (bad params, invalid tool, etc.)
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        return MCPToolResult(
          toolName: toolCall.toolName,
          callId: toolCall.callId,
          success: false,
          error: errorData['error'] as String? ?? 'Bad request',
          errorType: 'client_error',
        );
      } else {
        return MCPToolResult(
          toolName: toolCall.toolName,
          callId: toolCall.callId,
          success: false,
          error: 'Unexpected status code: ${response.statusCode}',
          errorType: 'unknown_error',
        );
      }
    } on TimeoutException {
      return MCPToolResult(
        toolName: toolCall.toolName,
        callId: toolCall.callId,
        success: false,
        error: 'Tool execution timeout after ${timeout.inSeconds}s',
        errorType: 'timeout',
      );
    } catch (e) {
      return MCPToolResult(
        toolName: toolCall.toolName,
        callId: toolCall.callId,
        success: false,
        error: 'Execution failed: $e',
        errorType: 'execution_error',
      );
    }
  }
}

/// Result of executing a tool via MCP
class MCPToolResult {
  final String toolName;
  final String? callId;
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;
  final String? errorType;

  MCPToolResult({
    required this.toolName,
    this.callId,
    required this.success,
    this.data,
    this.error,
    this.errorType,
  });

  @override
  String toString() {
    if (success) {
      return 'MCPToolResult($toolName: success, data: $data)';
    } else {
      return 'MCPToolResult($toolName: failed, error: $error)';
    }
  }
}
