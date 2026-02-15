import 'dart:convert';
import '../core/invocation.dart';
import '../core/trainable.dart';
import '../core/adaptation_data.dart';
import '../core/event.dart';
import 'tool_registry.dart';
import 'event_bus.dart';

/// Placeholder adaptation data for ToolExecutor.
/// Currently no trainable parameters - this is a stub for future training.
class ToolExecutorAdaptationData extends AdaptationData {
  ToolExecutorAdaptationData();

  factory ToolExecutorAdaptationData.fromJson(Map<String, dynamic> json) {
    return ToolExecutorAdaptationData();
  }

  @override
  String toJson() => '{}';
}

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

/// Executes LLM-requested tools via registry lookup
class ToolExecutor with Trainable<ToolExecutorAdaptationData> {
  final ToolRegistry toolRegistry;
  final EventBus eventBus;

  ToolExecutor({
    required this.toolRegistry,
    required this.eventBus,
  });

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'tool_executor';

  @override
  ToolExecutorAdaptationData createDefaultData() =>
      ToolExecutorAdaptationData();

  @override
  ToolExecutorAdaptationData deserializeData(String json) =>
      ToolExecutorAdaptationData.fromJson(
        Map<String, dynamic>.from(
          const JsonDecoder().convert(json) as Map,
        ),
      );

  // ============ Tool Execution ============

  /// Execute a tool call
  Future<ToolExecutionResult> executeTool(
    ToolCall toolCall, {
    required String eventId,
  }) async {
    final startTime = DateTime.now();

    try {
      // Parse tool name (format: "namespace.toolName")
      final parts = toolCall.toolName.split('.');
      if (parts.length != 2) {
        final result = ToolExecutionResult(
          toolName: toolCall.toolName,
          success: false,
          error: 'Invalid tool name format',
        );

        // Record failed execution
        await recordInvocation(
          eventId,
          Invocation(
            eventId: eventId,
            componentType: componentType,
            success: false,
            confidence: toolCall.confidence,
            input: {
              'toolName': toolCall.toolName,
              'params': toolCall.params,
            },
            output: {
              'result': result.toJson(),
            },
          ),
        );

        return result;
      }

      final namespace = parts[0];
      final toolName = parts[1];

      final result = await _executeToolByNamespace(
        namespace: namespace,
        toolName: toolName,
        params: toolCall.params,
        callId: toolCall.callId,
        eventId: eventId,
      );

      final executionResult = ToolExecutionResult(
        toolName: toolCall.toolName,
        success: result.success,
        data: result.data,
        error: result.error,
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );

      // Record execution invocation (standardized pattern)
      await recordInvocation(
        eventId,
        Invocation(
          eventId: eventId,
          componentType: componentType,
          success: executionResult.success,
          confidence: toolCall.confidence,
          input: {
            'toolName': toolCall.toolName,
            'params': toolCall.params,
          },
          output: {
            'result': executionResult.toJson(),
          },
        ),
      );

      // Publish tool_call_executed event for UI visibility
      await eventBus.publish(Event(
        eventType: 'tool_call_executed',
        correlationId: eventId,
        source: 'tool_executor',
        payloadJson: jsonEncode({
          'tool_name': toolCall.toolName,
          'success': executionResult.success,
          'result': executionResult.data,
          'error': executionResult.error,
        }),
      ));

      return executionResult;
    } catch (e) {
      final result = ToolExecutionResult(
        toolName: toolCall.toolName,
        success: false,
        error: e.toString(),
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );

      // Record exception
      await recordInvocation(
        eventId,
        Invocation(
          eventId: eventId,
          componentType: componentType,
          success: false,
          confidence: toolCall.confidence,
          input: {
            'toolName': toolCall.toolName,
            'params': toolCall.params,
          },
          output: {
            'result': result.toJson(),
          },
        ),
      );

      return result;
    }
  }

  /// Execute multiple tool calls
  Future<List<ToolExecutionResult>> executeTools(
    List<ToolCall> toolCalls, {
    required String eventId,
  }) async {
    final results = <ToolExecutionResult>[];

    for (final toolCall in toolCalls) {
      final result = await executeTool(
        toolCall,
        eventId: eventId,
      );
      results.add(result);
    }

    return results;
  }

  /// Execute tool by registry lookup
  Future<ToolExecutionResult> _executeToolByNamespace({
    required String namespace,
    required String toolName,
    required Map<String, dynamic> params,
    required String callId,
    required String eventId,
  }) async {
    final fullToolName = '$namespace.$toolName';

    try {
      // Look up tool in registry
      final fn = toolRegistry.getTool(fullToolName);
      if (fn == null) {
        return ToolExecutionResult(
          toolName: fullToolName,
          success: false,
          error: 'Unknown tool: $fullToolName',
        );
      }

      final data = await fn(params);

      return ToolExecutionResult(
        toolName: fullToolName,
        success: true,
        data: data,
      );
    } catch (e) {
      return ToolExecutionResult(
        toolName: fullToolName,
        success: false,
        error: e.toString(),
      );
    }
  }
}
