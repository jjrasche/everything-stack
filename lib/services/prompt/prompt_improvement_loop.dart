import 'package:flutter/foundation.dart';

import '../../core/debug/debug_introspectable.dart';
import '../math/evaluation_math.dart';
import 'prompt_mutator.dart';
import 'prompt_registry.dart';
import 'prompt_types.dart';
import 'prompt_validator.dart';

class ImprovementCycleResult {
  final bool improved;
  final int? newVersion;
  final String reasoning;
  final Map<String, dynamic> baselineMetrics;
  final Map<String, dynamic> candidateMetrics;
  final ValidationResult? validation;
  final Duration duration;

  ImprovementCycleResult({
    required this.improved,
    this.newVersion,
    required this.reasoning,
    required this.baselineMetrics,
    required this.candidateMetrics,
    this.validation,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'improved': improved,
        'newVersion': newVersion,
        'reasoning': reasoning,
        'baselineMetrics': baselineMetrics,
        'candidateMetrics': candidateMetrics,
        'validation': validation?.toJson(),
        'durationSeconds': duration.inSeconds,
      };
}

/// Evaluation result produced by the caller's evaluate callback.
class EvaluationResult {
  final List<PromptFailure> failures;
  final MetricMap dimensionRates;
  final double coverage;
  final double focus;

  EvaluationResult({
    required this.failures,
    required this.dimensionRates,
    required this.coverage,
    required this.focus,
  });

  double get fInsight => harmonicMean(coverage, focus);
}

/// Generic Generate-Evaluate-Mutate orchestrator.
///
/// Knows nothing about extraction. Callers provide:
/// - [extractFn]: runs the prompt on input data → outputs
/// - [evaluateFn]: scores outputs → failures + metrics
/// - [dimensions]: DimensionSpec list for the mutator
class PromptImprovementLoop<TInput> with DebugIntrospectable {
  final PromptRegistry _registry;
  final PromptMutator _mutator;
  final PromptValidator _validator;
  final List<DimensionSpec> dimensions;

  /// Extract outputs from input using a given prompt.
  final Future<List<String>> Function(TInput input, String prompt) extractFn;

  /// Evaluate outputs against source, returning failures and metrics.
  final Future<EvaluationResult> Function(
    TInput input,
    List<String> outputs,
  ) evaluateFn;

  int _cycleCount = 0;
  int _improvementCount = 0;
  int _rejectionCount = 0;
  DateTime? _lastCycleAt;
  bool _isRunning = false;

  PromptImprovementLoop({
    required PromptRegistry registry,
    required PromptMutator mutator,
    required PromptValidator validator,
    required this.dimensions,
    required this.extractFn,
    required this.evaluateFn,
  })  : _registry = registry,
        _mutator = mutator,
        _validator = validator;

  bool get isRunning => _isRunning;

