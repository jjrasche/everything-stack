import 'dart:convert';
import '../core/invocation.dart';
import '../core/trainable.dart';
import '../core/adaptation_data.dart';
import '../core/event.dart';
import 'tool_registry.dart';
import 'event_bus.dart';

class ToolExecutorAdaptationData extends AdaptationData {
  ToolExecutorAdaptationData();

  factory ToolExecutorAdaptationData.fromJson(Map<String, dynamic> json) {
    return ToolExecutorAdaptationData();
  }

  @override
  String toJson() => '{}';
}

class ToolExecutionResult {
  final String toolName;
  final bool success;
  final dynamic toolOutput;
  final String? error;
  final int? latencyMs;

  ToolExecutionResult({
    required this.toolName,
    required this.success,
    this.toolOutput,
    this.error,
    this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'success': success,
        'data': toolOutput,
        'error': error,
        'latencyMs': latencyMs,
      };
}

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

  Future<ToolExecutionResult> executeTool(
    ToolCall toolCall, {
    required String eventId,
  }) async {
    final startTime = DateTime.now();

    try {
      final nameSegments = toolCall.toolName.split('.');
      if (nameSegments.length != 2) {
        final invalidNameResult = ToolExecutionResult(
          toolName: toolCall.toolName,
          success: false,
          error: 'Invalid tool name format',
        );

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
              'result': invalidNameResult.toJson(),
            },
          ),
        );

        return invalidNameResult;
      }

      final namespace = nameSegments[0];
      final toolName = nameSegments[1];

      final namespaceResult = await _executeToolByNamespace(
        namespace: namespace,
        toolName: toolName,
        params: toolCall.params,
        callId: toolCall.callId,
        eventId: eventId,
      );

      final executionResult = ToolExecutionResult(
        toolName: toolCall.toolName,
        success: namespaceResult.success,
        toolOutput: namespaceResult.toolOutput,
        error: namespaceResult.error,
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );

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

      await eventBus.publish(Event(
        eventType: 'tool_call_executed',
        correlationId: eventId,
        source: 'tool_executor',
        payloadJson: jsonEncode({
          'tool_name': toolCall.toolName,
          'success': executionResult.success,
          'result': executionResult.toolOutput,
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

  Future<List<ToolExecutionResult>> executeTools(
    List<ToolCall> toolCalls, {
    required String eventId,
  }) async {
    final executionResults = <ToolExecutionResult>[];

    for (final toolCall in toolCalls) {
      final executionResult = await executeTool(
        toolCall,
        eventId: eventId,
      );
      executionResults.add(executionResult);
    }

    return executionResults;
  }

  Future<ToolExecutionResult> _executeToolByNamespace({
    required String namespace,
    required String toolName,
    required Map<String, dynamic> params,
    required String callId,
    required String eventId,
  }) async {
    final fullToolName = '$namespace.$toolName';

    try {
      final toolFunction = toolRegistry.getTool(fullToolName);
      if (toolFunction == null) {
        return ToolExecutionResult(
          toolName: fullToolName,
          success: false,
          error: 'Unknown tool: $fullToolName',
        );
      }

      final toolOutput = await toolFunction(params);

      return ToolExecutionResult(
        toolName: fullToolName,
        success: true,
        toolOutput: toolOutput,
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
