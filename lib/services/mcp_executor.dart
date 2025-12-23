/// # MCPExecutor
///
/// ## What it does
/// Orchestrates the agent loop: LLM calls tools → execute → LLM sees results → repeat.
/// Handles multi-turn tool execution and prevents infinite loops.
///
/// ## Flow
/// 1. Call LLM with filtered tools
/// 2. LLM returns tool calls
/// 3. Execute via ToolExecutor (in-app handlers)
/// 4. Send results back to LLM as messages
/// 5. If LLM calls more tools, loop to step 2
/// 6. If LLM responds with text, we're done
/// 7. Return final execution results
///
/// ## Usage
/// ```dart
/// final executor = MCPExecutor(
///   llmService: groqService,
///   toolExecutor: toolExecutor,
///   maxTurns: 5,
/// );
///
/// final result = await executor.execute(
///   personality: personality,
///   utterance: 'Create a task and set a timer',
///   tools: filteredTools,
///   context: assembledContext,
/// );
///
/// if (result.success) {
///   print('Executed ${result.toolResults.length} tools');
///   print('LLM response: ${result.finalResponse}');
/// }
/// ```

import 'dart:convert';

import '../domain/personality.dart';
import '../domain/tool.dart';
import '../domain/invocations.dart';
import 'llm_service.dart';
import 'tool_executor.dart';
import 'context_manager_result.dart';

class MCPExecutor {
  final LLMService llmService;
  final ToolExecutor toolExecutor;
  final int maxTurns;

  MCPExecutor({
    required this.llmService,
    required this.toolExecutor,
    this.maxTurns = 5,
  });

  /// Execute tools with LLM orchestration
  ///
  /// Returns execution result with all tool calls and final LLM response.
  /// If correlationId is provided, records LLM invocations for training.
  Future<MCPExecutionResult> execute({
    required Personality personality,
    required String utterance,
    required List<Tool> tools,
    required Map<String, dynamic> context,
    String? correlationId,
  }) async {
    // Build initial messages
    final messages = <Map<String, dynamic>>[];

    // System prompt
    messages.add({
      'role': 'system',
      'content': personality.systemPrompt,
    });

    // Context (if available)
    if (context.isNotEmpty) {
      final contextStr = _formatContext(context);
      messages.add({
        'role': 'system',
        'content': 'Current context:\n$contextStr',
      });
    }

    // User message
    final userMessage =
        personality.userPromptTemplate.replaceAll('{input}', utterance);
    messages.add({
      'role': 'user',
      'content': userMessage,
    });

    // Convert Tool entities → LLMTool DTOs
    final llmTools = tools.map((tool) {
      return LLMTool(
        name: tool.fullName,
        description: tool.description,
        parameters: tool.parameters.isEmpty
            ? {
                'type': 'object',
                'properties': {},
              }
            : tool.parameters,
      );
    }).toList();

    // Agent loop
    final allToolResults = <ToolResult>[];
    final allToolCalls = <ToolCall>[];
    int turn = 0;

    while (turn < maxTurns) {
      turn++;

      // Call LLM
      final llmResponse = await llmService.chatWithTools(
        model: personality.baseModel,
        messages: messages,
        tools: llmTools,
        temperature: personality.temperature,
      );

      // Record LLM invocation for training if correlationId provided
      if (correlationId != null) {
        final llmInvocation = LLMInvocation(
          correlationId: correlationId,
          systemPromptVersion: '1.0', // TODO: Track actual version
          conversationHistoryLength: messages.length,
          response: llmResponse.content ?? '',
          tokenCount: llmResponse.tokensUsed,
        );
        await llmService.recordInvocation(llmInvocation);
      }

      // No tool calls - LLM is done
      if (!llmResponse.hasToolCalls) {
        return MCPExecutionResult(
          success: true,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          finalResponse: llmResponse.content,
          turns: turn,
        );
      }

      // Convert LLMToolCall → ToolCall
      final toolCalls = llmResponse.toolCalls.map((llmCall) {
        return ToolCall(
          toolName: llmCall.toolName,
          params: llmCall.params,
          confidence: 0.0, // Will be filled by ContextManager from tool scores
          callId: llmCall.id,
        );
      }).toList();

      allToolCalls.addAll(toolCalls);

      // Execute tool calls via ToolExecutor
      final toolResults = await toolExecutor.executeToolCalls(toolCalls);
      allToolResults.addAll(toolResults);

      // Add assistant's tool calls to message history
      messages.add({
        'role': 'assistant',
        'content': null,
        'tool_calls': llmResponse.toolCalls.map((tc) {
          return {
            'id': tc.id,
            'type': 'function',
            'function': {
              'name': tc.toolName,
              'arguments': jsonEncode(tc.params),
            },
          };
        }).toList(),
      });

      // Add tool results to message history
      for (final result in toolResults) {
        messages.add({
          'role': 'tool',
          'tool_call_id': result.callId,
          'content': result.success
              ? jsonEncode(result.data)
              : 'Error: ${result.error}',
        });
      }

      // Check if all tools failed - abort early
      if (toolResults.every((r) => !r.success)) {
        return MCPExecutionResult(
          success: false,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          error: 'All tool executions failed',
          errorType: 'execution_failed',
          turns: turn,
        );
      }

      // Loop continues - LLM will see results and decide next action
    }

    // Max turns reached
    return MCPExecutionResult(
      success: false,
      toolCalls: allToolCalls,
      toolResults: allToolResults,
      error: 'Max turns ($maxTurns) reached',
      errorType: 'max_turns_exceeded',
      turns: turn,
    );
  }

  /// Format context for LLM
  String _formatContext(Map<String, dynamic> context) {
    final buffer = StringBuffer();

    if (context['tasks'] != null) {
      final tasks = context['tasks'] as List;
      if (tasks.isNotEmpty) {
        buffer.writeln('Open tasks:');
        for (final task in tasks) {
          buffer.writeln(
              '- ${task['title']} (priority: ${task['priority']})');
        }
      }
    }

    if (context['timers'] != null) {
      final timers = context['timers'] as List;
      if (timers.isNotEmpty) {
        buffer.writeln('\nActive timers:');
        for (final timer in timers) {
          buffer.writeln(
              '- ${timer['label']} (${timer['remainingSeconds']}s remaining)');
        }
      }
    }

    return buffer.toString();
  }
}

/// Result of executing tools with LLM orchestration
class MCPExecutionResult {
  final bool success;
  final List<ToolCall> toolCalls;
  final List<ToolResult> toolResults;
  final String? finalResponse;
  final String? error;
  final String? errorType;
  final int turns;

  MCPExecutionResult({
    required this.success,
    required this.toolCalls,
    required this.toolResults,
    this.finalResponse,
    this.error,
    this.errorType,
    required this.turns,
  });

  @override
  String toString() {
    if (success) {
      return 'MCPExecutionResult(success, ${toolCalls.length} tools, $turns turns)';
    } else {
      return 'MCPExecutionResult(failed: $error)';
    }
  }
}
