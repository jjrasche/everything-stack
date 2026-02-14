import 'package:flutter/foundation.dart';

import 'prompt_types.dart';

class ValidationResult {
  final bool accepted;
  final MetricMap candidateMetrics;
  final MetricMap baselineMetrics;
  final MetricMap deltas;
  final List<String> regressions;
  final double candidateFInsight;
  final double baselineFInsight;

  ValidationResult({
    required this.accepted,
    required this.candidateMetrics,
    required this.baselineMetrics,
    required this.deltas,
    required this.regressions,
    required this.candidateFInsight,
    required this.baselineFInsight,
  });

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'candidateFInsight': candidateFInsight,
        'baselineFInsight': baselineFInsight,
        'fInsightDelta': candidateFInsight - baselineFInsight,
        'regressions': regressions,
        'dimensionDeltas': deltas,
        'candidateMetrics': candidateMetrics,
        'baselineMetrics': baselineMetrics,
      };
}

/// Regression gate: rejects candidate if any dimension drops > threshold.
///
/// Generic: compares MetricMaps, knows nothing about extraction.
class PromptValidator {
  final double regressionThreshold;

  PromptValidator({this.regressionThreshold = 0.05});

  ValidationResult validate({
    required MetricMap candidateMetrics,
    required MetricMap baselineMetrics,
    required double candidateFInsight,
    required double baselineFInsight,
  }) {
    final deltas = <String, double>{};
    final regressions = <String>[];

    final allDimensions = {
      ...baselineMetrics.keys,
      ...candidateMetrics.keys,
    };

    for (final dimension in allDimensions) {
      final baseline = baselineMetrics[dimension] ?? 0.0;
      final candidate = candidateMetrics[dimension] ?? 0.0;
      final delta = candidate - baseline;
      deltas[dimension] = delta;

      if (delta < -regressionThreshold) {
        regressions.add(
          '$dimension: ${(baseline * 100).toStringAsFixed(1)}% → '
          '${(candidate * 100).toStringAsFixed(1)}% '
          '(${(delta * 100).toStringAsFixed(1)}% regression)',
        );
      }
    }

    final fInsightDelta = candidateFInsight - baselineFInsight;
    if (fInsightDelta < -regressionThreshold) {
      regressions.add(
        'fInsight: ${(baselineFInsight * 100).toStringAsFixed(1)}% → '
        '${(candidateFInsight * 100).toStringAsFixed(1)}% '
        '(${(fInsightDelta * 100).toStringAsFixed(1)}% regression)',
      );
    }

    final accepted = regressions.isEmpty;

    if (!accepted) {
      debugPrint(
        'PromptValidator: REJECTED - ${regressions.length} regressions: '
        '${regressions.join("; ")}',
      );
    } else {
      debugPrint(
        'PromptValidator: ACCEPTED - F_insight: '
        '${baselineFInsight.toStringAsFixed(3)} → '
        '${candidateFInsight.toStringAsFixed(3)}',
      );
    }

    return ValidationResult(
      accepted: accepted,
      candidateMetrics: candidateMetrics,
      baselineMetrics: baselineMetrics,
      deltas: deltas,
      regressions: regressions,
      candidateFInsight: candidateFInsight,
      baselineFInsight: baselineFInsight,
    );
  }
}
