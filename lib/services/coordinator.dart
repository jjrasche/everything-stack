/// # Coordinator
///
/// ## What it does
/// Central orchestrator for the voice assistant pipeline.
/// Chains together 5 Trainable decision components:
/// 1. NamespaceSelector - picks namespace
/// 2. ToolSelector - picks tools within namespace
/// 3. ContextInjector - injects relevant context
/// 4. LLMConfigSelector - picks LLM parameters
/// 5. Orchestrates LLM call + tool execution (agentic loop)
/// 6. ResponseRenderer - formats response for user
///
/// ## Flow
/// 1. User provides utterance + embedding
/// 2. NamespaceSelector picks namespace
/// 3. ToolSelector picks tools in namespace
/// 4. ContextInjector injects context (tasks, timers, etc.)
/// 5. LLMConfigSelector picks LLM config (temperature, etc.)
/// 6. Call LLM with tools available
/// 7. If tools called: execute them, send results back to LLM
/// 8. Repeat 6-7 until LLM says done (max iterations)
/// 9. ResponseRenderer formats final response
/// 10. Return result with all invocations recorded
///
/// ## Agentic Loop
/// The LLM has tools available. If it requests tool calls:
/// 1. Parse tool calls from LLM response
/// 2. Execute each tool (via ToolExecutor)
/// 3. Collect results
/// 4. Send results back to LLM
/// 5. LLM responds again (may call more tools or finish)
/// 6. Repeat until LLM produces final_response (no tool calls)

import '../domain/invocation.dart';
import '../core/invocation_repository.dart';
import 'trainables/namespace_selector.dart';
import 'trainables/tool_selector.dart';
import 'trainables/context_injector.dart';
import 'trainables/llm_config_selector.dart';
import 'trainables/llm_orchestrator.dart';
import 'trainables/response_renderer.dart';
import 'embedding_service.dart';
import 'llm_service.dart';
import 'tool_executor.dart' show ToolExecutor, ToolCall;

/// Result of coordinator orchestration
class CoordinatorResult {
  /// Unique ID for this turn
  final String turnId;

  /// Selected namespace
  final String selectedNamespace;

  /// Selected tools
  final List<String> selectedTools;

  /// Injected context
  final Map<String, dynamic> injectedContext;

  /// LLM configuration used
  final Map<String, dynamic> llmConfig;

  /// Final response to user
  final String finalResponse;

  /// All invocations recorded (for training)
  final List<String> invocationIds;

  /// Did orchestration succeed?
  final bool success;

  /// Error message if !success
  final String? errorMessage;

  /// Total latency
  final int latencyMs;

  CoordinatorResult({
    required this.turnId,
    required this.selectedNamespace,
    required this.selectedTools,
    required this.injectedContext,
    required this.llmConfig,
    required this.finalResponse,
    required this.invocationIds,
    required this.success,
    this.errorMessage,
    required this.latencyMs,
  });
}

/// Central coordinator orchestrating all trainable decisions
class Coordinator {
  final NamespaceSelector namespaceSelector;
  final ToolSelector toolSelector;
  final ContextInjector contextInjector;
  final LLMConfigSelector llmConfigSelector;
  final LLMOrchestrator llmOrchestrator;
  final ResponseRenderer responseRenderer;
  final EmbeddingService embeddingService;
  final LLMService llmService;
  final ToolExecutor toolExecutor;

  final InvocationRepository<Invocation> invocationRepo;

  // Agentic loop control
  static const int maxAgentLoopIterations = 10;

  Coordinator({
    required this.namespaceSelector,
    required this.toolSelector,
    required this.contextInjector,
    required this.llmConfigSelector,
    required this.llmOrchestrator,
    required this.responseRenderer,
    required this.embeddingService,
    required this.llmService,
    required this.toolExecutor,
    required this.invocationRepo,
  });

