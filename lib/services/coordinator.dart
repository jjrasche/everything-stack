/// # Coordinator
///
/// ## What it does
/// Central orchestrator for the voice assistant pipeline.
/// Chains together trainable decision components + text-to-speech:
/// 1. Embedding generation (semantic representation)
/// 2. NamespaceSelector - picks namespace
/// 3. ToolSelector - picks tools within namespace
/// 4. ContextInjector - injects relevant context
/// 5. LLMConfigSelector - picks LLM parameters
/// 6. LLMOrchestrator - calls LLM + handles agentic loop
/// 7. ResponseRenderer - formats response for user
/// 8. TTSService - synthesizes response to speech (NEW)
///
/// ## Flow (Audio In → Audio Out)
/// 1. STT publishes Event(eventType: transcription_complete)
/// 2. Coordinator.orchestrate() triggered by event listener
/// 3. Generate embedding of utterance
/// 4. NamespaceSelector picks namespace
/// 5. ToolSelector picks tools in namespace
/// 6. ContextInjector injects context (tasks, timers, etc.)
/// 7. LLMConfigSelector picks LLM config (temperature, etc.)
/// 8. Call LLM with tools available (agentic loop with tool execution)
/// 9. ResponseRenderer formats final response for user
/// 10. TTSService synthesizes response → audio bytes → speaker
/// 11. Publish Event(eventType: orchestration_complete) for UI
/// 12. Record all invocations for training
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
import 'dart:convert';
import '../domain/invocation.dart';
import '../domain/event.dart';
import '../core/invocation_repository.dart';
import 'trainables/namespace_selector.dart';
import 'trainables/tool_selector.dart';
import 'trainables/context_injector.dart';
import 'trainables/llm_config_selector.dart';
import 'trainables/llm_orchestrator.dart';
import 'trainables/response_renderer.dart';
import 'embedding_service.dart';
import 'llm_service.dart';
import 'tts_service.dart';
import 'tool_executor.dart' show ToolExecutor;
import 'event_bus.dart';

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
  final TTSService ttsService;
  final ToolExecutor toolExecutor;

  final InvocationRepository<Invocation> invocationRepo;
  final EventBus eventBus;

  // Event listener subscription
  StreamSubscription<Event>? _transcriptionSubscription;

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
    required this.ttsService,
    required this.toolExecutor,
    required this.invocationRepo,
    required this.eventBus,
  });

  /// Initialize Coordinator: register event listeners
  ///
  /// Called during bootstrap after Coordinator is registered in GetIt.
  /// Subscribes to transcription_complete events from STTService via EventBus.
  /// Automatically triggers orchestration on each transcription event.
  ///
  /// This is the ONLY path for orchestration - UI should NOT call orchestrate() directly.
  void initialize() {
    print('\n🔧 [Coordinator.initialize] Wiring event listener');
    _transcriptionSubscription = eventBus.subscribe().listen(
      (event) async {
        // Filter for transcription_complete events
        if (event.eventType != 'transcription_complete') {
          return;
        }

        try {
          // Extract semantic input from event
          final inputText = event.toInputString();

          print('\n📡 [Coordinator] Heard transcription_complete: "$inputText"');
          print('🚀 [Coordinator] Starting orchestration from event...');

          final result = await orchestrate(
            correlationId: event.correlationId,
            utterance: inputText,
            availableNamespaces: ['general', 'productivity', 'entertainment'],
            toolsByNamespace: {
              'general': [],
              'productivity': [],
              'entertainment': [],
            },
          );

          print('✅ [Coordinator] Orchestration complete: ${result.success ? "SUCCESS" : "FAILED"}');
          if (!result.success) {
            print('⚠️ Error: ${result.errorMessage}');
          }

          // Publish orchestration_complete event for UI to update state
          await eventBus.publish(Event(
            eventType: 'orchestration_complete',
            correlationId: event.correlationId,
            source: 'coordinator',
            payloadJson: jsonEncode({
              'success': result.success,
              'response': result.finalResponse,
              'errorMessage': result.errorMessage,
            }),
          ));
          print('📡 [Coordinator] Published orchestration_complete event');
        } catch (e) {
          print('❌ [Coordinator] Failed to orchestrate from event: $e');
        }
      },
      onError: (error) {
        print('⚠️ [Coordinator] Event listener error: $error');
      },
    );
    print('✅ [Coordinator.initialize] Event listener registered');
  }

  /// Dispose: cleanup event listeners
  void dispose() {
    print('🛑 [Coordinator.dispose] Cleaning up event listener');
    _transcriptionSubscription?.cancel();
    print('✅ [Coordinator.dispose] Disposed');
  }

  /// Orchestrate voice assistant pipeline
  Future<CoordinatorResult> orchestrate({
    required String correlationId,
    required String utterance,
    required List<String> availableNamespaces,
    required Map<String, List<String>> toolsByNamespace,
  }) async {
    // TEMPORARY TEST: Uncomment to verify test catches failures
    // throw Exception('TEST FAILURE: Coordinator.orchestrate() intentionally broken');

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
      // COMMENTED OUT: Focus on LLM + TTS data for learning
      // print('\n[2/6] Selecting namespace...');
      // final selectedNamespace = await namespaceSelector.selectNamespace(
      //   correlationId: correlationId,
      //   utterance: utterance,
      //   embedding: embedding,
      //   availableNamespaces: availableNamespaces,
      // );
      final selectedNamespace = 'general'; // Default
      // print('✅ Selected namespace: "$selectedNamespace"');
      // invocationIds.add('namespace_selector_invocation');

      // 3. ToolSelector picks tools
      // COMMENTED OUT: Focus on LLM + TTS data for learning
      // print('\n[3/6] Selecting tools...');
      // final availableTools = toolsByNamespace[selectedNamespace] ?? [];
      // final selectedTools = await toolSelector.selectTools(
      //   correlationId: correlationId,
      //   namespace: selectedNamespace,
      //   utterance: utterance,
      //   embedding: embedding,
      //   availableTools: availableTools,
      // );
      final selectedTools = <String>[]; // No tools
      // print('✅ Selected tools: ${selectedTools.isEmpty ? "none" : selectedTools.join(", ")}');
      // invocationIds.add('tool_selector_invocation');

      // 4. ContextInjector injects context
      // COMMENTED OUT: Focus on LLM + TTS data for learning
      // print('\n[4/6] Injecting context...');
      // final injectedContext = await contextInjector.injectContext(
      //   correlationId: correlationId,
      //   namespace: selectedNamespace,
      // );
      final injectedContext = <String, dynamic>{}; // No context
      // print('✅ Context injected: ${injectedContext.length} keys');
      // invocationIds.add('context_injector_invocation');

      // 5. LLMConfigSelector picks config
      // COMMENTED OUT: Focus on LLM + TTS data for learning
      // print('\n[5/6] Selecting LLM config...');
      // final llmConfig = await llmConfigSelector.selectConfig(
      //   correlationId: correlationId,
      //   utterance: utterance,
      //   namespace: selectedNamespace,
      //   tools: selectedTools,
      // );
      final llmConfig = {
        'model': 'llama-3.1-8b-instant',
        'temperature': 0.7,
      }; // Default config
      // print('✅ LLM config: model=${llmConfig['model']}, temp=${llmConfig['temperature']}');
      // invocationIds.add('llm_config_selector_invocation');

      // 6. Call LLM (MVP: no tool execution)
      print('\n[6/6] Calling LLM service...');
      print('📡 LLM call starting...');
      final llmResponse = await llmService.chatWithTools(
        model: llmConfig['model'] as String? ?? 'llama-3.1-8b-instant',
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
      print('DEBUG: About to call llmOrchestrator.recordOrchestration');
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
      // COMMENTED OUT: Focus on LLM + TTS data for learning
      // print('\n🎨 Rendering response...');
      // final renderedResponse = await responseRenderer.renderResponse(
      //   correlationId: correlationId,
      //   llmResponse: finalResponse,
      //   namespace: selectedNamespace,
      //   tools: selectedTools,
      // );
      final renderedResponse = finalResponse; // Use LLM response as-is
      // print('✅ Response rendered: "$renderedResponse"');
      // invocationIds.add('response_renderer_invocation');

      // 8. TTS synthesizes and plays response
      print('\n🔊 Synthesizing response to speech...');
      await ttsService.synthesizeAndLog(
        text: renderedResponse,
        correlationId: correlationId,
      );
      invocationIds.add('tts_synthesis_invocation');

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
    } catch (e, stackTrace) {
      print('\n❌ COORDINATOR: orchestrate ERROR');
      print('🚨 Exception: $e');
      print('📍 Stack trace: ${StackTrace.current}');
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      print('⏱️ Latency before error: ${latency}ms');
      print('=== COORDINATOR: orchestrate END (ERROR) ===\n');

      // Publish error event (for monitoring and testing)
      final errorEvent = Event(
        eventType: 'orchestration_error',
        correlationId: correlationId,
        source: 'coordinator',
        payloadJson: jsonEncode({
          'message': e.toString(),
          'errorType': e.runtimeType.toString(),
          'stackTrace': stackTrace.toString(),
          'severity': 'error',
        }),
      );
      await eventBus.publish(errorEvent);
      print('📤 orchestration_error event published');

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

}
