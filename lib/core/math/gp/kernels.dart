/// Gaussian Process kernel functions.
///
/// Kernels define similarity between points in parameter space.
/// Used by GP regression to predict function values and uncertainty.
library;

import 'dart:math';

/// Base class for GP kernels (covariance functions)
abstract class Kernel {
  /// Compute kernel value between two points
  double compute(List<double> x1, List<double> x2);

  /// Compute covariance matrix for a set of points
  ///
  /// Returns n×n matrix where K[i][j] = compute(points[i], points[j])
  List<List<double>> computeMatrix(List<List<double>> points) {
    final n = points.length;
    final K = List.generate(n, (_) => List<double>.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        K[i][j] = compute(points[i], points[j]);
      }
    }

    return K;
  }
}

/// Matérn 5/2 kernel (twice differentiable, smooth).
///
/// Formula: k(x1, x2) = σ² (1 + √5r + 5r²/3) exp(-√5r)
/// where r = ||x1 - x2|| / ℓ
///
/// Properties:
/// - Smooth (C² continuous)
/// - Good default for GP regression
/// - More flexible than RBF for learning smooth functions
///
/// Parameters:
/// - lengthScale (ℓ): Controls how quickly correlation decays with distance
/// - variance (σ²): Controls output scale
class Matern52Kernel extends Kernel {
  final double lengthScale;
  final double variance;

  /// Create Matérn 5/2 kernel
  ///
  /// [lengthScale]: Typical distance between correlated points (default: 1.0)
  /// [variance]: Output scale factor (default: 1.0)
  Matern52Kernel({
    this.lengthScale = 1.0,
    this.variance = 1.0,
  }) {
    if (lengthScale <= 0) {
      throw ArgumentError('lengthScale must be positive, got $lengthScale');
    }
    if (variance <= 0) {
      throw ArgumentError('variance must be positive, got $variance');
    }
  }

  @override
  double compute(List<double> x1, List<double> x2) {
    if (x1.length != x2.length) {
      throw ArgumentError(
        'Dimension mismatch: x1 has ${x1.length}, x2 has ${x2.length}',
      );
    }

    double distSquared = 0.0;
    for (int i = 0; i < x1.length; i++) {
      final diff = x1[i] - x2[i];
      distSquared += diff * diff;
    }
    final dist = sqrt(distSquared);

    // Scaled distance: r = dist / lengthScale
    final r = dist / lengthScale;

    // Matérn 5/2 formula: σ² (1 + √5r + 5r²/3) exp(-√5r)
    final sqrt5r = sqrt(5.0) * r;
    final term1 = 1.0 + sqrt5r + (5.0 * r * r / 3.0);
    final term2 = exp(-sqrt5r);

    return variance * term1 * term2;
  }

  @override
  String toString() =>
      'Matern52Kernel(lengthScale: $lengthScale, variance: $variance)';
}

/// Radial Basis Function (RBF) / Squared Exponential kernel.
///
/// Formula: k(x1, x2) = σ² exp(-||x1 - x2||² / 2ℓ²)
///
/// Properties:
/// - Infinitely differentiable (very smooth)
/// - Can overfit if data is noisy
/// - Classic choice for GP regression
///
/// Parameters:
/// - lengthScale (ℓ): Controls decay rate
/// - variance (σ²): Output scale
class RBFKernel extends Kernel {
  final double lengthScale;
  final double variance;

  /// Create RBF kernel
  ///
  /// [lengthScale]: Typical distance between correlated points (default: 1.0)
  /// [variance]: Output scale factor (default: 1.0)
  RBFKernel({
    this.lengthScale = 1.0,
    this.variance = 1.0,
  }) {
    if (lengthScale <= 0) {
      throw ArgumentError('lengthScale must be positive, got $lengthScale');
    }
    if (variance <= 0) {
      throw ArgumentError('variance must be positive, got $variance');
    }
  }

  @override
  double compute(List<double> x1, List<double> x2) {
    if (x1.length != x2.length) {
      throw ArgumentError(
        'Dimension mismatch: x1 has ${x1.length}, x2 has ${x2.length}',
      );
    }

    double distSquared = 0.0;
    for (int i = 0; i < x1.length; i++) {
      final diff = x1[i] - x2[i];
      distSquared += diff * diff;
    }

    // RBF formula: σ² exp(-dist² / 2ℓ²)
    final exponent = -distSquared / (2.0 * lengthScale * lengthScale);
    return variance * exp(exponent);
  }

  @override
  String toString() =>
      'RBFKernel(lengthScale: $lengthScale, variance: $variance)';
}
