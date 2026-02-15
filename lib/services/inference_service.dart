import 'package:flutter/material.dart';
import 'dart:convert';

import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback.dart' as core_feedback;
import '../core/feedback_repository.dart';
import '../core/trainable.dart';
import '../core/component_types.dart';
import './implementations/llm_implementer.dart';
import './types/llm_types.dart';
import './types/message.dart';
import './types/context_selector_types.dart';
import './trainer/gaussian_process_optimizer.dart';

// Export types for use by Coordinator, Implementers, and Tests
export './types/message.dart' show Message;
export './types/llm_types.dart'
    show
        LLMResponse,
        LLMTool,
        LLMToolCall,
        LLMInvocationInput,
        LLMInvocationOutput,
        InferenceAdaptationData,
        LLMFeedback;

class InferenceService with Trainable<InferenceAdaptationData> {
  final Map<String, LLMImplementer> _implementers;
  final String _defaultImplementer;
  final InvocationRepository invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  InferenceService({
    required Map<String, LLMImplementer> implementers,
    required String defaultImplementer,
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  })  : _implementers = implementers,
        _defaultImplementer = defaultImplementer {
    if (!_implementers.containsKey(_defaultImplementer)) {
      throw ArgumentError(
        'Default implementer "$_defaultImplementer" not found in implementers',
      );
    }
  }

  /// Get available models per implementer.
  /// Used by ModelSelector to know which models can be selected.
  Map<String, List<String>> getAvailableModels() {
    return _implementers.map(
      (name, impl) => MapEntry(name, impl.availableModels),
    );
  }

