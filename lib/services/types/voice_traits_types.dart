/// # VoiceTraits Type Definitions
///
/// Types for contrastive few-shot example retrieval.
/// VoiceTraits retrieves positive and negative examples from past
/// interactions based on user feedback.

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

  FeedbackExample({
    required this.query,
    required this.response,
    required this.feedbackAction,
    required this.similarity,
    required this.invocationId,
    required this.timestamp,
  });

  /// Is this a positive example?
  bool get isPositive => feedbackAction == FeedbackAction.confirm;

  /// Is this a negative example?
  bool get isNegative => feedbackAction == FeedbackAction.deny;

  @override
  String toString() =>
      'FeedbackExample(${isPositive ? "+" : "-"} sim=${(similarity * 100).toStringAsFixed(1)}%)';
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

  VoiceTraitsInvocationOutput({
    required this.positiveCount,
    required this.negativeCount,
    required this.exampleIds,
  });

  Map<String, dynamic> toJson() => {
        'positiveCount': positiveCount,
        'negativeCount': negativeCount,
        'exampleIds': exampleIds,
      };
}
