import 'dart:convert';
import '../../core/adaptation_data.dart';
import '../../services/math/evaluation_math.dart';
import '../../services/prompt/prompt_types.dart';

/// Per-insight evaluation scores from LLM-as-judge.
///
/// Implements PromptFailure so the generic prompt improvement loop
/// can consume these without knowing about extraction.
class InsightEvaluation implements PromptFailure {
  final String insightContent;
  final bool groundedness;
  final bool atomicity;
  final bool selfContainment;
  final bool salience;
  final bool entityClarity;
  final bool formatCompliance;

  @override
  final String reasoning;

  InsightEvaluation({
    required this.insightContent,
    required this.groundedness,
    required this.atomicity,
    required this.selfContainment,
    required this.salience,
    required this.entityClarity,
    required this.formatCompliance,
    required this.reasoning,
  });

  @override
  String get outputContent => insightContent;

  @override
  Map<String, bool> get dimensionScores => {
        'groundedness': groundedness,
        'atomicity': atomicity,
        'selfContainment': selfContainment,
        'salience': salience,
        'entityClarity': entityClarity,
        'formatCompliance': formatCompliance,
      };

  double compositeScore(EvaluationWeights weights) {
    return (groundedness ? weights.groundednessWeight : 0) +
        (atomicity ? weights.atomicityWeight : 0) +
        (selfContainment ? weights.selfContainmentWeight : 0) +
        (salience ? weights.salienceWeight : 0) +
        (entityClarity ? weights.entityClarityWeight : 0) +
        (formatCompliance ? weights.formatWeight : 0);
  }

  bool get passesAllDimensions =>
      groundedness &&
      atomicity &&
      selfContainment &&
      salience &&
      entityClarity &&
      formatCompliance;

  Map<String, dynamic> toJson() => {
        'insightContent': insightContent,
        'groundedness': groundedness,
        'atomicity': atomicity,
        'selfContainment': selfContainment,
        'salience': salience,
        'entityClarity': entityClarity,
        'formatCompliance': formatCompliance,
        'reasoning': reasoning,
      };

