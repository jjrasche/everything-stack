/// # LLMService
///
/// Smart orchestration service for LLM capabilities.
/// Holds multiple LLM implementations and coordinates adaptation learning.
///
/// ## Key Responsibilities
/// - Hold Map<String, LLMImplementer> (Groq, Claude, etc.)
/// - Select implementer (specified or default)
/// - Read/apply adaptation state per implementer
/// - Log invocations for training feedback
/// - Train from feedback (update AdaptationState)
///
/// ## Design Pattern
/// Service (smart, orchestration) = Composition of Implementers (dumb, API wrappers)
/// Service knows HOW to use implementer, Implementer knows HOW to call API.

import 'dart:math' show min;
import 'package:flutter/material.dart';

import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/adaptation_state.dart';
import '../core/feedback.dart';
import '../core/feedback_repository.dart';
import '../core/trainable.dart';
import '../core/component_types.dart';
import './implementations/llm_implementer.dart';
import './types/llm_types.dart';
import './types/message.dart';

class LLMService implements Trainable {
  final Map<String, LLMImplementer> _implementers;
  final String _defaultImplementer;
  final InvocationRepository invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  LLMService({
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
    final state = await _getAdaptationState(implementer.implementerName, userId);

    // 3. Call implementer with adapted parameters
    final output = await implementer.chat(
      messages: messages,
      temperature: state.temperature,
      systemPrompt: state.systemPrompt,
    );

    // 4. Log invocation for training feedback
    final invocation = Invocation(
      eventId: eventId,
      componentType: ComponentType.llm,
      implementer: implementer.implementerName,
      success: true,
      confidence: 1.0,
      input: LLMInvocationInput(messages: messages).toJson(),
      output: output.toJson(),
    );
    await invocationRepo.save(invocation);

    // 5. Return response
    return output.response;
  }

  /// Get adaptation state for this implementer, or defaults if not found.
  Future<LLMAdaptationData> _getAdaptationState(
    String implementerName,
    String? userId,
  ) async {
    final state = await adaptationStateRepo.getForComponent(
      ComponentType.llm,
      implementer: implementerName,
      userId: userId,
    );

    return state != null
        ? LLMAdaptationData.fromJson(state.data)
        : LLMAdaptationData.defaults();
  }

  // ============ Trainable Implementation ============

  @override
  Widget buildFeedbackUI(Invocation invocation) {
    // Parse typed input/output from invocation
    final input = LLMInvocationInput.fromJson(invocation.input!);
    final output = LLMInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LLM Response:', style: Theme.of(null).textTheme.labelLarge),
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
        Text('Was this response helpful?', style: Theme.of(null).textTheme.labelLarge),
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
  Future<void> trainFromFeedback(String invocationId, Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: LLMFeedback.fromJson(feedback.correctedData)
    // 2. Get current AdaptationState for feedback.implementer
    // 3. Update temperature/responseLength based on feedback
    // 4. Save updated AdaptationState
  }
}