  /// Chat with LLM using adaptation-aware parameters.
  ///
  /// Flow:
  /// 1. Select implementer (specified or default)
  /// 2. Load adaptation state (temperature, response length preferences)
  /// 3. Call implementer with adapted parameters
  /// 4. Log invocation for training feedback
  /// 5. Return response
  Future<String> chat({
    required String eventId,
    required List<Message> messages,
    String? implementerName,
    String? userId,
  }) async {
    // 1. Get implementer (specified or default)
    final implementer = _implementers[implementerName ?? _defaultImplementer]!;

    // 2. Read adaptation state for this implementer + user
    final state =
        await _getAdaptationState(implementer.implementerName, userId);

    // 3. Call implementer with adapted parameters
    final output = await implementer.chat(
      messages: messages,
      temperature: state.temperature,
      topP: state.topP,
      frequencyPenalty: state.frequencyPenalty,
      presencePenalty: state.presencePenalty,
      maxTokens: state.maxTokens,
    );

    // 4. Log invocation for training feedback
    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: ComponentType.llm,
        implementer: implementer.implementerName,
        success: true,
        confidence: 1.0,
        input: LLMInvocationInput(messages: messages).toJson(),
        output: output.toJson(),
      ),
    );

    // 5. Return response
    return output.response;
  }

  /// Build LLM message array from ContextBundle.
  ///
  /// Prompt engineering: Converts semantic context + conversation thread
  /// into properly formatted LLM messages.
  ///
  /// Format:
  /// 1. System message with semantic context (facts from across system)
  /// 2. Conversation thread (STT → user, LLM → assistant)
  /// 3. Current user utterance
  List<Map<String, dynamic>> buildMessagesFromContext({
    required ContextBundle contextBundle,
    required String currentUtterance,
  }) {
    final messages = <Map<String, dynamic>>[];

    // 1. System message with semantic context
    final systemPrompt = StringBuffer();
    systemPrompt.writeln(
        'You are a helpful voice assistant. Keep responses brief and conversational - like you\'re talking to a friend, not writing an essay.');
    systemPrompt.writeln(
        '\nIMPORTANT: Only use tools when the user explicitly asks you to do something that requires a tool (like "set a timer" or "create a task"). For casual conversation, respond naturally without calling tools.');
    systemPrompt.writeln(
        '\nStyle: Short, direct answers. 1-2 sentences max unless asked for details. Avoid verbose explanations.');

    if (contextBundle.semanticContext.isNotEmpty) {
      systemPrompt.writeln('\n# Relevant Context (from semantic search):');
      for (final result in contextBundle.semanticContext) {
        // Use chunk text directly (it's the matched content)
        final chunkText = result.chunk.text;
        final entityType = result.chunk.sourceEntityType;
        final similarity = (result.similarity * 100).toStringAsFixed(0);
        systemPrompt.writeln('- [$entityType, $similarity% match]: $chunkText');
      }
    }

    messages.add({'role': 'system', 'content': systemPrompt.toString()});

    // 2. Conversation thread (LLM invocations → user/assistant message pairs)
    // Each LLM invocation has input.prompt (user) and output.response (assistant)
    for (final inv in contextBundle.conversationThread) {
      // Extract user prompt from input
      final userPrompt = inv.input?['prompt'] as String?;
      if (userPrompt != null && userPrompt.isNotEmpty) {
        messages.add({'role': 'user', 'content': userPrompt});
      }

      // Extract assistant response from output
      final assistantResponse = inv.output?['response'] as String?;
      if (assistantResponse != null && assistantResponse.isNotEmpty) {
        messages.add({'role': 'assistant', 'content': assistantResponse});
      }
    }

    // 3. Current user utterance
    messages.add({'role': 'user', 'content': currentUtterance});

    return messages;
  }

  /// Call LLM with tools available for agentic workflows.
  /// Delegates to implementer, logs invocation.
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    // Use default implementer (typically Groq)
    final implementer = _implementers[_defaultImplementer]!;

    // Delegate to implementer (currently only Groq supports tools)
    final response = await implementer.chatWithTools(
      model: model,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    // Log invocation for training
    // Extract last user message as prompt for semantic indexing
    final lastUserMsg = messages.lastWhere(
      (msg) => msg['role'] == 'user',
      orElse: () => <String, dynamic>{'content': ''},
    );
    final prompt = (lastUserMsg['content'] as String?) ?? '';

    await recordInvocation(
      'unknown', // TODO: Pass eventId from Coordinator
      Invocation(
        eventId: 'unknown',
        componentType: ComponentType.llm,
        implementer: implementer.implementerName,
        success: true,
        confidence: 1.0,
        input: {'prompt': prompt, 'messages': messages},
        output: {'response': response.content},
      ),
    );

    return response;
  }

  /// Stream tokens from LLM via SSE for real-time output.
  /// Delegates to the default implementer's streaming API.
  Stream<String> chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) {
    final implementer = _implementers[_defaultImplementer]!;
    return implementer.chatStream(
      model: model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// Get adaptation state for this implementer, or defaults if not found.
  Future<InferenceAdaptationData> _getAdaptationState(
    String implementerName,
    String? userId,
  ) async {
    final state = await adaptationStateRepo.getForComponent(
      ComponentType.llm,
      implementer: implementerName,
      userId: userId,
    );

    return state != null
        ? InferenceAdaptationData.fromJson(
            jsonDecode(state.dataJson ?? '{}') as Map<String, dynamic>)
        : InferenceAdaptationData.defaults();
  }

  // ============ Trainable Implementation ============

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    // Parse typed input/output from invocation
    final input = LLMInvocationInput.fromJson(invocation.input!);
    final output = LLMInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LLM Response:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(output.response),
        ),
        const SizedBox(height: 16),
        Text('Was this response helpful?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record feedback
              },
              child: const Text('Yes'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Record feedback
              },
              child: const Text('No'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(
      Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Extract userId from invocation/turn context for per-user training
    // For now, use global training (userId = null)
    const String? userId = null;

    // Get implementer from invocation (e.g., 'groq')
    final implementerName = invocation.implementer ?? _defaultImplementer;

    // Get or create optimizer for this implementer
    final optimizer = _getOrCreateOptimizer(implementerName, userId);

    // Get current params
    final state = await _getAdaptationState(implementerName, userId);

    // Convert feedback to reward
    final reward =
        feedback.action == core_feedback.FeedbackAction.confirm ? 1.0 : -1.0;

    // Record trial (persists to database)
    await optimizer.recordTrial({
      'temperature': state.temperature,
      'topP': state.topP,
      'frequencyPenalty': state.frequencyPenalty,
      'presencePenalty': state.presencePenalty,
      'maxTokens': state.maxTokens,
    }, reward);

    // Get GP suggestion (loads historical trials from database)
    final suggested = await optimizer.suggestNext();

    // Update with new parameters
    final newParams = state.copyWith(
      temperature: suggested['temperature'] as double,
      topP: suggested['topP'] as double,
      frequencyPenalty: suggested['frequencyPenalty'] as double,
      presencePenalty: suggested['presencePenalty'] as double,
      maxTokens: suggested['maxTokens'] as int,
    );

    // Save to AdaptationState
    final adaptationState = await adaptationStateRepo.getForComponent(
          ComponentType.llm,
          implementer: implementerName,
          userId: userId,
        ) ??
        AdaptationState(
          componentType: ComponentType.llm,
          implementer: implementerName,
          userId: userId,
        );

    adaptationState.dataJson = newParams.toJson();
    adaptationState.version++;
    adaptationState.lastUpdatedAt = DateTime.now();
    adaptationState.lastUpdateReason = 'trainFromFeedback';
    adaptationState.feedbackCountApplied++;

    await adaptationStateRepo.save(adaptationState);

    print(
        '✅ [InferenceService.trainFromFeedback] Updated parameters for $implementerName:');
    print(
        '   temperature: ${state.temperature.toStringAsFixed(2)} → ${newParams.temperature.toStringAsFixed(2)}');
    print(
        '   topP: ${state.topP.toStringAsFixed(2)} → ${newParams.topP.toStringAsFixed(2)}');
    print(
        '   frequencyPenalty: ${state.frequencyPenalty.toStringAsFixed(2)} → ${newParams.frequencyPenalty.toStringAsFixed(2)}');
    print(
        '   presencePenalty: ${state.presencePenalty.toStringAsFixed(2)} → ${newParams.presencePenalty.toStringAsFixed(2)}');
    print('   maxTokens: ${state.maxTokens} → ${newParams.maxTokens}');
  }

  // ============ GP Optimizer Management ============

  final Map<String, GaussianProcessOptimizer> _optimizers = {};

  GaussianProcessOptimizer _getOrCreateOptimizer(
      String implementerName, String? userId) {
    final key = '${implementerName}_${userId ?? "_global_"}';
    return _optimizers.putIfAbsent(
      key,
      () => GaussianProcessOptimizer(
        paramBounds: getParameterBounds(),
        componentType: '${componentType}_$implementerName', // e.g., 'llm_groq'
        userId: userId,
      ),
    );
  }

  // ============ Trainable Interface Implementation ============

  @override
  String get componentType => 'llm';

  @override
  InferenceAdaptationData createDefaultData() =>
      InferenceAdaptationData.defaults();

  @override
  InferenceAdaptationData deserializeData(String json) =>
      InferenceAdaptationData.fromJson(
          jsonDecode(json) as Map<String, dynamic>);

  @override
  Map<String, (double, double)> getParameterBounds() => {
        'temperature': (0.0, 2.0),
        'topP': (0.0, 1.0),
        'frequencyPenalty': (-2.0, 2.0),
        'presencePenalty': (-2.0, 2.0),
        'maxTokens': (
          100.0,
          8000.0
        ), // Groq limit, adjust per implementer if needed
      };
}
