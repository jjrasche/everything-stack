/// # Model Selector Type Definitions
///
/// Types for ModelSelector service: adaptation data, model stats, and selection results.
/// Uses Thompson Sampling with Beta-Bernoulli for learned model selection.

import 'dart:convert';
import '../../core/adaptation_data.dart';

/// Per-model performance statistics for Thompson Sampling.
///
/// Tracks successes (positive feedback) and failures (negative feedback)
/// for a single model. Used to compute Beta distribution parameters
/// for Thompson Sampling selection.
class ModelStats {
  /// Count of positive feedback (good responses)
  final int successes;

  /// Count of negative feedback (bad responses)
  final int failures;

  const ModelStats({
    required this.successes,
    required this.failures,
  });

  /// Beta distribution alpha parameter (successes + 1 for Jeffreys prior)
  double get alpha => successes + 1.0;

  /// Beta distribution beta parameter (failures + 1 for Jeffreys prior)
  double get beta => failures + 1.0;

  /// Expected success rate: alpha / (alpha + beta)
  double get expectedRate => alpha / (alpha + beta);

  /// Total number of trials
  int get trials => successes + failures;

  /// Create with no data (uniform prior)
  factory ModelStats.empty() => const ModelStats(successes: 0, failures: 0);

  /// Deserialize from JSON
  factory ModelStats.fromJson(Map<String, dynamic> json) => ModelStats(
        successes: json['successes'] as int? ?? 0,
        failures: json['failures'] as int? ?? 0,
      );

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
        'successes': successes,
        'failures': failures,
      };

  /// Create copy with updated values
  ModelStats copyWith({
    int? successes,
    int? failures,
  }) =>
      ModelStats(
        successes: successes ?? this.successes,
        failures: failures ?? this.failures,
      );

  /// Add a success
  ModelStats addSuccess() => copyWith(successes: successes + 1);

  /// Add a failure
  ModelStats addFailure() => copyWith(failures: failures + 1);

  @override
  String toString() =>
      'ModelStats(successes: $successes, failures: $failures, rate: ${(expectedRate * 100).toStringAsFixed(1)}%)';
}

/// Learned model selection preferences (trainable parameters).
///
/// Stores Thompson Sampling statistics for each model and controls
/// which models are active for selection.
class ModelSelectorAdaptationData extends AdaptationData {
  /// Per-model statistics for Thompson Sampling.
  /// Key format: "implementer:model" e.g., "groq:llama-3.3-70b-versatile"
  final Map<String, ModelStats> modelStats;

  /// Set of currently active model keys.
  /// Only active models participate in selection.
  final Set<String> activeModels;

  /// Default model to use when all have equal stats or no data.
  final String defaultModel;

  ModelSelectorAdaptationData({
    required this.modelStats,
    required this.activeModels,
    required this.defaultModel,
  });

  /// Default adaptation state with Groq models.
  factory ModelSelectorAdaptationData.defaults() {
    const defaultModels = [
      'groq:llama-3.3-70b-versatile',
      'groq:llama-3.1-8b-instant',
      'groq:mixtral-8x7b-32768',
    ];

    return ModelSelectorAdaptationData(
      modelStats: {
        for (final model in defaultModels) model: ModelStats.empty(),
      },
      activeModels: defaultModels.toSet(),
      defaultModel: 'groq:llama-3.3-70b-versatile',
    );
  }

  /// Deserialize from JSON.
  factory ModelSelectorAdaptationData.fromJson(Map<String, dynamic> json) {
    final statsJson = json['modelStats'] as Map<String, dynamic>? ?? {};
    final modelStats = statsJson.map(
      (key, value) => MapEntry(
        key,
        ModelStats.fromJson(value as Map<String, dynamic>),
      ),
    );

    final activeList = json['activeModels'] as List<dynamic>? ?? [];
    final activeModels = activeList.map((e) => e as String).toSet();

    return ModelSelectorAdaptationData(
      modelStats: modelStats,
      activeModels: activeModels,
      defaultModel:
          json['defaultModel'] as String? ?? 'groq:llama-3.3-70b-versatile',
    );
  }

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
        'modelStats':
            modelStats.map((key, value) => MapEntry(key, value.toJson())),
        'activeModels': activeModels.toList(),
        'defaultModel': defaultModel,
      });

  /// Create copy with updated values.
  ModelSelectorAdaptationData copyWith({
    Map<String, ModelStats>? modelStats,
    Set<String>? activeModels,
    String? defaultModel,
  }) =>
      ModelSelectorAdaptationData(
        modelStats: modelStats ?? this.modelStats,
        activeModels: activeModels ?? this.activeModels,
        defaultModel: defaultModel ?? this.defaultModel,
      );

  /// Get stats for a model, creating empty stats if not found.
  ModelStats getStats(String modelKey) =>
      modelStats[modelKey] ?? ModelStats.empty();

  /// Update stats for a single model.
  ModelSelectorAdaptationData updateStats(
      String modelKey, ModelStats newStats) {
    return copyWith(
      modelStats: {...modelStats, modelKey: newStats},
    );
  }
}

/// Result of model selection.
class ModelSelection {
  /// Implementer name (e.g., "groq")
  final String implementer;

  /// Model name (e.g., "llama-3.3-70b-versatile")
  final String model;

  /// Expected success rate (confidence)
  final double confidence;

  /// Sampled scores for each model (debug info)
  final Map<String, double> sampledScores;

  ModelSelection({
    required this.implementer,
    required this.model,
    required this.confidence,
    this.sampledScores = const {},
  });

  /// Full model key in "implementer:model" format
  String get modelKey => '$implementer:$model';

  /// Parse from "implementer:model" key format.
  factory ModelSelection.fromKey(
    String key,
    double confidence, {
    Map<String, double> sampledScores = const {},
  }) {
    final parts = key.split(':');
    if (parts.length != 2) {
      throw ArgumentError('Invalid model key format: $key (expected "impl:model")');
    }
    return ModelSelection(
      implementer: parts[0],
      model: parts[1],
      confidence: confidence,
      sampledScores: sampledScores,
    );
  }

  @override
  String toString() =>
      'ModelSelection($implementer:$model, conf: ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Input for ModelSelector invocation logging.
class ModelSelectorInvocationInput {
  final String utterance;

  ModelSelectorInvocationInput({required this.utterance});

  factory ModelSelectorInvocationInput.fromJson(Map<String, dynamic> json) =>
      ModelSelectorInvocationInput(
        utterance: json['utterance'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'utterance': utterance,
      };
}

/// Output for ModelSelector invocation logging.
class ModelSelectorInvocationOutput {
  /// Selected model key ("implementer:model")
  final String selectedModel;

  /// Confidence (expected success rate)
  final double confidence;

  /// Sampled values for each model (debug)
  final Map<String, double> sampledScores;

  ModelSelectorInvocationOutput({
    required this.selectedModel,
    required this.confidence,
    this.sampledScores = const {},
  });

  factory ModelSelectorInvocationOutput.fromJson(Map<String, dynamic> json) {
    final scoresJson = json['sampledScores'] as Map<String, dynamic>? ?? {};
    return ModelSelectorInvocationOutput(
      selectedModel: json['selectedModel'] as String? ?? '',
      confidence: json['confidence'] as double? ?? 0.5,
      sampledScores:
          scoresJson.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  Map<String, dynamic> toJson() => {
        'selectedModel': selectedModel,
        'confidence': confidence,
        'sampledScores': sampledScores,
      };
}