  /// Orchestrate voice assistant pipeline
  Future<CoordinatorResult> orchestrate({
    required String correlationId,
    required String utterance,
    required List<String> availableNamespaces,
    required Map<String, List<String>> toolsByNamespace,
  }) async {
    final startTime = DateTime.now();
    final invocationIds = <String>[];

    try {
      // 1. Generate embedding
      final embedding = await embeddingService.generate(utterance);

      // 2. NamespaceSelector picks namespace
      final selectedNamespace = await namespaceSelector.selectNamespace(
        correlationId: correlationId,
        utterance: utterance,
        embedding: embedding,
        availableNamespaces: availableNamespaces,
      );
      invocationIds.add('namespace_selector_invocation');

      // 3. ToolSelector picks tools
      final availableTools = toolsByNamespace[selectedNamespace] ?? [];
      final selectedTools = await toolSelector.selectTools(
        correlationId: correlationId,
        namespace: selectedNamespace,
        utterance: utterance,
        embedding: embedding,
        availableTools: availableTools,
      );
      invocationIds.add('tool_selector_invocation');

      // 4. ContextInjector injects context
      final injectedContext = await contextInjector.injectContext(
        correlationId: correlationId,
        namespace: selectedNamespace,
      );
      invocationIds.add('context_injector_invocation');

      // 5. LLMConfigSelector picks config
      final llmConfig = await llmConfigSelector.selectConfig(
        correlationId: correlationId,
        utterance: utterance,
        namespace: selectedNamespace,
        tools: selectedTools,
      );
      invocationIds.add('llm_config_selector_invocation');

      // 6. Agentic loop: Call LLM, execute tools, repeat until done
      final agenticLoopResult = await _agenticLoop(
        correlationId: correlationId,
        utterance: utterance,
        namespace: selectedNamespace,
        tools: selectedTools,
        context: injectedContext,
        config: llmConfig,
      );
      final finalResponse = agenticLoopResult['response'] as String;
      final toolCalls = agenticLoopResult['toolCalls'] as List<String>;
      final iterations = agenticLoopResult['iterations'] as int;

      // Record LLM orchestration invocation
      await llmOrchestrator.recordOrchestration(
        correlationId: correlationId,
        utterance: utterance,
        namespace: selectedNamespace,
        tools: selectedTools,
        context: injectedContext,
        finalResponse: finalResponse,
        toolCalls: toolCalls,
        iterations: iterations,
        success: true,
      );
      invocationIds.add('llm_orchestration_invocation');

      // 7. ResponseRenderer formats response
      final renderedResponse = await responseRenderer.renderResponse(
        correlationId: correlationId,
        llmResponse: finalResponse,
        namespace: selectedNamespace,
        tools: selectedTools,
      );
      invocationIds.add('response_renderer_invocation');

      return CoordinatorResult(
        turnId: correlationId,
        selectedNamespace: selectedNamespace,
        selectedTools: selectedTools,
        injectedContext: injectedContext,
        llmConfig: llmConfig,
        finalResponse: renderedResponse,
        invocationIds: invocationIds,
        success: true,
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      return CoordinatorResult(
        turnId: correlationId,
        selectedNamespace: '',
        selectedTools: [],
        injectedContext: {},
        llmConfig: {},
        finalResponse: '',
        invocationIds: invocationIds,
        success: false,
        errorMessage: e.toString(),
        latencyMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    }
  }

  /// Agentic loop: LLM orchestration with tool execution
  /// Returns map with 'response', 'toolCalls', and 'iterations' keys
  Future<Map<String, dynamic>> _agenticLoop({
    required String correlationId,
    required String utterance,
    required String namespace,
    required List<String> tools,
    required Map<String, dynamic> context,
    required Map<String, dynamic> config,
  }) async {
    final systemPrompt = _buildSystemPrompt(
      namespace: namespace,
      tools: tools,
      context: context,
    );

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt,
      },
      {
        'role': 'user',
        'content': utterance,
      },
    ];

    final allToolCalls = <String>[];
    var iteration = 0;
    while (iteration < maxAgentLoopIterations) {
      iteration++;

      // Call LLM
      final llmResponse = await llmService.chatWithTools(
        model: config['model'] as String? ?? 'groq-mixtral',
        messages: messages,
        tools: _buildToolDefinitions(tools),
        temperature: (config['temperature'] as num?)?.toDouble() ?? 0.7,
      );

      messages.add({
        'role': 'assistant',
        'content': llmResponse.content ?? '',
      });

      final toolCalls = llmResponse.toolCalls;

      if (toolCalls.isEmpty) {
        return {
          'response': llmResponse.content ?? 'No response generated',
          'toolCalls': allToolCalls,
          'iterations': iteration,
        };
      }

      // Track tool calls for recording
      for (final toolCall in toolCalls) {
        allToolCalls.add(toolCall.toolName);
      }

      final toolResults = <Map<String, dynamic>>[];
      for (final toolCall in toolCalls) {
        try {
          final result = await toolExecutor.executeTool(
            ToolCall(
              toolName: toolCall.toolName,
              params: toolCall.params,
              callId: toolCall.id,
            ),
            correlationId: correlationId,
          );

          await toolExecutor.recordToolExecution(
            correlationId: correlationId,
            toolCall: ToolCall(
              toolName: toolCall.toolName,
              params: toolCall.params,
              callId: toolCall.id,
            ),
            result: result,
          );

          toolResults.add({
            'toolName': result.toolName,
            'success': result.success,
            'data': result.data,
            'error': result.error,
          });
        } catch (e) {
          toolResults.add({
            'toolName': toolCall.toolName,
            'success': false,
            'error': e.toString(),
          });
        }
      }

      messages.add({
        'role': 'user',
        'content': 'Tool results:\n${_formatToolResults(toolResults)}',
      });
    }

    return {
      'response': 'Tool execution loop exceeded maximum iterations ($maxAgentLoopIterations)',
      'toolCalls': allToolCalls,
      'iterations': maxAgentLoopIterations,
    };
  }

  String _buildSystemPrompt({
    required String namespace,
    required List<String> tools,
    required Map<String, dynamic> context,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('You are a helpful assistant.');
    buffer.writeln('Namespace: $namespace');
    buffer.writeln('Available tools: ${tools.join(", ")}');

    if (context.isNotEmpty) {
      buffer.writeln('\nContext:');
      context.forEach((key, value) {
        buffer.writeln('- $key: $value');
      });
    }

    return buffer.toString();
  }

  List<LLMTool> _buildToolDefinitions(List<String> tools) {
    return tools
        .map((tool) => LLMTool(
              name: tool,
              description: 'Tool: $tool',
              parameters: {
                'type': 'object',
                'properties': {},
              },
            ))
        .toList();
  }

  String _formatToolResults(List<Map<String, dynamic>> results) {
    return results
        .map((r) =>
            '${r['toolName']}: ${r['success'] ? "Success - ${r['data']}" : "Failed - ${r['error']}"}')
        .join('\n');
  }
}
