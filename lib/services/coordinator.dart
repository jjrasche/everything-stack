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

      // 6. Call LLM (MVP: no tool execution)
      final llmResponse = await llmService.chatWithTools(
        model: llmConfig['model'] as String? ?? 'groq-mixtral',
        messages: [
          {
            'role': 'system',
            'content': _buildSystemPrompt(
              namespace: selectedNamespace,
              tools: selectedTools,
              context: injectedContext,
            ),
          },
          {'role': 'user', 'content': utterance},
        ],
        tools: _buildToolDefinitions(selectedTools),
        temperature: (llmConfig['temperature'] as num?)?.toDouble() ?? 0.7,
      );
      final finalResponse = llmResponse.content ?? 'No response generated';
      final toolCalls = <String>[];
      final iterations = 1;

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

}
