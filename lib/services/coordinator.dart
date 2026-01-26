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
        // Handle start_of_turn events (barge-in detection)
        if (event.eventType == 'start_of_turn') {
          await _handleStartOfTurn(event);
          return;
        }

        // Handle transcription_complete events (orchestration trigger)
        if (event.eventType == 'transcription_complete') {
          try {
            // Extract semantic input from event
            final inputText = event.toInputString();

            print('\n📡 [Coordinator] Heard transcription_complete: "$inputText"');
            print('🚀 [Coordinator] Starting orchestration from event...');

            final result = await _orchestrate(
              eventId: event.uuid,
              utterance: inputText,
            );

            print('✅ [Coordinator] Orchestration complete: ${result.success ? "SUCCESS" : "FAILED"}');
            if (!result.success) {
              print('⚠️ Error: ${result.errorMessage}');
            }

            // Publish orchestration_complete event for UI to update state (text appears FIRST)
            await eventBus.publish(Event(
              eventType: 'orchestration_complete',
              correlationId: event.correlationId,  // Preserve correlation chain
              source: 'coordinator',
              payloadJson: jsonEncode({
                'success': result.success,
                'response': result.finalResponse,
                'errorMessage': result.errorMessage,
              }),
            ));
            print('📡 [Coordinator] Published orchestration_complete event');

            // THEN synthesize TTS (user sees text before hearing audio - better UX)
            if (result.success && result.finalResponse.isNotEmpty) {
              print('🔊 Synthesizing response to speech...');
              await ttsService.synthesize(
                text: result.finalResponse,
                eventId: event.correlationId,
              );
            }
          } catch (e) {
            print('❌ [Coordinator] Failed to orchestrate from event: $e');
          }
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

  /// Handle start_of_turn event (barge-in detection)
  ///
  /// When user starts speaking while TTS is playing, stop TTS immediately.
  /// This enables natural conversation flow where user can interrupt the assistant.
  ///
  /// Pure event routing - no trainable parameters, no learning surface.
  Future<void> _handleStartOfTurn(Event event) async {
    // Check if TTS is currently playing
    if (!ttsService.isPlaying) {
      // TTS not playing, nothing to do
      return;
    }

    print('⚠️ [Coordinator] BARGE-IN detected - user started speaking while TTS playing');
    print('🛑 [Coordinator] Stopping TTS immediately');

    // Stop TTS playback
    await ttsService.stop();

    print('✅ [Coordinator] Barge-in handled, TTS stopped');
  }

  /// Orchestrate voice assistant pipeline
  /// Orchestrate a turn: context → LLM → tools → TTS
  ///
  /// PRIVATE: Only callable through EventBus (initialize() listener)
  Future<CoordinatorResult> _orchestrate({
    required String eventId,
    required String utterance,
  }) async {
    print('\n=== COORDINATOR: orchestrate START ===');
    print('🔗 EventId: $eventId');
    print('📝 Utterance: "$utterance"');

    final startTime = DateTime.now();

    try {
      // 1. Get context
      print('\n[1/4] Selecting context via ContextSelector...');
      final context = await contextSelector.selectContext(
        eventId: eventId,
        transcription: utterance,
        userId: null,
      );
      print('✅ Context selected: ${context.summary}');

      // 2. Build messages + call LLM
      print('\n[2/4] Building message array from context...');
      final messages = llmService.buildMessagesFromContext(
        contextBundle: context,
        currentUtterance: utterance,
      );
      print('✅ Messages built: ${messages.length} messages');

      print('\n[3/4] Getting available tools...');
      // TODO: Integrate ToolSelector once semantic indexing is implemented
      // Currently ToolSelector is a stub that returns all tools anyway
      final tools = toolExecutor.toolRegistry
          .getAllTools()
          .map((t) => LLMTool(
                name: t.name,
                description: t.description,
                parametersSchema: t.parameters,
              ))
          .toList();
      print('✅ Available tools: ${tools.length} tools');

      print('\n[4/4] Calling LLM service with context...');
      print('📡 LLM call starting...');
      final llmResponse = await llmService.chatWithTools(
        model: 'llama-3.3-70b-versatile',  // Best Groq model for function calling
        messages: messages,
        tools: tools,
        temperature: 0.7,
      );
      print('✅ LLM response received');
      print('📄 Response content: "${llmResponse.content}"');

      // 3. Agentic loop: Execute tool calls and get verbal response
      final executedTools = <String>[];
      String finalResponse = llmResponse.content ?? '';

      if (llmResponse.toolCalls.isNotEmpty) {
        print('\n[Tool Execution] LLM requested ${llmResponse.toolCalls.length} tool calls');

        // Execute all tool calls and collect results
        final toolResults = <Map<String, dynamic>>[];
        for (final llmToolCall in llmResponse.toolCalls) {
          print('  🔧 Executing: ${llmToolCall.toolName}');
          final toolCall = ToolCall(
            toolName: llmToolCall.toolName,
            params: llmToolCall.params,
            callId: llmToolCall.id,
            confidence: 1.0,
          );
          final result = await toolExecutor.executeTool(toolCall, eventId: eventId);

          if (result.success) {
            executedTools.add(llmToolCall.toolName);
            print('  ✅ Tool executed: ${llmToolCall.toolName}');
            toolResults.add({
              'tool_call_id': llmToolCall.id,
              'role': 'tool',
              'name': llmToolCall.toolName,
              'content': jsonEncode(result.data),
            });
          } else {
            print('  ❌ Tool execution failed: ${result.error}');
            toolResults.add({
              'tool_call_id': llmToolCall.id,
              'role': 'tool',
              'name': llmToolCall.toolName,
              'content': jsonEncode({'error': result.error}),
            });
          }
        }

        // Send tool results back to LLM for verbal confirmation
        print('\n[Agentic Loop] Sending tool results back to LLM for confirmation...');
        final followUpMessages = [
          ...messages,
          {
            'role': 'assistant',
            'content': llmResponse.content,
            'tool_calls': llmResponse.toolCalls.map((tc) => {
              'id': tc.id,
              'type': 'function',
              'function': {
                'name': tc.toolName,
                'arguments': jsonEncode(tc.params),
              }
            }).toList(),
          },
          ...toolResults,
        ];

        final followUpResponse = await llmService.chatWithTools(
          model: 'llama-3.3-70b-versatile',
          messages: followUpMessages,
          tools: tools,
          temperature: 0.7,
        );

        finalResponse = followUpResponse.content ?? '';
        print('✅ LLM follow-up response: "$finalResponse"');
      }

      // Note: TTS happens in event listener AFTER orchestration_complete is published
      // This ensures text appears in UI before audio plays (better UX)

      final latency = DateTime.now().difference(startTime).inMilliseconds;
      print('\n✅ COORDINATOR: orchestrate SUCCESS');
      print('⏱️ Total latency: ${latency}ms');
      print('=== COORDINATOR: orchestrate END ===\n');

      return CoordinatorResult(
        turnId: eventId,
        selectedNamespace: 'general',
        selectedTools: executedTools,
        injectedContext: {
          'conversationThreadSize': context.conversationThread.length,
          'semanticContextSize': context.semanticContext.length,
        },
        llmConfig: {'model': 'llama-3.3-70b-versatile', 'temperature': 0.7},
        finalResponse: finalResponse,
        invocationIds: ['tts_synthesis_invocation'],
        success: true,
        latencyMs: latency,
      );
    } catch (e) {
      final latency = DateTime.now().difference(startTime).inMilliseconds;

      // Publish error event
      await eventBus.publish(Event(
        eventType: 'orchestration_error',
        correlationId: eventId,
        source: 'coordinator',
        payloadJson: jsonEncode({
          'message': e.toString(),
          'errorType': e.runtimeType.toString(),
        }),
      ));

      return CoordinatorResult(
        turnId: eventId,
        selectedNamespace: '',
        selectedTools: [],
        injectedContext: {},
        llmConfig: {},
        finalResponse: '',
        invocationIds: [],
        success: false,
        errorMessage: e.toString(),
        latencyMs: latency,
      );
    }
  }
}