  factory InsightEvaluation.fromJson(Map<String, dynamic> json) {
    return InsightEvaluation(
      insightContent: json['insightContent'] as String,
      groundedness: json['groundedness'] as bool,
      atomicity: json['atomicity'] as bool,
      selfContainment: json['selfContainment'] as bool,
      salience: json['salience'] as bool,
      entityClarity: json['entityClarity'] as bool,
      formatCompliance: json['formatCompliance'] as bool,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

class ExtractionSetEvaluation {
  final List<InsightEvaluation> insightScores;
  final double coverage;
  final double focus;

  ExtractionSetEvaluation({
    required this.insightScores,
    required this.coverage,
    required this.focus,
  });

  double get fInsight => harmonicMean(coverage, focus);

  double averageCompositeScore(EvaluationWeights weights) {
    if (insightScores.isEmpty) return 0;
    final total = insightScores.fold<double>(
      0,
      (sum, eval) => sum + eval.compositeScore(weights),
    );
    return total / insightScores.length;
  }

  Map<String, dynamic> toJson(EvaluationWeights weights) => {
        'insightCount': insightScores.length,
        'coverage': coverage,
        'focus': focus,
        'fInsight': fInsight,
        'averageCompositeScore': averageCompositeScore(weights),
        'dimensionPassRates': dimensionPassRates(),
        'insights': insightScores.map((e) => e.toJson()).toList(),
      };

  Map<String, double> dimensionPassRates() {
    if (insightScores.isEmpty) return {};
    final n = insightScores.length.toDouble();
    return {
      'groundedness': insightScores.where((e) => e.groundedness).length / n,
      'atomicity': insightScores.where((e) => e.atomicity).length / n,
      'selfContainment':
          insightScores.where((e) => e.selfContainment).length / n,
      'salience': insightScores.where((e) => e.salience).length / n,
      'entityClarity':
          insightScores.where((e) => e.entityClarity).length / n,
      'formatCompliance':
          insightScores.where((e) => e.formatCompliance).length / n,
    };
  }
}

/// Learnable weights for rubric dimensions.
class EvaluationWeights extends AdaptationData {
  final double groundednessWeight;
  final double salienceWeight;
  final double selfContainmentWeight;
  final double atomicityWeight;
  final double entityClarityWeight;
  final double formatWeight;

  EvaluationWeights({
    this.groundednessWeight = 0.25,
    this.salienceWeight = 0.25,
    this.selfContainmentWeight = 0.15,
    this.atomicityWeight = 0.10,
    this.entityClarityWeight = 0.10,
    this.formatWeight = 0.15,
  });

  factory EvaluationWeights.defaults() => EvaluationWeights();

  EvaluationWeights copyWith({
    double? groundednessWeight,
    double? salienceWeight,
    double? selfContainmentWeight,
    double? atomicityWeight,
    double? entityClarityWeight,
    double? formatWeight,
  }) {
    return EvaluationWeights(
      groundednessWeight: groundednessWeight ?? this.groundednessWeight,
      salienceWeight: salienceWeight ?? this.salienceWeight,
      selfContainmentWeight:
          selfContainmentWeight ?? this.selfContainmentWeight,
      atomicityWeight: atomicityWeight ?? this.atomicityWeight,
      entityClarityWeight: entityClarityWeight ?? this.entityClarityWeight,
      formatWeight: formatWeight ?? this.formatWeight,
    );
  }

  @override
  String toJson() => jsonEncode({
        'groundednessWeight': groundednessWeight,
        'salienceWeight': salienceWeight,
        'selfContainmentWeight': selfContainmentWeight,
        'atomicityWeight': atomicityWeight,
        'entityClarityWeight': entityClarityWeight,
        'formatWeight': formatWeight,
      });

  factory EvaluationWeights.fromJson(Map<String, dynamic> json) {
    return EvaluationWeights(
      groundednessWeight:
          (json['groundednessWeight'] as num?)?.toDouble() ?? 0.25,
      salienceWeight: (json['salienceWeight'] as num?)?.toDouble() ?? 0.25,
      selfContainmentWeight:
          (json['selfContainmentWeight'] as num?)?.toDouble() ?? 0.15,
      atomicityWeight:
          (json['atomicityWeight'] as num?)?.toDouble() ?? 0.10,
      entityClarityWeight:
          (json['entityClarityWeight'] as num?)?.toDouble() ?? 0.10,
      formatWeight: (json['formatWeight'] as num?)?.toDouble() ?? 0.15,
    );
  }

  /// Converts weights to DimensionSpec list for the generic mutator.
  List<DimensionSpec> toDimensionSpecs() => [
        DimensionSpec(
          name: 'groundedness',
          weight: groundednessWeight,
          failureGuidance:
              'emphasize extracting only what is explicitly stated, not inferred',
        ),
        DimensionSpec(
          name: 'atomicity',
          weight: atomicityWeight,
          failureGuidance:
              'add clearer instructions about one-fact-per-insight with examples of splitting compound statements',
        ),
        DimensionSpec(
          name: 'selfContainment',
          weight: selfContainmentWeight,
          failureGuidance:
              'add instructions about resolving pronouns and including sufficient context',
        ),
        DimensionSpec(
          name: 'salience',
          weight: salienceWeight,
          failureGuidance:
              'strengthen filtering criteria for what is worth extracting',
        ),
        DimensionSpec(
          name: 'entityClarity',
          weight: entityClarityWeight,
          failureGuidance:
              'add instructions about naming specific entities',
        ),
        DimensionSpec(
          name: 'formatCompliance',
          weight: formatWeight,
          failureGuidance:
              'add more format examples and explicit formatting rules',
        ),
      ];
}

/// Pairs source conversation turns with extracted insight strings for evaluation.
class EvaluationInput {
  final List<Map<String, dynamic>> sourceTurns;
  final List<String> insightContents;

  EvaluationInput({
    required this.sourceTurns,
    required this.insightContents,
  });
}
