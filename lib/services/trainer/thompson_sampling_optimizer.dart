/// ## Why Beta-Bernoulli?
/// - Natural conjugate prior for binary outcomes (good/bad response)
/// - Handles cold start gracefully (uniform prior)
/// - Simple to update: just increment success or failure count
/// - Well-understood convergence properties

import 'dart:math';
import '../types/model_selector_types.dart';

/// Thompson Sampling optimizer for discrete arm selection.
///
/// Uses Beta-Bernoulli model: each arm has independent Beta posterior
/// updated from binary feedback (success/failure).
class ThompsonSamplingOptimizer {
  final Random _random;

  /// Create optimizer with optional random seed (for testing).
  ThompsonSamplingOptimizer({Random? random}) : _random = random ?? Random();

  /// Select arm with highest Thompson sample.
  ///
  /// For each arm, samples from Beta(alpha, beta) posterior.
  /// Returns the arm with the highest sampled value.
  ///
  /// Returns null if armStats is empty.
  String? selectArm(Map<String, ModelStats> armStats) {
    if (armStats.isEmpty) return null;

    String? bestArm;
    double bestSample = -1;
    final sampledScores = <String, double>{};

    for (final entry in armStats.entries) {
      final stats = entry.value;
      final sample = sampleBeta(stats.alpha, stats.beta);
      sampledScores[entry.key] = sample;

      if (sample > bestSample) {
        bestSample = sample;
        bestArm = entry.key;
      }
    }

    return bestArm;
  }

  /// Select arm and return detailed selection result.
  ///
  /// Returns both the selected arm and all sampled scores for debugging.
  ({String arm, Map<String, double> scores})? selectArmWithScores(
    Map<String, ModelStats> armStats,
  ) {
    if (armStats.isEmpty) return null;

    String? bestArm;
    double bestSample = -1;
    final sampledScores = <String, double>{};

    for (final entry in armStats.entries) {
      final stats = entry.value;
      final sample = sampleBeta(stats.alpha, stats.beta);
      sampledScores[entry.key] = sample;

      if (sample > bestSample) {
        bestSample = sample;
        bestArm = entry.key;
      }
    }

    return (arm: bestArm!, scores: sampledScores);
  }

  /// Sample from Beta(alpha, beta) distribution.
  ///
  /// Uses the relationship: Beta(a,b) = X/(X+Y)
  /// where X ~ Gamma(a,1) and Y ~ Gamma(b,1)
  ///
  /// Visible for testing.
  double sampleBeta(double alpha, double beta) {
    if (alpha <= 0 || beta <= 0) {
      throw ArgumentError('Alpha ($alpha) and beta ($beta) must be positive');
    }

    final x = _sampleGamma(alpha);
    final y = _sampleGamma(beta);

    // Handle edge case where both are very small
    if (x + y == 0) return 0.5;

    return x / (x + y);
  }

  /// Sample from Gamma(shape, 1) distribution.
  ///
  /// Uses Marsaglia and Tsang's method for shape >= 1,
  /// with Ahrens-Dieter transformation for shape < 1.
  double _sampleGamma(double shape) {
    if (shape < 1) {
      // For shape < 1, use: Gamma(a) = Gamma(a+1) * U^(1/a)
      // where U ~ Uniform(0,1)
      final u = _random.nextDouble();
      return _sampleGamma(shape + 1) * pow(u, 1 / shape);
    }

    // Marsaglia and Tsang's method for shape >= 1
    final d = shape - 1 / 3;
    final c = 1 / sqrt(9 * d);

    while (true) {
      double x, v;

      do {
        x = _sampleStandardNormal();
        v = 1 + c * x;
      } while (v <= 0);

      v = v * v * v;
      final u = _random.nextDouble();

      // Accept/reject
      if (u < 1 - 0.0331 * (x * x) * (x * x)) {
        return d * v;
      }

      if (log(u) < 0.5 * x * x + d * (1 - v + log(v))) {
        return d * v;
      }
    }
  }

  /// Sample from standard normal distribution using Box-Muller transform.
  double _sampleStandardNormal() {
    final u1 = _random.nextDouble();
    final u2 = _random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// Compute expected regret bound after n trials.
  ///
  /// Thompson Sampling achieves O(sqrt(K * n * log(n))) regret
  /// where K is the number of arms and n is the number of trials.
  ///
  /// This is useful for understanding learning progress.
  static double expectedRegretBound(int numArms, int numTrials) {
    if (numTrials <= 0) return 0;
    return sqrt(numArms * numTrials * log(numTrials + 1));
  }

  /// Compute probability that arm A is better than arm B.
  ///
  /// Uses Monte Carlo estimation with the given number of samples.
  /// Useful for understanding relative arm quality.
  double probabilityABetterThanB(
    ModelStats statsA,
    ModelStats statsB, {
    int samples = 10000,
  }) {
    int aWins = 0;

    for (int i = 0; i < samples; i++) {
      final sampleA = sampleBeta(statsA.alpha, statsA.beta);
      final sampleB = sampleBeta(statsB.alpha, statsB.beta);
      if (sampleA > sampleB) aWins++;
    }

    return aWins / samples;
  }
}
