/// # LLMConfigSelector
///
/// ## What it does
/// Trainable component that selects LLM configuration for a request.
/// Learns which temperature, model, and parameters work best for different requests.
///
/// ## Input
/// - utterance: User's request
/// - namespace: Selected namespace
/// - tools: Tools that will be available
///
/// ## Output
/// - config: Selected LLM configuration {temperature, model, maxTokens, etc.}
///
/// ## Training
/// When user feedback indicates poor LLM response:
/// - Adjust temperature (higher for creative, lower for factual)
/// - Track response quality scores
/// - Learn which configurations work for different namespaces

import 'package:flutter/material.dart';
import '../trainable.dart';
import '../../domain/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/adaptation_state_repository.dart';
import '../../core/adaptation_state.dart';
import '../../core/feedback_repository.dart';
import 'dart:convert';

class LLMConfigSelector implements Trainable {
  final InvocationRepository<Invocation> invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  LLMConfigSelector({
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  });

  /// Select LLM configuration
  ///
  /// For now, returns default config.
  /// Will learn to adjust temperature and other parameters based on feedback.
  Future<Map<String, dynamic>> selectConfig({
    required String correlationId,
    required String utterance,
    required String namespace,
    required List<String> tools,
  }) async {
    // Default LLM config
    final config = <String, dynamic>{
      'model': 'llama-3.1-8b-instant',
      'temperature': 0.7,
      'maxTokens': 2048,
      'topP': 0.95,
      'topK': 50,
    };

    // Record invocation
    final invocation = Invocation(
      correlationId: correlationId,
      componentType: 'llm_config_selector',
      success: true,
      confidence: 1.0,
      input: {
        'utterance': utterance,
        'namespace': namespace,
        'tools': tools,
      },
      output: {
        'selectedConfig': config,
      },
    );
    await recordInvocation(invocation);
    return config;
  }

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! Invocation) {
      throw ArgumentError('Expected Invocation');
    }
    await invocationRepo.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // Get all feedback for llm_config_selector on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'llm_config_selector',
    );

    if (feedbackList.isEmpty) return;

    // Get current adaptation state
    final state = await adaptationStateRepo.getCurrent(userId: userId);
    state.loadData();

    // Process each feedback
    for (final feedback in feedbackList) {
      if (!feedback.hasCorrection) continue;

      // Load the invocation
      final invocation = await invocationRepo.findById(feedback.invocationId);
      if (invocation == null) continue;

      // Parse corrected data as JSON {quality: 'good'|'poor'|'hallucinated', temperature?: 0.8}
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (corrected['quality'] is String) {
        final quality = corrected['quality'] as String;

        // Update state data (track response quality)
        Map<String, dynamic> data = state.data;

        switch (quality) {
          case 'good':
            data['goodResponses'] = (data['goodResponses'] as int? ?? 0) + 1;
            break;
          case 'poor':
            data['poorResponses'] = (data['poorResponses'] as int? ?? 0) + 1;
            // Suggest lower temperature
            data['recommendedTemperature'] = 0.5;
            break;
          case 'hallucinated':
            data['hallucinatedResponses'] =
                (data['hallucinatedResponses'] as int? ?? 0) + 1;
            // Suggest even lower temperature
            data['recommendedTemperature'] = 0.3;
            break;
        }

        state.data = data;
        state.version++;
        state.lastUpdatedAt = DateTime.now();
        state.lastUpdateReason = 'trainFromFeedback';
        state.feedbackCountApplied++;

        await adaptationStateRepo.save(state);
      }
    }
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    final state = await adaptationStateRepo.getCurrent(userId: userId);
    state.loadData();
    return state.data;
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement UI for rating LLM response quality
    // Should allow user to rate as good/poor/hallucinated
    return Placeholder();
  }
}
