import 'dart:convert';
import '../../core/adaptation_data.dart';

/// Model-specific token limits and learned optimal context.
class ModelContextConfig {
  /// Model identifier (e.g., "llama-3.3-70b-versatile")
  final String model;

  /// Maximum context window (hard limit)
  final int maxContextTokens;

  /// Learned optimal context tokens (trainable)
  /// Starts at default, GP optimizer adjusts based on feedback
  final int optimalContextTokens;

  /// Tokens reserved for response generation
  /// Context budget = maxContextTokens - reservedForResponse - optimalContextTokens overhead
  final int reservedForResponse;

  ModelContextConfig({
    required this.model,
    required this.maxContextTokens,
    required this.optimalContextTokens,
    this.reservedForResponse = 4096,
  });

  /// Effective context budget (what we can actually use)
  int get effectiveContextBudget =>
      optimalContextTokens.clamp(500, maxContextTokens - reservedForResponse);

  /// Create copy with updated optimal tokens
  ModelContextConfig copyWith({
    int? optimalContextTokens,
  }) {
    return ModelContextConfig(
      model: model,
      maxContextTokens: maxContextTokens,
      optimalContextTokens: optimalContextTokens ?? this.optimalContextTokens,
      reservedForResponse: reservedForResponse,
    );
  }

  Map<String, dynamic> toMap() => {
        'model': model,
        'maxContextTokens': maxContextTokens,
        'optimalContextTokens': optimalContextTokens,
        'reservedForResponse': reservedForResponse,
      };

  factory ModelContextConfig.fromMap(Map<String, dynamic> map) {
    return ModelContextConfig(
      model: map['model'] as String,
      maxContextTokens: map['maxContextTokens'] as int,
      optimalContextTokens: map['optimalContextTokens'] as int,
      reservedForResponse: map['reservedForResponse'] as int? ?? 4096,
    );
  }
}

/// Learned context capacity preferences per model.
class ContextCapacityAdaptationData extends AdaptationData {
  /// Model-specific configurations
  /// Key: "implementer:model" e.g., "groq:llama-3.3-70b-versatile"
  final Map<String, ModelContextConfig> modelConfigs;

  /// Default optimal context tokens for unknown models
  /// Used when model not in modelConfigs
  final int defaultOptimalTokens;

  ContextCapacityAdaptationData({
    required this.modelConfigs,
    this.defaultOptimalTokens = 4000,
  });

  /// Get config for a specific model (with fallback)
  ModelContextConfig getConfigForModel(String modelKey, {int? maxTokens}) {
    if (modelConfigs.containsKey(modelKey)) {
      return modelConfigs[modelKey]!;
    }

    return ModelContextConfig(
      model: modelKey,
      maxContextTokens: maxTokens ?? 128000,
      optimalContextTokens: defaultOptimalTokens,
    );
  }

  /// Default adaptation state with Groq models.
  factory ContextCapacityAdaptationData.defaults() {
    return ContextCapacityAdaptationData(
      modelConfigs: {
        // Groq models (128K context)
        'groq:llama-3.3-70b-versatile': ModelContextConfig(
          model: 'llama-3.3-70b-versatile',
          maxContextTokens: 128000,
          optimalContextTokens: 8000, // Start conservative
        ),
        'groq:llama-3.1-8b-instant': ModelContextConfig(
          model: 'llama-3.1-8b-instant',
          maxContextTokens: 128000,
          optimalContextTokens: 6000, // Smaller model, smaller context
        ),
      },
      defaultOptimalTokens: 4000,
    );
  }

  /// Deserialize from JSON.
  factory ContextCapacityAdaptationData.fromJson(Map<String, dynamic> json) {
    final configsJson = json['modelConfigs'] as Map<String, dynamic>? ?? {};
    final configs = configsJson.map((key, value) =>
        MapEntry(key, ModelContextConfig.fromMap(value as Map<String, dynamic>)));

    return ContextCapacityAdaptationData(
      modelConfigs: configs,
      defaultOptimalTokens: json['defaultOptimalTokens'] as int? ?? 4000,
    );
  }

  @override
  String toJson() => jsonEncode({
        'modelConfigs':
            modelConfigs.map((key, value) => MapEntry(key, value.toMap())),
        'defaultOptimalTokens': defaultOptimalTokens,
      });

  /// Create copy with updated model config
  ContextCapacityAdaptationData copyWithModelConfig(
    String modelKey,
    ModelContextConfig config,
  ) {
    return ContextCapacityAdaptationData(
      modelConfigs: {...modelConfigs, modelKey: config},
      defaultOptimalTokens: defaultOptimalTokens,
    );
  }
}

/// Result of context truncation.
class TruncationResult {
  /// Truncated messages that fit within budget
  final List<Map<String, dynamic>> messages;

  /// Total tokens in truncated messages
  final int totalTokens;

  /// Token budget that was used
  final int tokenBudget;

  /// Whether truncation occurred
  final bool wasTruncated;

  /// Number of messages removed
  final int messagesRemoved;

  /// Tokens removed by truncation
  final int tokensRemoved;

  TruncationResult({
    required this.messages,
    required this.totalTokens,
    required this.tokenBudget,
    required this.wasTruncated,
    this.messagesRemoved = 0,
    this.tokensRemoved = 0,
  });

  /// Debug summary
  String get summary => wasTruncated
      ? 'Truncated: $totalTokens/$tokenBudget tokens, removed $messagesRemoved messages'
      : 'No truncation: $totalTokens/$tokenBudget tokens';
}

/// Invocation input for ContextCapacity.
class ContextCapacityInvocationInput {
  /// Model being used
  final String model;

  /// Original token count before truncation
  final int originalTokens;

  /// Messages before truncation
  final int originalMessageCount;

  ContextCapacityInvocationInput({
    required this.model,
    required this.originalTokens,
    required this.originalMessageCount,
  });

  Map<String, dynamic> toMap() => {
        'model': model,
        'originalTokens': originalTokens,
        'originalMessageCount': originalMessageCount,
      };
}

/// Invocation output for ContextCapacity.
class ContextCapacityInvocationOutput {
  /// Token budget used
  final int tokenBudget;

  /// Final token count
  final int finalTokens;

  /// Whether truncation occurred
  final bool wasTruncated;

  /// Messages removed
  final int messagesRemoved;

  ContextCapacityInvocationOutput({
    required this.tokenBudget,
    required this.finalTokens,
    required this.wasTruncated,
    required this.messagesRemoved,
  });

  Map<String, dynamic> toMap() => {
        'tokenBudget': tokenBudget,
        'finalTokens': finalTokens,
        'wasTruncated': wasTruncated,
        'messagesRemoved': messagesRemoved,
      };
}
