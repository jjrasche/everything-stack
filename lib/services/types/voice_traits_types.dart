/// # VoiceTraits Type Definitions
///
/// Types for contrastive few-shot example retrieval.
/// VoiceTraits retrieves positive and negative examples from past
/// interactions based on user feedback.
///
/// ## Trainable Parameters
/// VoiceTraits learns optimal retrieval settings from feedback:
/// - maxPositiveExamples: How many good examples improve quality
/// - maxNegativeExamples: How many bad examples help avoidance
/// - minSimilarity: Threshold for "relevant enough"
/// - decayAlpha: How much to weight recent examples over old ones

import 'dart:convert';
import 'dart:math' as math;
import '../../core/adaptation_data.dart';
import '../../core/invocation.dart';
import '../../domain/feedback.dart';

/// A past interaction with its feedback signal.
///
/// Used for contrastive few-shot prompt construction.
class FeedbackExample {
  /// The original user query/utterance
  final String query;

  /// The assistant's response
  final String response;

  /// The feedback action (confirm = positive, deny = negative)
  final FeedbackAction feedbackAction;

  /// Similarity to current query (0.0-1.0)
  final double similarity;

  /// Source invocation UUID (for debugging)
  final String invocationId;

  /// When the interaction occurred
  final DateTime timestamp;

  /// Combined score (similarity × decay)
  /// Used for ranking examples when selecting top-k
  final double score;

  FeedbackExample({
    required this.query,
    required this.response,
    required this.feedbackAction,
    required this.similarity,
    required this.invocationId,
    required this.timestamp,
    double? score,
  }) : score = score ?? similarity; // Default to similarity if not provided

  /// Is this a positive example?
  bool get isPositive => feedbackAction == FeedbackAction.confirm;

  /// Is this a negative example?
  bool get isNegative => feedbackAction == FeedbackAction.deny;

  @override
  String toString() =>
      'FeedbackExample(${isPositive ? "+" : "-"} score=${(score * 100).toStringAsFixed(1)}%)';
}

/// Contrastive examples for few-shot prompting.
///
/// Contains positive (liked) and negative (disliked) examples
/// similar to the current query.
class ContrastiveExamples {
  /// Positive examples (confirmed as good)
  final List<FeedbackExample> positive;

  /// Negative examples (denied as bad)
  final List<FeedbackExample> negative;

  ContrastiveExamples({
    required this.positive,
    required this.negative,
  });

  /// No examples available
  factory ContrastiveExamples.empty() => ContrastiveExamples(
        positive: [],
        negative: [],
      );

  /// Do we have any examples?
  bool get hasExamples => positive.isNotEmpty || negative.isNotEmpty;

  /// Total number of examples
  int get totalCount => positive.length + negative.length;

  @override
  String toString() =>
      'ContrastiveExamples(+${positive.length}, -${negative.length})';
}

/// Configuration for VoiceTraits retrieval.
class VoiceTraitsConfig {
  /// Maximum positive examples to retrieve
  final int maxPositiveExamples;

  /// Maximum negative examples to retrieve
  final int maxNegativeExamples;

  /// Minimum similarity threshold (0.0-1.0)
  final double minSimilarity;

  /// Maximum age of examples (null = no limit)
  final Duration? maxAge;

  const VoiceTraitsConfig({
    this.maxPositiveExamples = 2,
    this.maxNegativeExamples = 1,
    this.minSimilarity = 0.3,
    this.maxAge,
  });

  /// Default configuration
  static const defaults = VoiceTraitsConfig();
}

/// Learned parameters for VoiceTraits retrieval.
///
/// Controls how many examples to retrieve and how to score them.
/// Updated via feedback training.
class VoiceTraitsAdaptationData extends AdaptationData {
  /// Maximum positive examples to inject into prompt
  final int maxPositiveExamples;

  /// Maximum negative examples to inject into prompt
  final int maxNegativeExamples;

