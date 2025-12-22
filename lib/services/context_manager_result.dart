/// # ContextManagerResult
///
/// ## What it does
/// Value object returned by ContextManager.handleEvent().
/// Contains tool selection, execution results, and LLM response.
///
/// ## Usage
/// ```dart
/// final result = await contextManager.handleEvent(event);
///
/// if (result.error != null) {
///   // Handle error
/// } else if (result.toolCalls.isEmpty) {
///   // No tools selected (below threshold)
/// } else {
///   // Tools were executed
///   for (final execResult in result.executionResults) {
///     if (execResult.success) {
///       print('Tool ${execResult.toolName} succeeded');
///     }
///   }
///
///   // LLM's final response after seeing execution results
///   print('LLM: ${result.llmResponse}');
/// }
/// ```

import 'tool_executor.dart';

class ContextManagerResult {
  /// Which namespace was selected (null if none passed threshold)
  final String? selectedNamespace;

  /// Tool calls the LLM wants to execute (0-N)
  final List<ToolCall> toolCalls;

  /// Overall confidence in this decision (0.0-1.0)
  final double confidence;

  /// UUID of the ContextManagerInvocation logged for this decision
  final String invocationId;

  /// Context assembled and passed to LLM
  final Map<String, dynamic> assembledContext;

  /// Execution results from tool handlers (empty if tools weren't executed)
  final List<ToolResult> executionResults;

  /// LLM's final response after seeing execution results
  final String? llmResponse;

  /// Error message if something failed
  final String? error;

  /// Error type: 'llm_timeout', 'llm_error', 'no_namespace', 'no_tools', 'execution_error'
  final String? errorType;

  ContextManagerResult({
    this.selectedNamespace,
    required this.toolCalls,
    required this.confidence,
    required this.invocationId,
    required this.assembledContext,
    this.executionResults = const [],
    this.llmResponse,
    this.error,
    this.errorType,
  });

  /// Did this result in an error?
  bool get hasError => error != null;

  /// Were any tools selected?
  bool get hasToolCalls => toolCalls.isNotEmpty;

  /// Success factory
  factory ContextManagerResult.success({
    required String selectedNamespace,
    required List<ToolCall> toolCalls,
    required double confidence,
    required String invocationId,
    required Map<String, dynamic> assembledContext,
    List<ToolResult>? executionResults,
    String? llmResponse,
  }) {
    return ContextManagerResult(
      selectedNamespace: selectedNamespace,
      toolCalls: toolCalls,
      confidence: confidence,
      invocationId: invocationId,
      assembledContext: assembledContext,
      executionResults: executionResults ?? [],
      llmResponse: llmResponse,
    );
  }

  /// No namespace passed threshold
  factory ContextManagerResult.noNamespace({
    required String invocationId,
  }) {
    return ContextManagerResult(
      toolCalls: [],
      confidence: 0.0,
      invocationId: invocationId,
      assembledContext: {},
      error: 'No namespace passed semantic threshold',
      errorType: 'no_namespace',
    );
  }

  /// No tools passed threshold in selected namespace
  factory ContextManagerResult.noTools({
    required String selectedNamespace,
    required String invocationId,
  }) {
    return ContextManagerResult(
      selectedNamespace: selectedNamespace,
      toolCalls: [],
      confidence: 0.0,
      invocationId: invocationId,
      assembledContext: {},
      error: 'No tools passed threshold in namespace $selectedNamespace',
      errorType: 'no_tools',
    );
  }

  /// Error factory
  factory ContextManagerResult.error({
    required String invocationId,
    required String error,
    required String errorType,
  }) {
    return ContextManagerResult(
      toolCalls: [],
      confidence: 0.0,
      invocationId: invocationId,
      assembledContext: {},
      error: error,
      errorType: errorType,
    );
  }
}

/// Represents a single tool call to execute
class ToolCall {
  /// Full tool name: "task.create", "timer.set"
  final String toolName;

  /// Parameters for this tool call
  final Map<String, dynamic> params;

  /// Confidence in this specific tool selection (0.0-1.0)
  final double confidence;

  /// Groq's tool call ID (for response tracking)
  final String? callId;

  ToolCall({
    required this.toolName,
    required this.params,
    required this.confidence,
    this.callId,
  });

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'params': params,
        'confidence': confidence,
        'callId': callId,
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      toolName: json['toolName'] as String,
      params: json['params'] as Map<String, dynamic>,
      confidence: (json['confidence'] as num).toDouble(),
      callId: json['callId'] as String?,
    );
  }
}
