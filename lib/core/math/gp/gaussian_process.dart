/// Gaussian Process regression for Bayesian optimization.
///
/// GP learns a distribution over functions from observed data points.
/// Used for parameter optimization: predicts reward mean and uncertainty.
library;

import 'dart:math';
import '../../../math/linalg/matrix.dart';
import '../../../math/linalg/matrix_ops.dart';
import 'kernels.dart';

/// Exception thrown when GP operations fail
class GPException implements Exception {
  final String message;
  GPException(this.message);

  @override
  String toString() => 'GPException: $message';
}

/// Training data point for GP
class GPDataPoint {
  final List<double> params;
  final double reward;

  GPDataPoint({
    required this.params,
    required this.reward,
  });

  @override
  String toString() => 'GPDataPoint(params: $params, reward: $reward)';
}

/// Gaussian Process regressor with automatic error handling.
///
/// Learns function f: params → reward from observed data points.
/// Provides mean prediction and uncertainty estimate for new points.
///
/// Example:
/// ```dart
/// final gp = GaussianProcess(
///   kernel: Matern52Kernel(lengthScale: 1.0),
///   noiseVariance: 1e-6,
/// );
///
/// // Train on historical trials
/// final data = [
///   GPDataPoint(params: [0.5, 0.3], reward: 0.8),
///   GPDataPoint(params: [0.7, 0.2], reward: 0.9),
/// ];
/// gp.fit(data);
///
/// // Predict reward for new params
/// final (mean, std) = gp.predict([0.6, 0.25]);
/// print('Predicted reward: $mean ± $std');
/// ```
class GaussianProcess {
  final Kernel kernel;
  double noiseVariance;
  final MatrixOps _matrixOps;

  // Cached values from last fit()
  List<GPDataPoint>? _data;
  Matrix? _L; // Cholesky decomposition of K + noise*I
  Vector? _alpha; // Precomputed weights for prediction

  /// Create Gaussian Process regressor
  ///
  /// [kernel]: Covariance function (Matern52Kernel recommended)
  /// [noiseVariance]: Observation noise level (default: 1e-6)
  GaussianProcess({
    required this.kernel,
    this.noiseVariance = 1e-6,
    MatrixOps? matrixOps,
  }) : _matrixOps = matrixOps ?? getMatrixOps() {
    if (noiseVariance <= 0) {
      throw ArgumentError('noiseVariance must be positive, got $noiseVariance');
    }
  }

  /// Train GP on observed data points.
  ///
  /// Computes Cholesky decomposition and weights for prediction.
  /// Automatically retries with increased noise if matrix is singular.
  ///
  /// Throws [GPException] if fitting fails after retries.
  void fit(List<GPDataPoint> data) {
    if (data.isEmpty) {
      throw GPException('Cannot fit GP with empty data');
    }

    _data = data;
    final n = data.length;

    final points = data.map((d) => d.params).toList();
    final K = kernel.computeMatrix(points);

    // Try Cholesky decomposition with increasing noise
    int attempts = 0;
    const maxAttempts = 3;
    double currentNoise = noiseVariance;

    while (attempts < maxAttempts) {
      try {
        for (int i = 0; i < n; i++) {
          K[i][i] += currentNoise;
        }

        // Cholesky decomposition: K = L * L^T
        _L = _matrixOps.cholesky(K, epsilon: 0.0);

        // Success - compute alpha weights
        break;
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          throw GPException(
            'Failed to fit GP after $maxAttempts attempts. '
            'Matrix is too ill-conditioned. '
            'Try: (1) normalize parameters, (2) increase noiseVariance, '
            '(3) use fewer data points.',
          );
        }

        currentNoise *= 10;

        for (int i = 0; i < n; i++) {
          K[i][i] -= currentNoise / 10;
        }
      }
    }

    // Solve for alpha: alpha = (K + noise*I)^{-1} * y
    // L * L^T * alpha = y
    // Step 1: L * m = y (forward substitution)
    // Step 2: L^T * alpha = m (backward substitution)

    final y = data.map((d) => d.reward).toList();
    final m = _matrixOps.forwardSubstitution(_L!, y);
    final Lt = transpose(_L!);
    _alpha = _matrixOps.backwardSubstitution(Lt, m);
  }

  /// Predict reward mean and standard deviation for new parameters.
  ///
  /// Returns (mean, std) tuple:
  /// - mean: Expected reward
  /// - std: Uncertainty (standard deviation)
  ///
  /// Higher std means more exploration potential (less data in this region).
  ///
  /// Throws [GPException] if predict() called before fit().
  (double, double) predict(List<double> params) {
    if (_data == null || _L == null || _alpha == null) {
      throw GPException('Must call fit() before predict()');
    }

    final kStar = _data!.map((d) => kernel.compute(params, d.params)).toList();

    // Predictive mean: mean = k*^T * alpha
    double mean = 0.0;
    for (int i = 0; i < kStar.length; i++) {
      mean += kStar[i] * _alpha![i];
    }

    // Predictive variance: var = k(x*, x*) - k*^T * (K + noise*I)^{-1} * k*
    // Solve L * v = k* for v
    final v = _matrixOps.forwardSubstitution(_L!, kStar);

    // v^T * v = k*^T * (K + noise*I)^{-1} * k*
    double vNormSquared = 0.0;
    for (final val in v) {
      vNormSquared += val * val;
    }

    // Prior variance - data variance
    final kStarStar = kernel.compute(params, params);
    final variance = kStarStar - vNormSquared;

    // Clamp variance to non-negative (numerical errors can make it slightly negative)
    final clampedVariance = max(variance, 0.0);

    return (mean, sqrt(clampedVariance));
  }

  /// Check if GP has been trained
  bool get isFitted => _data != null && _L != null && _alpha != null;

  /// Number of training data points
  int get dataSize => _data?.length ?? 0;

  @override
  String toString() => 'GaussianProcess(kernel: $kernel, '
      'noiseVariance: $noiseVariance, '
      'fitted: $isFitted, '
      'dataSize: $dataSize)';
}