  /// Minimum similarity threshold (0.0-1.0)
  final double minSimilarity;

  /// Decay exponent for age scoring.
  /// Higher = stronger preference for recent examples.
  /// Formula: decay = 1 / (1 + ageInDays * decayRate) ^ decayAlpha
  final double decayAlpha;

  /// Decay rate per day (0.0-1.0).
  /// At 0.1: 10-day-old examples have ~50% weight.
  final double decayRate;

  VoiceTraitsAdaptationData({
    required this.maxPositiveExamples,
    required this.maxNegativeExamples,
    required this.minSimilarity,
    required this.decayAlpha,
    required this.decayRate,
  });

  /// Default values tuned for typical conversational assistants
  factory VoiceTraitsAdaptationData.defaults() => VoiceTraitsAdaptationData(
        maxPositiveExamples: 2,
        maxNegativeExamples: 1,
        minSimilarity: 0.3,
        decayAlpha: 1.0,
        decayRate: 0.1,
      );

  @override
  String toJson() => jsonEncode({
        'maxPositiveExamples': maxPositiveExamples,
        'maxNegativeExamples': maxNegativeExamples,
        'minSimilarity': minSimilarity,
        'decayAlpha': decayAlpha,
        'decayRate': decayRate,
      });

  factory VoiceTraitsAdaptationData.fromJson(Map<String, dynamic> json) =>
      VoiceTraitsAdaptationData(
        maxPositiveExamples: json['maxPositiveExamples'] as int? ?? 2,
        maxNegativeExamples: json['maxNegativeExamples'] as int? ?? 1,
        minSimilarity: (json['minSimilarity'] as num?)?.toDouble() ?? 0.3,
        decayAlpha: (json['decayAlpha'] as num?)?.toDouble() ?? 1.0,
        decayRate: (json['decayRate'] as num?)?.toDouble() ?? 0.1,
      );

  VoiceTraitsAdaptationData copyWith({
    int? maxPositiveExamples,
    int? maxNegativeExamples,
    double? minSimilarity,
    double? decayAlpha,
    double? decayRate,
  }) =>
      VoiceTraitsAdaptationData(
        maxPositiveExamples: maxPositiveExamples ?? this.maxPositiveExamples,
        maxNegativeExamples: maxNegativeExamples ?? this.maxNegativeExamples,
        minSimilarity: minSimilarity ?? this.minSimilarity,
        decayAlpha: decayAlpha ?? this.decayAlpha,
        decayRate: decayRate ?? this.decayRate,
      );

  /// Compute decay factor for an example of given age.
  ///
  /// Returns value in [0, 1] where 1 = brand new, approaching 0 = very old.
  double computeDecay(Duration age) {
    final ageInDays = age.inHours / 24.0;
    return 1.0 / (1.0 + ageInDays * decayRate);
  }

  /// Compute final score for an example.
  ///
  /// Combines similarity and decay: score = similarity × decay^α
  double computeScore(double similarity, Duration age) {
    final decay = computeDecay(age);
    return similarity * math.pow(decay, decayAlpha);
  }
}

/// Input for VoiceTraits invocation logging.
class VoiceTraitsInvocationInput {
  final String query;
  final int candidatesSearched;

  VoiceTraitsInvocationInput({
    required this.query,
    required this.candidatesSearched,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        'candidatesSearched': candidatesSearched,
      };
}

/// Output for VoiceTraits invocation logging.
class VoiceTraitsInvocationOutput {
  final int positiveCount;
  final int negativeCount;
  final List<String> exampleIds;
  final double avgScore;

  VoiceTraitsInvocationOutput({
    required this.positiveCount,
    required this.negativeCount,
    required this.exampleIds,
    this.avgScore = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'positiveCount': positiveCount,
        'negativeCount': negativeCount,
        'exampleIds': exampleIds,
        'avgScore': avgScore,
      };
}