  Future<ImprovementCycleResult> runCycle({
    required List<TInput> goldenInputs,
    int maxMutationAttempts = 3,
  }) async {
    if (_isRunning) {
      return ImprovementCycleResult(
        improved: false,
        reasoning: 'Cycle already running',
        baselineMetrics: {},
        candidateMetrics: {},
        duration: Duration.zero,
      );
    }

    _isRunning = true;
    final stopwatch = Stopwatch()..start();

    try {
      final currentPrompt = await _registry.getActivePrompt();

      debugPrint('ImprovementLoop: Running baseline evaluation...');
      final baseline = await _evaluateOnGoldenData(goldenInputs, currentPrompt);

      if (baseline.failures.isEmpty) {
        _cycleCount++;
        _lastCycleAt = DateTime.now();
        stopwatch.stop();
        return ImprovementCycleResult(
          improved: false,
          reasoning: 'No failures to address',
          baselineMetrics: {
            'fInsight': baseline.fInsight,
            'dimensions': baseline.dimensionRates,
          },
          candidateMetrics: {},
          duration: stopwatch.elapsed,
        );
      }

      for (var attempt = 0; attempt < maxMutationAttempts; attempt++) {
        debugPrint(
          'ImprovementLoop: Mutation attempt ${attempt + 1}/$maxMutationAttempts',
        );

        final mutation = await _mutator.mutate(
          currentPrompt: currentPrompt,
          failures: baseline.failures,
          dimensions: dimensions,
        );

        final candidate =
            await _evaluateOnGoldenData(goldenInputs, mutation.mutatedPrompt);

        final validation = _validator.validate(
          candidateMetrics: candidate.dimensionRates,
          baselineMetrics: baseline.dimensionRates,
          candidateFInsight: candidate.fInsight,
          baselineFInsight: baseline.fInsight,
        );

        if (validation.accepted) {
          final newVersion = await _registry.saveNewVersion(
            promptText: mutation.mutatedPrompt,
            reason: mutation.reasoning,
            metrics: {
              'fInsight': validation.candidateFInsight,
              ...validation.candidateMetrics,
            },
          );

          _registry.invalidateCache();
          _cycleCount++;
          _improvementCount++;
          _lastCycleAt = DateTime.now();
          stopwatch.stop();

          return ImprovementCycleResult(
            improved: true,
            newVersion: newVersion,
            reasoning: mutation.reasoning,
            baselineMetrics: {
              'fInsight': baseline.fInsight,
              'dimensions': baseline.dimensionRates,
            },
            candidateMetrics: {
              'fInsight': validation.candidateFInsight,
              'dimensions': validation.candidateMetrics,
            },
            validation: validation,
            duration: stopwatch.elapsed,
          );
        }

        debugPrint(
          'ImprovementLoop: Attempt ${attempt + 1} rejected: '
          '${validation.regressions.join("; ")}',
        );
      }

      _cycleCount++;
      _rejectionCount++;
      _lastCycleAt = DateTime.now();
      stopwatch.stop();

      return ImprovementCycleResult(
        improved: false,
        reasoning:
            'All $maxMutationAttempts mutation attempts rejected',
        baselineMetrics: {
          'fInsight': baseline.fInsight,
          'dimensions': baseline.dimensionRates,
        },
        candidateMetrics: {},
        duration: stopwatch.elapsed,
      );
    } catch (e, st) {
      debugPrint('ImprovementLoop: Cycle failed: $e\n$st');
      stopwatch.stop();
      return ImprovementCycleResult(
        improved: false,
        reasoning: 'Cycle failed: $e',
        baselineMetrics: {},
        candidateMetrics: {},
        duration: stopwatch.elapsed,
      );
    } finally {
      _isRunning = false;
    }
  }

  Future<_AggregateEvaluation> _evaluateOnGoldenData(
    List<TInput> inputs,
    String prompt,
  ) async {
    final allFailures = <PromptFailure>[];
    double totalCoverage = 0;
    double totalFocus = 0;
    final allDimensionRates = <String, List<double>>{};

    for (final input in inputs) {
      final outputs = await extractFn(input, prompt);
      final result = await evaluateFn(input, outputs);

      allFailures.addAll(result.failures);
      totalCoverage += result.coverage;
      totalFocus += result.focus;

      for (final entry in result.dimensionRates.entries) {
        allDimensionRates.putIfAbsent(entry.key, () => []).add(entry.value);
      }
    }

    final n = inputs.length;
    final avgCoverage = n > 0 ? totalCoverage / n : 0.0;
    final avgFocus = n > 0 ? totalFocus / n : 0.0;

    final aggregatedRates = allDimensionRates.map(
      (dim, values) =>
          MapEntry(dim, values.fold<double>(0, (a, b) => a + b) / values.length),
    );

    return _AggregateEvaluation(
      failures: allFailures,
      dimensionRates: aggregatedRates,
      fInsight: harmonicMean(avgCoverage, avgFocus),
      coverage: avgCoverage,
      focus: avgFocus,
    );
  }

  // ============ DebugIntrospectable ============

  @override
  String get debugName => 'improvement';

  @override
  Map<String, dynamic> getDebugState() => {
        'cycleCount': _cycleCount,
        'improvementCount': _improvementCount,
        'rejectionCount': _rejectionCount,
        'lastCycleAt': _lastCycleAt?.toIso8601String(),
        'isRunning': _isRunning,
        'activePromptVersion': _registry.activeVersion,
      };

  @override
  Map<String, DebugAction> getDebugActions() => {
        'getStatus': DebugAction(
          description: 'Get improvement loop status',
          handler: (params) async => {
                'cycleCount': _cycleCount,
                'improvementCount': _improvementCount,
                'rejectionCount': _rejectionCount,
                'successRate': _cycleCount > 0
                    ? (_improvementCount / _cycleCount * 100)
                        .toStringAsFixed(1)
                    : 'N/A',
                'lastCycleAt': _lastCycleAt?.toIso8601String(),
                'isRunning': _isRunning,
                'activePromptVersion': _registry.activeVersion,
              },
        ),
      };
}

class _AggregateEvaluation {
  final List<PromptFailure> failures;
  final MetricMap dimensionRates;
  final double fInsight;
  final double coverage;
  final double focus;

  _AggregateEvaluation({
    required this.failures,
    required this.dimensionRates,
    required this.fInsight,
    required this.coverage,
    required this.focus,
  });
}
