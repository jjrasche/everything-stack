/// # ModelSelector
///
/// ## What it does
/// Selects the best LLM model for a query using Thompson Sampling.
/// Learns from user feedback to optimize model selection over time.
///
/// ## Algorithm
/// 1. Maintain Beta(α, β) posterior for each model from binary feedback
/// 2. Sample from each model's posterior distribution
/// 3. Select model with highest sampled value
/// 4. Update posterior based on feedback (success/failure)
///
/// ## Why Thompson Sampling?
/// - Handles exploration/exploitation tradeoff naturally
/// - Converges to optimal arm with good regret bounds
/// - Simple update rule: just increment success or failure count
/// - Graceful cold start (uniform prior)
///
/// ## Usage
/// ```dart
/// final selection = await modelSelector.selectModel(
///   eventId: 'evt_123',
///   utterance: 'Set a timer for 5 minutes',
/// );
/// print('Selected: ${selection.model}');
/// // Use selection.model in LLM call
/// ```

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/trainable.dart';
import '../../core/invocation.dart';
import '../../core/adaptation_state.dart';
import '../../core/adaptation_state_repository.dart';
import '../../domain/feedback.dart' as domain_feedback;
import '../types/model_selector_types.dart';
import '../trainer/thompson_sampling_optimizer.dart';

/// Trainable model selector using Thompson Sampling.
///
/// Learns which model performs best for the user based on feedback.
/// Balances exploration (trying less-used models) with exploitation
/// (using models that have performed well).
class ModelSelector with Trainable<ModelSelectorAdaptationData> {
  /// Available models by implementer.
  /// Key: implementer name (e.g., "groq")
  /// Value: list of model names
  final Map<String, List<String>> availableModels;

  /// Thompson Sampling optimizer for arm selection.
  final ThompsonSamplingOptimizer _optimizer;

  ModelSelector({
    required this.availableModels,
    ThompsonSamplingOptimizer? optimizer,
  }) : _optimizer = optimizer ?? ThompsonSamplingOptimizer();

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'model_selector';

  @override
  ModelSelectorAdaptationData createDefaultData() =>
      ModelSelectorAdaptationData.defaults();

  @override
  ModelSelectorAdaptationData deserializeData(String json) {
    if (json.isEmpty || json == '{}') {
      return createDefaultData();
    }
    return ModelSelectorAdaptationData.fromJson(
      Map<String, dynamic>.from(
        const JsonDecoder().convert(json) as Map,
      ),
    );
  }

