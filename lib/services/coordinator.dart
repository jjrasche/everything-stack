/// # Coordinator
///
/// ## What it does
/// Central orchestrator for the voice assistant pipeline.
/// Orchestrates LLM + TTS for end-to-end voice interaction:
/// 1. Embedding generation (semantic representation)
/// 2. InferenceService - calls LLM with tools (includes agentic loop)
/// 3. TTSService - synthesizes response to speech
///
/// ## Flow (Audio In → Audio Out)
/// 1. STT publishes Event(eventType: transcription_complete)
/// 2. Coordinator.orchestrate() triggered by event listener
/// 3. Generate embedding of utterance
/// 4. Call LLM with tools available (agentic loop with tool execution)
/// 5. TTSService synthesizes response → audio bytes → speaker
/// 6. Publish Event(eventType: orchestration_complete) for UI
/// 7. Record all invocations for training
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
import '../core/invocation.dart';
import '../core/event.dart';
import '../core/invocation_repository.dart';
import 'embedding_service.dart';
import 'inference_service.dart';
import 'tts_service.dart';
import 'tool_executor.dart' show ToolExecutor, ToolCall;
import 'event_bus.dart';
import 'context_selector.dart';
import 'types/context_selector_types.dart';
import 'types/llm_types.dart';

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

/// Central coordinator orchestrating voice assistant pipeline
class Coordinator {
  final EmbeddingService embeddingService;
  final InferenceService llmService;
  final TTSService ttsService;
  final ToolExecutor toolExecutor;
  final ContextSelector contextSelector;

  final InvocationRepository<Invocation> invocationRepo;
  final EventBus eventBus;

  // Event listener subscription
  StreamSubscription<Event>? _transcriptionSubscription;

  // Agentic loop control
  static const int maxAgentLoopIterations = 10;

