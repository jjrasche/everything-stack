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
import 'trainables/model_selector.dart';
import 'voice_traits.dart';
import 'context_capacity.dart';
import 'types/llm_types.dart';
import 'types/model_selector_types.dart';

class CoordinatorResult {
  final String turnId;
  final String selectedNamespace;
  final List<String> selectedTools;
  final Map<String, dynamic> injectedContext;
  final Map<String, dynamic> llmConfig;
  final String finalResponse;
  final List<String> invocationIds;
  final bool isSuccess;
  final String? errorMessage;
  final int latencyMs;

  CoordinatorResult({
    required this.turnId,
    required this.selectedNamespace,
    required this.selectedTools,
    required this.injectedContext,
    required this.llmConfig,
    required this.finalResponse,
    required this.invocationIds,
    required this.isSuccess,
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
  final ModelSelector modelSelector;
  final VoiceTraits? voiceTraits; // Optional for backwards compatibility
  final ContextCapacity? contextCapacity; // Optional for backwards compatibility

  final InvocationRepository<Invocation> invocationRepo;
  final EventBus eventBus;

  StreamSubscription<Event>? _transcriptionSubscription;
  static const int maxAgentLoopIterations = 10;

  Coordinator({
    required this.embeddingService,
    required this.llmService,
    required this.ttsService,
    required this.toolExecutor,
    required this.contextSelector,
    required this.modelSelector,
    this.voiceTraits,
    this.contextCapacity,
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
        if (event.eventType == 'start_of_turn') {
          await _handleStartOfTurn(event);
          return;
        }

        if (event.eventType == 'transcription_complete') {
          try {
            final inputText = event.toInputString();

            print(
                '\n📡 [Coordinator] Heard transcription_complete: "$inputText"');
            print('🚀 [Coordinator] Starting orchestration from event...');

            final result = await _orchestrate(
              eventId: event.uuid,
              utterance: inputText,
            );

            print(
                '✅ [Coordinator] Orchestration complete: ${result.isSuccess ? "SUCCESS" : "FAILED"}');
            if (!result.isSuccess) {
              print('⚠️ Error: ${result.errorMessage}');
            }

            // Publish orchestration_complete event for UI to update state (text appears FIRST)
            await eventBus.publish(Event(
              eventType: 'orchestration_complete',
              correlationId: event.correlationId, // Preserve correlation chain
              source: 'coordinator',
              payloadJson: jsonEncode({
                'success': result.isSuccess,
                'response': result.finalResponse,
                'errorMessage': result.errorMessage,
              }),
            ));
            print('📡 [Coordinator] Published orchestration_complete event');

            // THEN synthesize TTS (user sees text before hearing audio - better UX)
            if (result.isSuccess && result.finalResponse.isNotEmpty) {
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
    if (!ttsService.isPlaying) {
      // TTS not playing, nothing to do
      return;
    }

    print(
        '⚠️ [Coordinator] BARGE-IN detected - user started speaking while TTS playing');
    print('🛑 [Coordinator] Stopping TTS immediately');

    await ttsService.stop();

    print('✅ [Coordinator] Barge-in handled, TTS stopped');
  }

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
      print('\n[1/7] Selecting context via ContextSelector...');
      final contextBundle = await contextSelector.selectContext(
        eventId: eventId,
        transcription: utterance,
        userId: null,
      );
      print('✅ Context selected: ${contextBundle.summary}');

      print('\n[2/7] Building message array from context...');
      final messages = llmService.buildMessagesFromContext(
        contextBundle: contextBundle,
        currentUtterance: utterance,
      );
      print('✅ Messages built: ${messages.length} messages');

      print('\n[3/7] Getting available tools...');
      // TODO: Integrate ToolSelector once semantic indexing is implemented
      final tools = _collectAvailableTools();
      print('✅ Available tools: ${tools.length} tools');

      print('\n[4/7] Selecting model via ModelSelector...');
      final modelSelection = await modelSelector.selectModel(
        eventId: eventId,
        utterance: utterance,
      );
      print('✅ Model selected: ${modelSelection.model} '
          '(confidence: ${(modelSelection.confidence * 100).toStringAsFixed(1)}%)');

      print('\n[5/7] Getting voice traits examples...');
      var finalMessages = await _applyVoiceTraits(messages, utterance, eventId);

      print('\n[6/7] Truncating context to token budget...');
      finalMessages = await _applyTokenBudget(finalMessages, modelSelection, eventId);

      print('\n[7/7] Calling LLM service with context...');
      print('📡 LLM call starting...');
      final llmResponse = await llmService.chatWithTools(
        model: modelSelection.model,
        messages: finalMessages,
        tools: tools,
        temperature: 0.7,
      );
      print('✅ LLM response received');
      print('📄 Response content: "${llmResponse.content}"');

      final (finalResponse, executedTools) = await _executeToolLoop(
        llmResponse: llmResponse,
        messages: messages,
        modelSelection: modelSelection,
        tools: tools,
        eventId: eventId,
      );

      final latency = DateTime.now().difference(startTime).inMilliseconds;
      print('\n✅ COORDINATOR: orchestrate SUCCESS');
      print('⏱️ Total latency: ${latency}ms');
      print('=== COORDINATOR: orchestrate END ===\n');

      return CoordinatorResult(
        turnId: eventId,
        selectedNamespace: 'general',
        selectedTools: executedTools,
        injectedContext: {
          'conversationThreadSize': contextBundle.conversationThread.length,
          'semanticContextSize': contextBundle.semanticContext.length,
        },
        llmConfig: {
          'model': modelSelection.model,
          'implementer': modelSelection.implementer,
          'confidence': modelSelection.confidence,
          'temperature': 0.7,
        },
        finalResponse: finalResponse,
        invocationIds: ['tts_synthesis_invocation'],
        isSuccess: true,
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
        isSuccess: false,
        errorMessage: e.toString(),
        latencyMs: latency,
      );
    }
  }

  List<LLMTool> _collectAvailableTools() {
    return toolExecutor.toolRegistry
        .getAllTools()
        .map((toolDef) => LLMTool(
              name: toolDef.name,
              description: toolDef.description,
              parametersSchema: toolDef.parameters,
            ))
        .toList();
  }

  /// Apply voice traits to messages, degrading gracefully on failure.
  Future<List<Map<String, dynamic>>> _applyVoiceTraits(
    List<Map<String, dynamic>> messages,
    String utterance,
    String eventId,
  ) async {
    if (voiceTraits == null) {
      print('ℹ️ VoiceTraits not configured');
      return messages;
    }
    try {
      final examples = await voiceTraits!.getExamples(
        query: utterance,
        eventId: eventId,
      );
      if (examples.hasExamples) {
        final traitsPrompt = voiceTraits!.formatPrompt(examples);
        final messagesWithTraits = _injectVoiceTraits(messages, traitsPrompt);
        print('✅ Voice traits injected: ${examples.totalCount} examples');
        return messagesWithTraits;
      } else {
        print('ℹ️ No voice traits examples found');
        return messages;
      }
    } catch (e) {
      print('⚠️ Voice traits failed (degraded gracefully): $e');
      return messages;
    }
  }

  /// Truncate messages to fit token budget, degrading gracefully on failure.
  Future<List<Map<String, dynamic>>> _applyTokenBudget(
    List<Map<String, dynamic>> messages,
    ModelSelection modelSelection,
    String eventId,
  ) async {
    if (contextCapacity == null) {
      print('ℹ️ ContextCapacity not configured');
      return messages;
    }
    try {
      final modelKey = '${modelSelection.implementer}:${modelSelection.model}';
      final truncationResult = await contextCapacity!.truncateMessages(
        messages: messages,
        model: modelKey,
        eventId: eventId,
      );
      if (truncationResult.wasTruncated) {
        print('✂️ Context truncated: ${truncationResult.summary}');
      } else {
        print('✅ Context within budget: ${truncationResult.totalTokens}/${truncationResult.tokenBudget} tokens');
      }
      return truncationResult.messages;
    } catch (e) {
      print('⚠️ ContextCapacity failed (degraded gracefully): $e');
      return messages;
    }
  }

  /// Execute tool calls from LLM response and get follow-up verbal response.
  ///
  /// Returns (finalResponse, executedToolNames). If no tool calls, returns
  /// the original LLM response content unchanged.
  Future<(String, List<String>)> _executeToolLoop({
    required LLMResponse llmResponse,
    required List<Map<String, dynamic>> messages,
    required ModelSelection modelSelection,
    required List<LLMTool> tools,
    required String eventId,
  }) async {
    final executedTools = <String>[];
    String finalResponse = llmResponse.content ?? '';

    if (llmResponse.toolCalls.isEmpty) return (finalResponse, executedTools);

    print('\n[Tool Execution] LLM requested ${llmResponse.toolCalls.length} tool calls');

    final toolResults = <Map<String, dynamic>>[];
    for (final llmToolCall in llmResponse.toolCalls) {
      print('  🔧 Executing: ${llmToolCall.toolName}');
      final toolCall = ToolCall(
        toolName: llmToolCall.toolName,
        params: llmToolCall.params,
        callId: llmToolCall.id,
        confidence: 1.0,
      );
      final executionResult =
          await toolExecutor.executeTool(toolCall, eventId: eventId);

      if (executionResult.success) {
        executedTools.add(llmToolCall.toolName);
        print('  ✅ Tool executed: ${llmToolCall.toolName}');
        toolResults.add({
          'tool_call_id': llmToolCall.id,
          'role': 'tool',
          'name': llmToolCall.toolName,
          'content': jsonEncode(executionResult.toolOutput),
        });
      } else {
        print('  ❌ Tool execution failed: ${executionResult.error}');
        toolResults.add({
          'tool_call_id': llmToolCall.id,
          'role': 'tool',
          'name': llmToolCall.toolName,
          'content': jsonEncode({'error': executionResult.error}),
        });
      }
    }

    print('\n[Agentic Loop] Sending tool results back to LLM for confirmation...');
    final followUpMessages = [
      ...messages,
      {
        'role': 'assistant',
        'content': llmResponse.content,
        'tool_calls': llmResponse.toolCalls
            .map((pendingCall) => {
                  'id': pendingCall.id,
                  'type': 'function',
                  'function': {
                    'name': pendingCall.toolName,
                    'arguments': jsonEncode(pendingCall.params),
                  }
                })
            .toList(),
      },
      ...toolResults,
    ];

    final followUpResponse = await llmService.chatWithTools(
      model: modelSelection.model,
      messages: followUpMessages,
      tools: tools,
      temperature: 0.7,
    );

    finalResponse = followUpResponse.content ?? '';
    print('✅ LLM follow-up response: "$finalResponse"');

    return (finalResponse, executedTools);
  }

  List<Map<String, dynamic>> _injectVoiceTraits(
    List<Map<String, dynamic>> messages,
    String traitsPrompt,
  ) {
    if (traitsPrompt.isEmpty) return messages;

    final augmentedMessages = List<Map<String, dynamic>>.from(messages);

    final systemIndex = augmentedMessages.indexWhere((m) => m['role'] == 'system');
    if (systemIndex >= 0) {
      final existingContent = augmentedMessages[systemIndex]['content'] as String? ?? '';
      augmentedMessages[systemIndex] = {
        ...augmentedMessages[systemIndex],
        'content': '$existingContent\n\n$traitsPrompt',
      };
    } else {
      augmentedMessages.insert(0, {
        'role': 'system',
        'content': traitsPrompt,
      });
    }

    return augmentedMessages;
  }
}
