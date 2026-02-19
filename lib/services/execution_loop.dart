import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

class ExecutionResult {
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

  ExecutionResult({
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

/// Orchestrator execution loop: assembleContext -> selectTools -> execute -> respond.
///
/// Listens to EventBus for transcription events and runs the full pipeline.
/// Each step is a named concept function. This class coordinates them.
///
/// Future steps (stubbed): decompose, selectTools (entity/semantic/LRU),
/// classifyFailure, inferenceRouting.
class ExecutionLoop {
  final EmbeddingService embeddingService;
  final InferenceService llmService;
  final TTSService ttsService;
  final ToolExecutor toolExecutor;
  final ContextSelector contextSelector;
  final ModelSelector modelSelector;
  final VoiceTraits? voiceTraits;
  final ContextCapacity? contextCapacity;

  final InvocationRepository<Invocation> invocationRepo;
  final EventBus eventBus;

  StreamSubscription<Event>? _eventSubscription;
  static const int maxToolLoopIterations = 10;

  ExecutionLoop({
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

  /// Wire event listeners. Only path for orchestration.
  ///
  /// Called during bootstrap after registration in GetIt.
  /// UI should NOT call runLoop() directly.
  void initialize() {
    debugPrint('[ExecutionLoop] Wiring event listener');
    _eventSubscription = eventBus.subscribe().listen(
      _routeEvent,
      onError: (error) {
        debugPrint('[ExecutionLoop] Event listener error: $error');
      },
    );
    debugPrint('[ExecutionLoop] Event listener registered');
  }

  void dispose() {
    debugPrint('[ExecutionLoop] Disposing event listener');
    _eventSubscription?.cancel();
  }

  // ============ Event Routing ============

  Future<void> _routeEvent(Event event) async {
    switch (event.eventType) {
      case 'start_of_turn':
        await _handleBargeIn(event);
      case 'transcription_complete':
        await _handleTranscription(event);
    }
  }

  /// Stop TTS when user starts speaking (barge-in detection).
  Future<void> _handleBargeIn(Event event) async {
    if (!ttsService.isPlaying) return;

    debugPrint('[ExecutionLoop] Barge-in detected, stopping TTS');
    await ttsService.stop();
  }

  Future<void> _handleTranscription(Event event) async {
    try {
      final utterance = event.toInputString();
      debugPrint('[ExecutionLoop] Transcription received: "$utterance"');

      final result = await runLoop(eventId: event.uuid, utterance: utterance);

      await _publishResult(event, result);
      await _synthesizeResponse(event, result);
    } catch (e) {
      debugPrint('[ExecutionLoop] Failed: $e');
    }
  }

  // ============ Execution Loop (orchestrator method) ============

  /// Run the full execution loop for a single utterance.
  ///
  /// Orchestrator: assembleContext -> buildMessages -> collectTools ->
  /// selectModel -> applyVoiceTraits -> applyTokenBudget -> infer -> executeTools.
  ///
  /// Future additions: decompose (goal -> subtasks), selectTools (entity/semantic/LRU),
  /// classifyFailure (tool vs plan vs context), inferenceRouting (SLM vs frontier).
  Future<ExecutionResult> runLoop({
    required String eventId,
    required String utterance,
  }) async {
    final startTime = DateTime.now();

    try {
      final contextBundle = await _assembleContext(eventId, utterance);
      final messages = _buildMessages(contextBundle, utterance);
      final tools = _collectAvailableTools();
      final modelSelection = await _selectModel(eventId, utterance);
      final messagesWithTraits = await _applyVoiceTraits(messages, utterance, eventId);
      final budgetedMessages = await _applyTokenBudget(messagesWithTraits, modelSelection, eventId);
      final llmResponse = await _infer(modelSelection, budgetedMessages, tools);
      final (finalResponse, executedTools) = await _executeToolCalls(
        llmResponse: llmResponse,
        messages: messages,
        modelSelection: modelSelection,
        tools: tools,
        eventId: eventId,
      );

      return _buildSuccessResult(
        eventId: eventId,
        contextBundle: contextBundle,
        modelSelection: modelSelection,
        finalResponse: finalResponse,
        executedTools: executedTools,
        startTime: startTime,
      );
    } catch (e) {
      return _buildFailureResult(eventId: eventId, error: e, startTime: startTime);
    }
  }

  // ============ Concept Functions ============

  Future<ContextBundle> _assembleContext(String eventId, String utterance) async {
    debugPrint('[ExecutionLoop] Assembling context');
    final contextBundle = await contextSelector.selectContext(
      eventId: eventId,
      transcription: utterance,
      userId: null,
    );
    debugPrint('[ExecutionLoop] Context: ${contextBundle.summary}');
    return contextBundle;
  }

  List<Map<String, dynamic>> _buildMessages(
    ContextBundle contextBundle,
    String utterance,
  ) {
    final messages = llmService.buildMessagesFromContext(
      contextBundle: contextBundle,
      currentUtterance: utterance,
    );
    debugPrint('[ExecutionLoop] Messages built: ${messages.length}');
    return messages;
  }

  List<LLMTool> _collectAvailableTools() {
    final tools = toolExecutor.toolRegistry
        .getAllTools()
        .map((toolDef) => LLMTool(
              name: toolDef.name,
              description: toolDef.description,
              parametersSchema: toolDef.parameters,
            ))
        .toList();
    debugPrint('[ExecutionLoop] Available tools: ${tools.length}');
    return tools;
  }

  Future<ModelSelection> _selectModel(String eventId, String utterance) async {
    final modelSelection = await modelSelector.selectModel(
      eventId: eventId,
      utterance: utterance,
    );
    debugPrint('[ExecutionLoop] Model: ${modelSelection.model} '
        '(${(modelSelection.confidence * 100).toStringAsFixed(1)}%)');
    return modelSelection;
  }

  Future<LLMResponse> _infer(
    ModelSelection modelSelection,
    List<Map<String, dynamic>> messages,
    List<LLMTool> tools,
  ) async {
    debugPrint('[ExecutionLoop] Calling LLM');
    final llmResponse = await llmService.chatWithTools(
      model: modelSelection.model,
      messages: messages,
      tools: tools,
      temperature: 0.7,
    );
    debugPrint('[ExecutionLoop] LLM response received');
    return llmResponse;
  }

  /// Apply voice traits to messages. Degrades gracefully on failure.
  Future<List<Map<String, dynamic>>> _applyVoiceTraits(
    List<Map<String, dynamic>> messages,
    String utterance,
    String eventId,
  ) async {
    if (voiceTraits == null) return messages;
    try {
      final examples = await voiceTraits!.getExamples(
        query: utterance,
        eventId: eventId,
      );
      if (!examples.hasExamples) return messages;

      final traitsPrompt = voiceTraits!.formatPrompt(examples);
      debugPrint('[ExecutionLoop] Voice traits injected: ${examples.totalCount} examples');
      return _injectIntoSystemMessage(messages, traitsPrompt);
    } catch (e) {
      debugPrint('[ExecutionLoop] Voice traits failed (degraded): $e');
      return messages;
    }
  }

  /// Truncate messages to fit token budget. Degrades gracefully on failure.
  Future<List<Map<String, dynamic>>> _applyTokenBudget(
    List<Map<String, dynamic>> messages,
    ModelSelection modelSelection,
    String eventId,
  ) async {
    if (contextCapacity == null) return messages;
    try {
      final modelKey = '${modelSelection.implementer}:${modelSelection.model}';
      final truncationResult = await contextCapacity!.truncateMessages(
        messages: messages,
        model: modelKey,
        eventId: eventId,
      );
      if (truncationResult.wasTruncated) {
        debugPrint('[ExecutionLoop] Context truncated: ${truncationResult.summary}');
      }
      return truncationResult.messages;
    } catch (e) {
      debugPrint('[ExecutionLoop] Token budget failed (degraded): $e');
      return messages;
    }
  }

  /// Execute tool calls from LLM response. Send results back for follow-up.
  ///
  /// Returns (finalResponse, executedToolNames).
  /// If no tool calls, returns original LLM content unchanged.
  Future<(String, List<String>)> _executeToolCalls({
    required LLMResponse llmResponse,
    required List<Map<String, dynamic>> messages,
    required ModelSelection modelSelection,
    required List<LLMTool> tools,
    required String eventId,
  }) async {
    final executedTools = <String>[];
    String finalResponse = llmResponse.content ?? '';

    if (llmResponse.toolCalls.isEmpty) return (finalResponse, executedTools);

    debugPrint('[ExecutionLoop] Executing ${llmResponse.toolCalls.length} tool calls');

    final toolResults = await _runToolCalls(llmResponse.toolCalls, executedTools, eventId);
    final followUpMessages = _buildFollowUpMessages(messages, llmResponse, toolResults);

    final followUpResponse = await llmService.chatWithTools(
      model: modelSelection.model,
      messages: followUpMessages,
      tools: tools,
      temperature: 0.7,
    );

    finalResponse = followUpResponse.content ?? '';
    debugPrint('[ExecutionLoop] Follow-up response received');

    return (finalResponse, executedTools);
  }

  Future<List<Map<String, dynamic>>> _runToolCalls(
    List<LLMToolCall> toolCalls,
    List<String> executedTools,
    String eventId,
  ) async {
    final toolResults = <Map<String, dynamic>>[];
    for (final llmToolCall in toolCalls) {
      debugPrint('[ExecutionLoop] Executing: ${llmToolCall.toolName}');
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
      }

      toolResults.add({
        'tool_call_id': llmToolCall.id,
        'role': 'tool',
        'name': llmToolCall.toolName,
        'content': executionResult.success
            ? jsonEncode(executionResult.toolOutput)
            : jsonEncode({'error': executionResult.error}),
      });
    }
    return toolResults;
  }

  List<Map<String, dynamic>> _buildFollowUpMessages(
    List<Map<String, dynamic>> messages,
    LLMResponse llmResponse,
    List<Map<String, dynamic>> toolResults,
  ) {
    return [
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
  }

  // ============ Message Construction ============

  List<Map<String, dynamic>> _injectIntoSystemMessage(
    List<Map<String, dynamic>> messages,
    String additionalContent,
  ) {
    if (additionalContent.isEmpty) return messages;

    final augmentedMessages = List<Map<String, dynamic>>.from(messages);

    final systemIndex =
        augmentedMessages.indexWhere((m) => m['role'] == 'system');
    if (systemIndex >= 0) {
      final existingContent =
          augmentedMessages[systemIndex]['content'] as String? ?? '';
      augmentedMessages[systemIndex] = {
        ...augmentedMessages[systemIndex],
        'content': '$existingContent\n\n$additionalContent',
      };
    } else {
      augmentedMessages.insert(0, {
        'role': 'system',
        'content': additionalContent,
      });
    }

    return augmentedMessages;
  }

  // ============ Result Construction ============

  ExecutionResult _buildSuccessResult({
    required String eventId,
    required ContextBundle contextBundle,
    required ModelSelection modelSelection,
    required String finalResponse,
    required List<String> executedTools,
    required DateTime startTime,
  }) {
    final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('[ExecutionLoop] Success (${latencyMs}ms)');

    return ExecutionResult(
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
      latencyMs: latencyMs,
    );
  }

  Future<ExecutionResult> _buildFailureResult({
    required String eventId,
    required Object error,
    required DateTime startTime,
  }) async {
    final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('[ExecutionLoop] Failed (${latencyMs}ms): $error');

    await eventBus.publish(Event(
      eventType: 'orchestration_error',
      correlationId: eventId,
      source: 'execution_loop',
      payloadJson: jsonEncode({
        'message': error.toString(),
        'errorType': error.runtimeType.toString(),
      }),
    ));

    return ExecutionResult(
      turnId: eventId,
      selectedNamespace: '',
      selectedTools: [],
      injectedContext: {},
      llmConfig: {},
      finalResponse: '',
      invocationIds: [],
      isSuccess: false,
      errorMessage: error.toString(),
      latencyMs: latencyMs,
    );
  }

  // ============ Event Publishing ============

  Future<void> _publishResult(Event sourceEvent, ExecutionResult result) async {
    await eventBus.publish(Event(
      eventType: 'orchestration_complete',
      correlationId: sourceEvent.correlationId,
      source: 'execution_loop',
      payloadJson: jsonEncode({
        'success': result.isSuccess,
        'response': result.finalResponse,
        'errorMessage': result.errorMessage,
      }),
    ));
  }

  Future<void> _synthesizeResponse(
    Event sourceEvent,
    ExecutionResult result,
  ) async {
    if (!result.isSuccess || result.finalResponse.isEmpty) return;

    debugPrint('[ExecutionLoop] Synthesizing TTS');
    await ttsService.synthesize(
      text: result.finalResponse,
      eventId: sourceEvent.correlationId,
    );
  }
}
