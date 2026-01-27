/// # Gaussian Process Optimizer
///
/// Bayesian optimization using Gaussian Process regression.
/// Uses Upper Confidence Bound (UCB) acquisition function for exploration/exploitation.
///
/// **How it works:**
/// 1. Load historical trials from database
/// 2. Fit GP to trial data (params → reward)
/// 3. Generate candidates and score with UCB = mean + 2*std
/// 4. Return best candidate (denormalized)
///
/// **Key features:**
/// - Persists trials to database (survives app restart)
/// - Automatic normalization to [0,1] for GP stability
/// - Handles discrete parameters (rounds to nearest int)
/// - UCB balances exploration (high std) vs exploitation (high mean)

import 'dart:convert';
import 'dart:math';

import 'package:get_it/get_it.dart';

import '../../core/trial.dart';
import '../../core/trial_repository.dart';
import '../../core/math/gp/gaussian_process.dart';
import '../../core/math/gp/kernels.dart';
import 'parameter_optimizer.dart';
import 'types.dart';

class GaussianProcessOptimizer implements ParameterOptimizer {
  @override
  final ParamBounds paramBounds;

  @override
  final String componentType;

  @override
  final String? userId;

  final TrialRepository _trialRepo;
  final GaussianProcess _gp;
  final Random _random;

  /// Number of random candidates to generate for UCB evaluation
  final int numCandidates;

  /// UCB exploration parameter (typically 1.0-3.0)
  /// Higher = more exploration, lower = more exploitation
  final double ucbBeta;

  /// Minimum trials before using GP (use random exploration below this)
  final int minTrialsForGP;

  GaussianProcessOptimizer({
    required this.paramBounds,
    required this.componentType,
    this.userId,
    TrialRepository? trialRepo,
    double lengthScale = 1.0,
    double kernelVariance = 1.0,
    double noiseVariance = 1e-6,
    this.numCandidates = 1000,
    this.ucbBeta = 2.0,
    this.minTrialsForGP = 5,
    Random? random,
  })  : _trialRepo = trialRepo ?? GetIt.I<TrialRepository>(),
        _gp = GaussianProcess(
          kernel: Matern52Kernel(
            lengthScale: lengthScale,
            variance: kernelVariance,
          ),
          noiseVariance: noiseVariance,
        ),
        _random = random ?? Random();

  @override
  Future<void> recordTrial(Map<String, dynamic> params, double reward) async {
    // Normalize params to [0,1]
    final normalized = _normalize(params);

    // Persist to database
    final trial = Trial(
      componentType: componentType,
      paramsJson: jsonEncode(normalized),
      reward: reward,
      userId: userId,
    );

    await _trialRepo.save(trial);
  }

  @override
  Future<Map<String, dynamic>> suggestNext() async {
    // Load historical trials from database
    final trials = await _trialRepo.getRecent(
      componentType: componentType,
      userId: userId,
      limit: 100,
    );

    // Initial random exploration phase
    if (trials.length < minTrialsForGP) {
      return _randomParams();
    }

    // Convert trials to GP format
    final gpTrials = trials.map((t) {
      final params = t.params.values.toList();
      return GPDataPoint(params: params, reward: t.reward);
    }).toList();

    // Fit GP to historical trials
    try {
      _gp.fit(gpTrials);
    } catch (e) {
      throw OptimizerException(
        'Failed to fit GP model',
        cause: e,
      );
    }

    // Generate candidates and find best UCB
    Map<String, double>? bestParams;
    double bestUCB = -double.infinity;

    for (int i = 0; i < numCandidates; i++) {
      final candidate = _randomNormalizedParams();
      final candidateList = candidate.values.toList();

      final (mean, std) = _gp.predict(candidateList);
      final ucb = mean + ucbBeta * std;

      if (ucb > bestUCB) {
        bestUCB = ucb;
        bestParams = candidate;
      }
    }

    if (bestParams == null) {
      throw OptimizerException('Failed to find candidate with valid UCB');
    }

    // Denormalize and return
    return _denormalize(bestParams);
  }

  @override
  Future<int> getTrialCount() async {
    return await _trialRepo.count(
      componentType: componentType,
      userId: userId,
    );
  }

  @override
  Future<void> clearHistory() async {
    await _trialRepo.deleteByComponent(
      componentType: componentType,
      userId: userId,
    );
  }

  // ============ Normalization / Denormalization ============

  /// Normalize parameters to [0, 1] for GP
  Map<String, double> _normalize(Map<String, dynamic> params) {
    return {
      for (var entry in params.entries)
        entry.key: _normalizeParam(entry.key, entry.value)
    };
  }

  double _normalizeParam(String name, dynamic value) {
    final (min, max) = paramBounds[name]!;
    final doubleValue = value is int ? value.toDouble() : value as double;
    return (doubleValue - min) / (max - min);
  }

  /// Denormalize parameters from [0, 1] back to original ranges
  Map<String, dynamic> _denormalize(Map<String, double> normalized) {
    return {
      for (var entry in normalized.entries)
        entry.key: _denormalizeParam(entry.key, entry.value)
    };
  }

  dynamic _denormalizeParam(String name, double normalized) {
    final (min, max) = paramBounds[name]!;
    final value = normalized * (max - min) + min;

    // Round discrete parameters (convention: names ending with Size/Results/Count)
    if (name.endsWith('Size') ||
        name.endsWith('Results') ||
        name.endsWith('Count')) {
      return value.round();
    }

    return value;
  }

  // ============ Random Sampling ============

  /// Generate random parameters (denormalized)
  Map<String, dynamic> _randomParams() {
    final normalized = _randomNormalizedParams();
    return _denormalize(normalized);
  }

  /// Generate random normalized parameters in [0, 1]
  Map<String, double> _randomNormalizedParams() {
    return {for (var name in paramBounds.keys) name: _random.nextDouble()};
  }
}
