/// # Context Selector Type Definitions
///
/// Types for ContextSelector service: adaptation data, context bundle, and results.

import 'dart:convert';
import '../../core/adaptation_data.dart';
import '../../core/invocation.dart';
import '../semantic_search/search_result.dart';

/// Learned context selection preferences (trainable parameters).
class ContextSelectorAdaptationData extends AdaptationData {
  /// How many recent STT/LLM pairs to include in conversation thread
  final int conversationThreadSize;

  /// Decay factor for conversation thread
  /// Turns from 24 hours ago = 0.5x weight
  /// Turns from 48 hours ago = 0.25x weight
  /// Goal: Keep recent conversation relevant but fade old tangents
  final double conversationHalfLifeHours;

  /// Max number of semantic context results to include
  /// These are embedded entities from across the system
  final int maxSemanticResults;

  /// Decay factor for semantic context
  /// Facts from 1 month (720h) ago = 0.5x weight
  /// Facts from 2 months ago = 0.25x weight
  /// Goal: Knowledge persists long term but older is less trusted
  final double semanticHalfLifeHours;

  /// Minimum semantic similarity score to include
  final double semanticThreshold;

  /// Exponent for similarity in conversation thread scoring
  /// score = similarity^α × decay^β
  /// Higher α = similarity matters more
  /// α=0 ignores similarity, α=2 squares similarity
  final double similarityAlpha;

  /// Exponent for decay in conversation thread scoring
  /// score = similarity^α × decay^β
  /// Higher β = recency matters more
  /// β=0 ignores recency, β=2 squares decay
  final double decayBeta;

  ContextSelectorAdaptationData({
    required this.conversationThreadSize,
    required this.conversationHalfLifeHours,
    required this.maxSemanticResults,
    required this.semanticHalfLifeHours,
    required this.semanticThreshold,
    required this.similarityAlpha,
    required this.decayBeta,
  });

  /// Default adaptation state (untrained).
  factory ContextSelectorAdaptationData.defaults() =>
      ContextSelectorAdaptationData(
        conversationThreadSize: 5,
        conversationHalfLifeHours: 24.0, // 1 day
        maxSemanticResults: 10,
        semanticHalfLifeHours: 720.0, // 1 month
        semanticThreshold: 0.7,
        similarityAlpha: 1.0, // Linear similarity
        decayBeta: 0.5, // Decay matters less than similarity
      );

  /// Deserialize from JSON.
  factory ContextSelectorAdaptationData.fromJson(Map<String, dynamic> json) =>
      ContextSelectorAdaptationData(
        conversationThreadSize: json['conversationThreadSize'] as int? ?? 5,
        conversationHalfLifeHours:
            json['conversationHalfLifeHours'] as double? ?? 24.0,
        maxSemanticResults: json['maxSemanticResults'] as int? ?? 10,
        semanticHalfLifeHours:
            json['semanticHalfLifeHours'] as double? ?? 720.0,
        semanticThreshold: json['semanticThreshold'] as double? ?? 0.7,
        similarityAlpha: json['similarityAlpha'] as double? ?? 1.0,
        decayBeta: json['decayBeta'] as double? ?? 0.5,
      );

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
        'conversationThreadSize': conversationThreadSize,
        'conversationHalfLifeHours': conversationHalfLifeHours,
        'maxSemanticResults': maxSemanticResults,
        'semanticHalfLifeHours': semanticHalfLifeHours,
        'semanticThreshold': semanticThreshold,
        'similarityAlpha': similarityAlpha,
        'decayBeta': decayBeta,
      });

  /// Create a copy with modified fields (for GP optimizer updates).
  ContextSelectorAdaptationData copyWith({
    int? conversationThreadSize,
    double? conversationHalfLifeHours,
    int? maxSemanticResults,
    double? semanticHalfLifeHours,
    double? semanticThreshold,
    double? similarityAlpha,
    double? decayBeta,
  }) {
    return ContextSelectorAdaptationData(
      conversationThreadSize:
          conversationThreadSize ?? this.conversationThreadSize,
      conversationHalfLifeHours:
          conversationHalfLifeHours ?? this.conversationHalfLifeHours,
      maxSemanticResults: maxSemanticResults ?? this.maxSemanticResults,
      semanticHalfLifeHours:
          semanticHalfLifeHours ?? this.semanticHalfLifeHours,
      semanticThreshold: semanticThreshold ?? this.semanticThreshold,
      similarityAlpha: similarityAlpha ?? this.similarityAlpha,
      decayBeta: decayBeta ?? this.decayBeta,
    );
  }
}

/// Context bundle returned by ContextSelector.
/// Contains both conversation thread and relevant semantic context.
class ContextBundle {
  /// Recent LLM invocations forming conversation thread
  /// Maps cleanly to user/assistant message pairs
  /// Each LLM invocation has input.prompt (user) and output.response (assistant)
  final List<Invocation> conversationThread;

  /// Semantically relevant chunks from ANY chunkable entity
  /// Includes chunk text, source entity, and similarity score
  /// Gets summarized into system message
  final List<SemanticSearchResult> semanticContext;

  /// Adaptation state that generated this bundle
  final ContextSelectorAdaptationData params;

  ContextBundle({
    required this.conversationThread,
    required this.semanticContext,
    required this.params,
  });

  /// Total items in bundle
  int get totalItems =>
      conversationThread.length + semanticContext.length;

  /// Debug string showing bundle composition
  String get summary =>
      'ContextBundle: ${conversationThread.length} conversation, ${semanticContext.length} semantic';
}