  Coordinator({
    required this.embeddingService,
    required this.llmService,
    required this.ttsService,
    required this.toolExecutor,
    required this.contextSelector,
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
            eventId: event.uuid,
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
            correlationId: event.uuid,
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
    required String eventId,
    required String utterance,
    required List<String> availableNamespaces,
    required Map<String, List<String>> toolsByNamespace,
  }) async {
    // TEMPORARY TEST: Uncomment to verify test catches failures
    // throw Exception('TEST FAILURE: Coordinator.orchestrate() intentionally broken');

    print('\n=== COORDINATOR: orchestrate START ===');
    print('🔗 EventId: $eventId');
    print('📝 Utterance: "$utterance"');

    final startTime = DateTime.now();
    final invocationIds = <String>[];

    try {
      // 1. Select context using ContextSelector (dual temporal decay)
      print('\n[1/4] Selecting context via ContextSelector...');
      final contextBundle = await contextSelector.selectContext(
        transcription: utterance,
        userId: null, // No user segmentation yet
      );
      print('✅ Context selected: ${contextBundle.summary}');

      // 2. Build messages from ContextBundle
      print('\n[2/4] Building message array from context...');
      final messages = _buildMessagesFromContext(
        contextBundle: contextBundle,
        currentUtterance: utterance,
      );
      print('✅ Messages built: ${messages.length} messages');

      // 3. Get all available tools from ToolRegistry
      print('\n[3/4] Getting available tools...');
      final toolDefinitions = toolExecutor.toolRegistry.getAllTools();
      final availableTools = toolDefinitions
          .map((tool) => LLMTool(
                name: tool.name,
                description: tool.description,
                parametersSchema: tool.parameters,
              ))
          .toList();
      print('✅ Available tools: ${availableTools.length} tools');

      // 4. LLM config (default for now)
      final llmConfig = {
        'model': 'llama-3.1-8b-instant',
        'temperature': 0.7,
      };

      // 5. Call LLM with tools
      print('\n[4/4] Calling LLM service with context...');
      print('📡 LLM call starting...');
      final llmResponse = await llmService.chatWithTools(
        model: llmConfig['model'] as String? ?? 'llama-3.1-8b-instant',
        messages: messages,
        tools: availableTools,
        temperature: (llmConfig['temperature'] as num?)?.toDouble() ?? 0.7,
      );
      print('✅ LLM response received');
      print('📄 Response content: "${llmResponse.content}"');

      // 6. Execute tool calls if present
      String finalResponse = llmResponse.content ?? 'No response generated';
      final executedToolNames = <String>[];
      int iterations = 1;

      if (llmResponse.toolCalls.isNotEmpty) {
        print('\n[Tool Execution] LLM requested ${llmResponse.toolCalls.length} tool calls');

        for (final llmToolCall in llmResponse.toolCalls) {
          print('  🔧 Executing: ${llmToolCall.toolName}');
          try {
            // Convert LLMToolCall to ToolCall
            final toolCall = ToolCall(
              toolName: llmToolCall.toolName,
              params: llmToolCall.params,
              callId: llmToolCall.id,
              confidence: 1.0,
            );

            final result = await toolExecutor.executeTool(
              toolCall,
              eventId: eventId,
            );

            if (result.success) {
              executedToolNames.add(llmToolCall.toolName);
              print('  ✅ Tool executed: ${llmToolCall.toolName}');
              final resultStr = result.data.toString();
              print('  📦 Result: ${resultStr.substring(0, resultStr.length > 100 ? 100 : resultStr.length)}...');
            } else {
              print('  ❌ Tool execution failed: ${result.error}');
            }
          } catch (e) {
            print('  ❌ Tool execution exception: $e');
          }
        }
      }

      print('💾 Final response set to: "$finalResponse"');

      // Placeholder values for return
      final selectedNamespace = 'general';
      final selectedTools = executedToolNames;
      final injectedContext = {
        'conversationThreadSize': contextBundle.conversationThread.length,
        'semanticContextSize': contextBundle.semanticContext.length,
      };

      // Record LLM orchestration invocation
      // TODO: Restore when LLMOrchestrator is available
      // print('\n📋 Recording LLM orchestration...');
      // print('DEBUG: About to call llmOrchestrator.recordOrchestration');
      // await llmOrchestrator.recordOrchestration(
      //   eventId: eventId,
      //   utterance: utterance,
      //   namespace: selectedNamespace,
      //   tools: selectedTools,
      //   context: injectedContext,
      //   finalResponse: finalResponse,
      //   toolCalls: toolCalls,
      //   iterations: iterations,
      //   success: true,
      // );
      // print('✅ LLM orchestration recorded');
      // invocationIds.add('llm_orchestration_invocation');

      // 7. ResponseRenderer formats response
      // COMMENTED OUT: Focus on LLM + TTS data for learning
      // print('\n🎨 Rendering response...');
      // final renderedResponse = await responseRenderer.renderResponse(
      //   eventId: eventId,
      //   llmResponse: finalResponse,
      //   namespace: selectedNamespace,
      //   tools: selectedTools,
      // );
      final renderedResponse = finalResponse; // Use LLM response as-is
      // print('✅ Response rendered: "$renderedResponse"');
      // invocationIds.add('response_renderer_invocation');

      // 8. TTS synthesizes and plays response
      print('\n🔊 Synthesizing response to speech...');
      await ttsService.synthesize(
        text: renderedResponse,
        eventId: eventId,
      );
      invocationIds.add('tts_synthesis_invocation');

      final latency = DateTime.now().difference(startTime).inMilliseconds;
      print('\n✅ COORDINATOR: orchestrate SUCCESS');
      print('⏱️ Total latency: ${latency}ms');
      print('🔗 Invocation IDs: ${invocationIds.join(", ")}');
      print('=== COORDINATOR: orchestrate END ===\n');

      return CoordinatorResult(
        turnId: eventId,
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
        correlationId: eventId,
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
        turnId: eventId,
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


  /// Build message array from ContextBundle
  ///
  /// Format:
  /// 1. System message with semantic context (facts from across system)
  /// 2. Conversation thread (STT → user, LLM → assistant)
  /// 3. Current user utterance
  List<Map<String, String>> _buildMessagesFromContext({
    required ContextBundle contextBundle,
    required String currentUtterance,
  }) {
    final messages = <Map<String, String>>[];

    // 1. System message with semantic context
    final systemPrompt = StringBuffer();
    systemPrompt.writeln('You are a helpful voice assistant.');

    if (contextBundle.semanticContext.isNotEmpty) {
      systemPrompt.writeln('\n# Relevant Context (from past interactions):');
      for (final inv in contextBundle.semanticContext) {
        final summary = inv.toEmbeddingInput();
        systemPrompt.writeln('- ${inv.componentType}: $summary');
      }
    }

    messages.add({'role': 'system', 'content': systemPrompt.toString()});

    // 2. Conversation thread (STT/LLM pairs → user/assistant messages)
    for (final inv in contextBundle.conversationThread) {
      if (inv.componentType == 'stt') {
        // STT invocation → user message
        final userMessage = inv.toEmbeddingInput();
        messages.add({'role': 'user', 'content': userMessage});
      } else if (inv.componentType == 'llm') {
        // LLM invocation → assistant message
        final assistantMessage = inv.toEmbeddingInput();
        messages.add({'role': 'assistant', 'content': assistantMessage});
      }
    }

    // 3. Current user utterance
    messages.add({'role': 'user', 'content': currentUtterance});

    return messages;
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
              parametersSchema: {
                'type': 'object',
                'properties': {},
              },
            ))
        .toList();
  }

}