  @override
  Map<String, (double, double)> getParameterBounds() {
    // Thompson Sampling doesn't use GP bounds - it updates stats directly.
    // But we still need to return something for the Trainable interface.
    // These bounds are informational only.
    return {
      'explorationBonus': (0.0, 1.0), // Reserved for future use
    };
  }

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    final output = ModelSelectorInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Model Selection:',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selected: ${output.selectedModel}'),
              Text(
                  'Confidence: ${(output.confidence * 100).toStringAsFixed(1)}%'),
              const SizedBox(height: 8),
              Text('Sampled scores:',
                  style: Theme.of(context).textTheme.labelSmall),
              ...output.sampledScores.entries.map((e) => Text(
                    '  ${e.key}: ${(e.value * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Was this model a good choice?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record positive feedback
              },
              child: const Text('Good'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Record negative feedback
              },
              child: const Text('Bad'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(
    Invocation invocation,
    domain_feedback.Feedback feedback,
  ) async {
    // 1. Extract which model was selected
    final output = invocation.output;
    if (output == null) {
      print('⚠️ [ModelSelector] Cannot train: invocation has no output');
      return;
    }

    final selectedModel = output['selectedModel'] as String?;
    if (selectedModel == null || selectedModel.isEmpty) {
      print('⚠️ [ModelSelector] Cannot train: no selectedModel in output');
      return;
    }

    // 2. Get current adaptation state
    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    // 3. Update stats based on feedback
    final currentStats = params.getStats(selectedModel);
    final isSuccess = feedback.action == domain_feedback.FeedbackAction.confirm;

    final newStats = isSuccess
        ? currentStats.addSuccess()
        : currentStats.addFailure();

    print('📊 [ModelSelector] Training from feedback:');
    print('   Model: $selectedModel');
    print('   Feedback: ${isSuccess ? "positive" : "negative"}');
    print('   Stats: ${currentStats.trials} → ${newStats.trials} trials');
    print('   Rate: ${(currentStats.expectedRate * 100).toStringAsFixed(1)}% → ${(newStats.expectedRate * 100).toStringAsFixed(1)}%');

    // 4. Save updated state
    final newParams = params.updateStats(selectedModel, newStats);

    state.dataJson = newParams.toJson();
    state.version++;
    state.lastUpdatedAt = DateTime.now();
    state.lastUpdateReason = 'trainFromFeedback';
    state.feedbackCountApplied++;

    await adaptationStateRepo.save(state);
    print('✅ [ModelSelector] Adaptation state saved');
  }

  // ============ Model Selection ============

  /// Select the best model for the given query using Thompson Sampling.
  ///
  /// Returns a [ModelSelection] with the chosen model and confidence.
  /// Records an invocation for training feedback.
  Future<ModelSelection> selectModel({
    required String eventId,
    required String utterance,
    String? userId,
  }) async {
    // 1. Get adaptation state (user-specific or global)
    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    // 2. Filter to active models that are still available
    final currentlyAvailable = getAvailableModelKeys().toSet();
    final activeStats = Map.fromEntries(
      params.modelStats.entries.where((e) =>
          params.activeModels.contains(e.key) &&
          currentlyAvailable.contains(e.key)),
    );

    // Log if any stale models were filtered out
    final staleModels = params.activeModels.difference(currentlyAvailable);
    if (staleModels.isNotEmpty) {
      print('⚠️ [ModelSelector] Filtered out stale models: $staleModels');
    }

    // 3. Thompson Sampling selection
    final result = _optimizer.selectArmWithScores(activeStats);

    String selectedKey;
    double confidence;
    Map<String, double> sampledScores;

    if (result == null) {
      // No active models - use default
      selectedKey = params.defaultModel;
      confidence = 0.5;
      sampledScores = {};
      print('⚠️ [ModelSelector] No active models, using default: $selectedKey');
    } else {
      selectedKey = result.arm;
      sampledScores = result.scores;
      confidence = params.getStats(selectedKey).expectedRate;
    }

    // 4. Parse selection
    final selection = ModelSelection.fromKey(
      selectedKey,
      confidence,
      sampledScores: sampledScores,
    );

    print('🎯 [ModelSelector] Selected: ${selection.model}');
    print('   Implementer: ${selection.implementer}');
    print('   Confidence: ${(confidence * 100).toStringAsFixed(1)}%');
    if (sampledScores.isNotEmpty) {
      print('   Sampled scores:');
      for (final entry in sampledScores.entries) {
        final stats = params.getStats(entry.key);
        print('     ${entry.key}: ${(entry.value * 100).toStringAsFixed(1)}% '
            '(${stats.successes}/${stats.trials} trials)');
      }
    }

    // 5. Record invocation for training
    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: componentType,
        implementer: null,
        success: true,
        confidence: confidence,
        input: ModelSelectorInvocationInput(utterance: utterance).toJson(),
        output: ModelSelectorInvocationOutput(
          selectedModel: selectedKey,
          confidence: confidence,
          sampledScores: sampledScores,
        ).toJson(),
      ),
    );

    return selection;
  }

  /// Get current model statistics (for debugging/UI).
  Future<Map<String, ModelStats>> getModelStats({String? userId}) async {
    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();
    return params.modelStats;
  }

  /// Get list of all available model keys.
  List<String> getAvailableModelKeys() {
    final keys = <String>[];
    for (final entry in availableModels.entries) {
      for (final model in entry.value) {
        keys.add('${entry.key}:$model');
      }
    }
    return keys;
  }

  /// Add a new model to the available models.
  ///
  /// The model will be added to the adaptation state with empty stats.
  Future<void> addModel(String implementer, String model) async {
    final key = '$implementer:$model';

    // Update available models
    availableModels.putIfAbsent(implementer, () => []);
    if (!availableModels[implementer]!.contains(model)) {
      availableModels[implementer]!.add(model);
    }

    // Update adaptation state
    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    if (!params.modelStats.containsKey(key)) {
      final newParams = params.copyWith(
        modelStats: {...params.modelStats, key: ModelStats.empty()},
        activeModels: {...params.activeModels, key},
      );
      state.dataJson = newParams.toJson();
      state.version++;
      await adaptationStateRepo.save(state);
    }
  }

  /// Enable or disable a model for selection.
  Future<void> setModelActive(String modelKey, bool active) async {
    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    final newActive = Set<String>.from(params.activeModels);
    if (active) {
      newActive.add(modelKey);
    } else {
      newActive.remove(modelKey);
    }

    final newParams = params.copyWith(activeModels: newActive);
    state.dataJson = newParams.toJson();
    state.version++;
    await adaptationStateRepo.save(state);
  }
}
