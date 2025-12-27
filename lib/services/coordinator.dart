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

import 'dart:async';
import '../domain/invocation.dart';
import '../domain/event.dart';
import '../domain/event_repository.dart';
import '../domain/event_retry_utils.dart';
import '../core/invocation_repository.dart';
import 'trainables/namespace_selector.dart';
import 'trainables/tool_selector.dart';
import 'trainables/context_injector.dart';
import 'trainables/llm_config_selector.dart';
import 'trainables/llm_orchestrator.dart';
import 'trainables/response_renderer.dart';
import 'embedding_service.dart';
import 'llm_service.dart';
import 'tool_executor.dart' show ToolExecutor;

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
  final EventRepository eventRepository;

  // Event loop control
  Timer? _eventLoopTimer;
  bool _isProcessingEvent = false;

  // Agentic loop control
  static const int maxAgentLoopIterations = 10;

  // Event loop interval (100ms)
  static const Duration eventLoopInterval = Duration(milliseconds: 100);

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
    required this.eventRepository,
  });

  /// Orchestrate voice assistant pipeline
  Future<CoordinatorResult> orchestrate({
    required String correlationId,
    required String utterance,
    required List<String> availableNamespaces,
    required Map<String, List<String>> toolsByNamespace,
  }) async {
    print('\n=== COORDINATOR: orchestrate START ===');
    print('🔗 CorrelationId: $correlationId');
    print('📝 Utterance: "$utterance"');

    final startTime = DateTime.now();
    final invocationIds = <String>[];

    try {
      // 1. Generate embedding
      print('\n[1/6] Generating embedding...');
      final embedding = await embeddingService.generate(utterance);
      print('✅ Embedding generated: ${embedding.isNotEmpty ? embedding.length : 0} dimensions');

      // 2. NamespaceSelector picks namespace
      print('\n[2/6] Selecting namespace...');
      final selectedNamespace = await namespaceSelector.selectNamespace(
        correlationId: correlationId,
        utterance: utterance,
        embedding: embedding,
        availableNamespaces: availableNamespaces,
      );
      print('✅ Selected namespace: "$selectedNamespace"');
      invocationIds.add('namespace_selector_invocation');

      // 3. ToolSelector picks tools
      print('\n[3/6] Selecting tools...');
      final availableTools = toolsByNamespace[selectedNamespace] ?? [];
      final selectedTools = await toolSelector.selectTools(
        correlationId: correlationId,
        namespace: selectedNamespace,
        utterance: utterance,
        embedding: embedding,
        availableTools: availableTools,
      );
      print('✅ Selected tools: ${selectedTools.isEmpty ? "none" : selectedTools.join(", ")}');
      invocationIds.add('tool_selector_invocation');

      // 4. ContextInjector injects context
      print('\n[4/6] Injecting context...');
      final injectedContext = await contextInjector.injectContext(
        correlationId: correlationId,
        namespace: selectedNamespace,
      );
      print('✅ Context injected: ${injectedContext.length} keys');
      invocationIds.add('context_injector_invocation');

      // 5. LLMConfigSelector picks config
      print('\n[5/6] Selecting LLM config...');
      final llmConfig = await llmConfigSelector.selectConfig(
        correlationId: correlationId,
        utterance: utterance,
        namespace: selectedNamespace,
        tools: selectedTools,
      );
      print('✅ LLM config: model=${llmConfig['model']}, temp=${llmConfig['temperature']}');
      invocationIds.add('llm_config_selector_invocation');

      // 6. Call LLM (MVP: no tool execution)
      print('\n[6/6] Calling LLM service...');
      print('📡 LLM call starting...');
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
      print('✅ LLM response received');
      print('📄 Response content: "${llmResponse.content}"');

      final finalResponse = llmResponse.content ?? 'No response generated';
      final toolCalls = <String>[];
      final iterations = 1;
      print('💾 Final response set to: "$finalResponse"');

      // Record LLM orchestration invocation
      print('\n📋 Recording LLM orchestration...');
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
      print('✅ LLM orchestration recorded');
      invocationIds.add('llm_orchestration_invocation');

      // 7. ResponseRenderer formats response
      print('\n🎨 Rendering response...');
      final renderedResponse = await responseRenderer.renderResponse(
        correlationId: correlationId,
        llmResponse: finalResponse,
        namespace: selectedNamespace,
        tools: selectedTools,
      );
      print('✅ Response rendered: "$renderedResponse"');
      invocationIds.add('response_renderer_invocation');

      final latency = DateTime.now().difference(startTime).inMilliseconds;
      print('\n✅ COORDINATOR: orchestrate SUCCESS');
      print('⏱️ Total latency: ${latency}ms');
      print('🔗 Invocation IDs: ${invocationIds.join(", ")}');
      print('=== COORDINATOR: orchestrate END ===\n');

      return CoordinatorResult(
        turnId: correlationId,
        selectedNamespace: selectedNamespace,
        selectedTools: selectedTools,
        injectedContext: injectedContext,
        llmConfig: llmConfig,
        finalResponse: renderedResponse,
        invocationIds: invocationIds,
        success: true,
        latencyMs: latency,
      );
    } catch (e) {
      print('\n❌ COORDINATOR: orchestrate ERROR');
      print('🚨 Exception: $e');
      print('📍 Stack trace: ${StackTrace.current}');
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      print('⏱️ Latency before error: ${latency}ms');
      print('=== COORDINATOR: orchestrate END (ERROR) ===\n');

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
        latencyMs: latency,
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

  // ============ Event Loop Management ============

  /// Start the event processing loop
  ///
  /// Runs a Timer.periodic that checks for pending events every 100ms.
  /// Non-blocking - safe for Flutter UI thread.
  void startEventLoop() {
    if (_eventLoopTimer != null && _eventLoopTimer!.isActive) {
      print('Event loop already running');
      return;
    }

    print('Starting event loop (interval: ${eventLoopInterval.inMilliseconds}ms)');
    _eventLoopTimer = Timer.periodic(eventLoopInterval, (_) async {
      await _processNextEvent();
    });
  }

  /// Stop the event processing loop
  void stopEventLoop() {
    if (_eventLoopTimer != null) {
      _eventLoopTimer!.cancel();
      _eventLoopTimer = null;
      print('Event loop stopped');
    }
  }

  /// Process next pending or retryable event
  ///
  /// Called by Timer.periodic every 100ms.
  /// Skips if already processing to prevent concurrent processing.
  Future<void> _processNextEvent() async {
    // Skip if already processing an event
    if (_isProcessingEvent) {
      return;
    }

    _isProcessingEvent = true;

    try {
      // 1. Check for pending events first (FIFO)
      Event? event = await eventRepository.dequeueAndClaim();

      // 2. If no pending events, check for retry-ready events
      if (event == null) {
        final retryable = await eventRepository.getEventsReadyForRetry();
        if (retryable.isNotEmpty) {
          event = retryable.first;
          // Claim by updating status
          event.status = EventStatus.processing;
          await eventRepository.save(event);
        }
      }

      // 3. If found an event, process it
      if (event != null) {
        await _processEvent(event);
      }
    } catch (e, stackTrace) {
      print('Error in event loop: $e');
      print('Stack trace: $stackTrace');
    } finally {
      _isProcessingEvent = false;
    }
  }

  /// Process a single event
  ///
  /// Routes event to appropriate tool handler based on event.type.
  /// Handles success, failure, and retry logic.
  Future<void> _processEvent(Event event) async {
    print('Processing event: uuid=${event.uuid}, type=${event.type}, source=${event.source}');

    try {
      // Route based on event type
      // For now, we just mark as completed
      // TODO: Wire up tool execution based on event.type
      //
      // Example routing:
      // if (event.type == 'tts') {
      //   await toolExecutor.executeTool('tts', event.payload);
      // } else if (event.type == 'teams_webhook') {
      //   await toolExecutor.executeTool('teams_webhook_handler', event.payload);
      // }

      // Mark as completed
      await eventRepository.markCompleted(event);
      print('Event completed: uuid=${event.uuid}');
    } catch (e) {
      print('Event processing failed: uuid=${event.uuid}, error=$e');

      // Decide: retry or mark failed?
      final shouldRetryEvent = shouldRetry(
        retryPolicy: event.retryPolicy,
        retryCount: event.retryCount,
        maxRetries: event.maxRetries,
      );

      if (shouldRetryEvent) {
        // Schedule retry
        final nextRetryAt = calculateNextRetryAt(
          retryPolicy: event.retryPolicy,
          retryCount: event.retryCount,
        );

        if (nextRetryAt != null) {
          await eventRepository.scheduleRetry(event, nextRetryAt);
          print('Event scheduled for retry: uuid=${event.uuid}, retryCount=${event.retryCount}, nextRetryAt=$nextRetryAt');
        } else {
          // No retry (policy is 'none')
          await eventRepository.markFailed(event, e.toString());
          print('Event failed (no retry policy): uuid=${event.uuid}');
        }
      } else {
        // Retries exhausted
        await eventRepository.markFailed(event, e.toString());
        print('Event failed (retries exhausted): uuid=${event.uuid}');
      }
    }
  }

}
