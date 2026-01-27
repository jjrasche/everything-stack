/// Unit tests for GP kernels
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/math/gp/kernels.dart';
import 'dart:math';

void main() {
  group('Matern52Kernel', () {
    test('identical points have kernel value = variance', () {
      final kernel = Matern52Kernel(lengthScale: 1.0, variance: 2.0);
      final x = [1.0, 2.0, 3.0];

      // At r=0, Matérn 5/2 = σ² (1 + 0 + 0) exp(0) = σ²
      expect(kernel.compute(x, x), closeTo(2.0, 1e-10));
    });

    test('kernel is symmetric', () {
      final kernel = Matern52Kernel();
      final x1 = [1.0, 2.0];
      final x2 = [3.0, 4.0];

      expect(
        kernel.compute(x1, x2),
        closeTo(kernel.compute(x2, x1), 1e-10),
      );
    });

    test('kernel decreases with distance', () {
      final kernel = Matern52Kernel(lengthScale: 1.0);
      final x0 = [0.0, 0.0];

      final k1 = kernel.compute(x0, [0.5, 0.0]); // distance 0.5
      final k2 = kernel.compute(x0, [1.0, 0.0]); // distance 1.0
      final k3 = kernel.compute(x0, [2.0, 0.0]); // distance 2.0

      expect(k1, greaterThan(k2));
      expect(k2, greaterThan(k3));
    });

    test('lengthScale controls decay rate', () {
      final shortScale = Matern52Kernel(lengthScale: 0.5);
      final longScale = Matern52Kernel(lengthScale: 2.0);

      final x1 = [0.0, 0.0];
      final x2 = [1.0, 0.0];

      // Shorter lengthScale → faster decay → smaller kernel value
      expect(
        shortScale.compute(x1, x2),
        lessThan(longScale.compute(x1, x2)),
      );
    });

    test('variance scales output', () {
      final k1 = Matern52Kernel(variance: 1.0);
      final k2 = Matern52Kernel(variance: 2.0);

      final x1 = [0.0, 0.0];
      final x2 = [1.0, 0.0];

      expect(
        k2.compute(x1, x2),
        closeTo(2.0 * k1.compute(x1, x2), 1e-10),
      );
    });

    test('Matérn 5/2 formula verification', () {
      final kernel = Matern52Kernel(lengthScale: 1.0, variance: 1.0);
      final x1 = [0.0, 0.0];
      final x2 = [1.0, 0.0];

      // Distance = 1, r = 1/1 = 1
      // k = 1 * (1 + √5*1 + 5*1²/3) * exp(-√5*1)
      final sqrt5 = sqrt(5.0);
      final expected = (1 + sqrt5 + 5.0 / 3.0) * exp(-sqrt5);

      expect(kernel.compute(x1, x2), closeTo(expected, 1e-10));
    });

    test('computes covariance matrix', () {
      final kernel = Matern52Kernel();
      final points = [
        [0.0, 0.0],
        [1.0, 0.0],
        [0.0, 1.0],
      ];

      final K = kernel.computeMatrix(points);

      // Check dimensions
      expect(K.length, 3);
      expect(K[0].length, 3);

      // Check symmetry
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(K[i][j], closeTo(K[j][i], 1e-10));
        }
      }

      // Check diagonal (self-covariance = variance)
      for (int i = 0; i < 3; i++) {
        expect(K[i][i], closeTo(1.0, 1e-10));
      }
    });

    test('throws on dimension mismatch', () {
      final kernel = Matern52Kernel();
      final x1 = [1.0, 2.0];
      final x2 = [1.0, 2.0, 3.0];

      expect(() => kernel.compute(x1, x2), throwsArgumentError);
    });

    test('throws on invalid lengthScale', () {
      expect(
        () => Matern52Kernel(lengthScale: 0.0),
        throwsArgumentError,
      );
      expect(
        () => Matern52Kernel(lengthScale: -1.0),
        throwsArgumentError,
      );
    });

    test('throws on invalid variance', () {
      expect(
        () => Matern52Kernel(variance: 0.0),
        throwsArgumentError,
      );
      expect(
        () => Matern52Kernel(variance: -1.0),
        throwsArgumentError,
      );
    });
  });

  group('RBFKernel', () {
    test('identical points have kernel value = variance', () {
      final kernel = RBFKernel(lengthScale: 1.0, variance: 2.0);
      final x = [1.0, 2.0, 3.0];

      // At dist=0, RBF = σ² exp(0) = σ²
      expect(kernel.compute(x, x), closeTo(2.0, 1e-10));
    });

    test('kernel is symmetric', () {
      final kernel = RBFKernel();
      final x1 = [1.0, 2.0];
      final x2 = [3.0, 4.0];

      expect(
        kernel.compute(x1, x2),
        closeTo(kernel.compute(x2, x1), 1e-10),
      );
    });

    test('kernel decreases with distance', () {
      final kernel = RBFKernel(lengthScale: 1.0);
      final x0 = [0.0, 0.0];

      final k1 = kernel.compute(x0, [0.5, 0.0]);
      final k2 = kernel.compute(x0, [1.0, 0.0]);
      final k3 = kernel.compute(x0, [2.0, 0.0]);

      expect(k1, greaterThan(k2));
      expect(k2, greaterThan(k3));
    });

    test('RBF formula verification', () {
      final kernel = RBFKernel(lengthScale: 1.0, variance: 1.0);
      final x1 = [0.0, 0.0];
      final x2 = [1.0, 0.0];

      // dist² = 1, RBF = exp(-1 / 2*1²) = exp(-0.5)
      final expected = exp(-0.5);

      expect(kernel.compute(x1, x2), closeTo(expected, 1e-10));
    });

    test('lengthScale controls decay rate', () {
      final shortScale = RBFKernel(lengthScale: 0.5);
      final longScale = RBFKernel(lengthScale: 2.0);

      final x1 = [0.0, 0.0];
      final x2 = [1.0, 0.0];

      // Shorter lengthScale → faster decay
      expect(
        shortScale.compute(x1, x2),
        lessThan(longScale.compute(x1, x2)),
      );
    });

    test('variance scales output', () {
      final k1 = RBFKernel(variance: 1.0);
      final k2 = RBFKernel(variance: 3.0);

      final x1 = [0.0, 0.0];
      final x2 = [1.0, 0.0];

      expect(
        k2.compute(x1, x2),
        closeTo(3.0 * k1.compute(x1, x2), 1e-10),
      );
    });

    test('computes covariance matrix', () {
      final kernel = RBFKernel();
      final points = [
        [0.0],
        [1.0],
        [2.0],
      ];

      final K = kernel.computeMatrix(points);

      // Check symmetry
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(K[i][j], closeTo(K[j][i], 1e-10));
        }
      }

      // Check positive definite (all eigenvalues > 0)
      // For RBF kernel, covariance matrix is always positive definite
      // Spot check: K[0][1] should be exp(-0.5)
      expect(K[0][1], closeTo(exp(-0.5), 1e-10));
    });

    test('throws on dimension mismatch', () {
      final kernel = RBFKernel();
      final x1 = [1.0];
      final x2 = [1.0, 2.0];

      expect(() => kernel.compute(x1, x2), throwsArgumentError);
    });
  });

  group('Kernel comparison', () {
    test('Matérn 5/2 vs RBF at same distance', () {
      final matern = Matern52Kernel(lengthScale: 1.0, variance: 1.0);
      final rbf = RBFKernel(lengthScale: 1.0, variance: 1.0);

      final x1 = [0.0];
      final x2 = [1.0];

      final kMatern = matern.compute(x1, x2);
      final kRBF = rbf.compute(x1, x2);

      // Both should be positive and less than 1
      expect(kMatern, greaterThan(0.0));
      expect(kMatern, lessThan(1.0));
      expect(kRBF, greaterThan(0.0));
      expect(kRBF, lessThan(1.0));

      // RBF decays slower than Matérn 5/2 at moderate distances
      expect(kRBF, greaterThan(kMatern));
    });
  });
}
