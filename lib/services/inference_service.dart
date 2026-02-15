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

  Map<String, List<String>> getAvailableModels() {
    return _implementers.map(
      (implementerName, implementer) =>
          MapEntry(implementerName, implementer.availableModels),
    );
  }

  Future<String> chat({
    required String eventId,
    required List<Message> messages,
    String? implementerName,
    String? userId,
  }) async {
    final implementer = _implementers[implementerName ?? _defaultImplementer]!;

    final state =
        await _getAdaptationState(implementer.implementerName, userId);

    final llmOutput = await implementer.chat(
      messages: messages,
      temperature: state.temperature,
      topP: state.topP,
      frequencyPenalty: state.frequencyPenalty,
      presencePenalty: state.presencePenalty,
      maxTokens: state.maxTokens,
    );

    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: ComponentType.llm,
        implementer: implementer.implementerName,
        success: true,
        confidence: 1.0,
        input: LLMInvocationInput(messages: messages).toJson(),
        output: llmOutput.toJson(),
      ),
    );

    return llmOutput.response;
  }

  List<Map<String, dynamic>> buildMessagesFromContext({
    required ContextBundle contextBundle,
    required String currentUtterance,
  }) {
    final contextMessages = <Map<String, dynamic>>[];

    final systemPrompt = StringBuffer();
    systemPrompt.writeln(
        'You are a helpful voice assistant. Keep responses brief and conversational - like you\'re talking to a friend, not writing an essay.');
    systemPrompt.writeln(
        '\nIMPORTANT: Only use tools when the user explicitly asks you to do something that requires a tool (like "set a timer" or "create a task"). For casual conversation, respond naturally without calling tools.');
    systemPrompt.writeln(
        '\nStyle: Short, direct answers. 1-2 sentences max unless asked for details. Avoid verbose explanations.');

    if (contextBundle.semanticContext.isNotEmpty) {
      systemPrompt.writeln('\n# Relevant Context (from semantic search):');
      for (final searchResult in contextBundle.semanticContext) {
        final chunkText = searchResult.chunk.text;
        final entityType = searchResult.chunk.sourceEntityType;
        final similarity = (searchResult.similarity * 100).toStringAsFixed(0);
        systemPrompt.writeln('- [$entityType, $similarity% match]: $chunkText');
      }
    }

    contextMessages.add({'role': 'system', 'content': systemPrompt.toString()});

    for (final llmInvocation in contextBundle.conversationThread) {
      final userPrompt = llmInvocation.input?['prompt'] as String?;
      if (userPrompt != null && userPrompt.isNotEmpty) {
        contextMessages.add({'role': 'user', 'content': userPrompt});
      }

      final assistantResponse = llmInvocation.output?['response'] as String?;
      if (assistantResponse != null && assistantResponse.isNotEmpty) {
        contextMessages.add({'role': 'assistant', 'content': assistantResponse});
      }
    }

    contextMessages.add({'role': 'user', 'content': currentUtterance});

    return contextMessages;
  }

  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    final implementer = _implementers[_defaultImplementer]!;

    final llmResponse = await implementer.chatWithTools(
      model: model,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    final lastUserMessage = messages.lastWhere(
      (msg) => msg['role'] == 'user',
      orElse: () => <String, dynamic>{'content': ''},
    );
    final lastUserPrompt = (lastUserMessage['content'] as String?) ?? '';

    await recordInvocation(
      'unknown', // TODO: Pass eventId from Coordinator
      Invocation(
        eventId: 'unknown',
        componentType: ComponentType.llm,
        implementer: implementer.implementerName,
        success: true,
        confidence: 1.0,
        input: {'prompt': lastUserPrompt, 'messages': messages},
        output: {'response': llmResponse.content},
      ),
    );

    return llmResponse;
  }

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
    final llmInput = LLMInvocationInput.fromJson(invocation.input!);
    final llmOutput = LLMInvocationOutput.fromJson(invocation.output!);

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
          child: Text(llmOutput.response),
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

    final implementerName = invocation.implementer ?? _defaultImplementer;

    final optimizer = _getOrCreateOptimizer(implementerName, userId);

    final state = await _getAdaptationState(implementerName, userId);

    final feedbackReward =
        feedback.action == core_feedback.FeedbackAction.confirm ? 1.0 : -1.0;

    await optimizer.recordTrial({
      'temperature': state.temperature,
      'topP': state.topP,
      'frequencyPenalty': state.frequencyPenalty,
      'presencePenalty': state.presencePenalty,
      'maxTokens': state.maxTokens,
    }, feedbackReward);

    final suggestedParams = await optimizer.suggestNext();

    final newParams = state.copyWith(
      temperature: suggestedParams['temperature'] as double,
      topP: suggestedParams['topP'] as double,
      frequencyPenalty: suggestedParams['frequencyPenalty'] as double,
      presencePenalty: suggestedParams['presencePenalty'] as double,
      maxTokens: suggestedParams['maxTokens'] as int,
    );

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
