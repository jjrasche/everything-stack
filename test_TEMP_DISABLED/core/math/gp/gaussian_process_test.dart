/// Unit tests for Gaussian Process regression
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/math/gp/gaussian_process.dart';
import 'package:everything_stack_template/core/math/gp/kernels.dart';
import 'dart:math';

void main() {
  group('GPDataPoint', () {
    test('creates data point', () {
      final point = GPDataPoint(params: [0.5, 0.3], reward: 0.8);
      expect(point.params, [0.5, 0.3]);
      expect(point.reward, 0.8);
    });
  });

  group('GaussianProcess - Basic Operations', () {
    test('creates GP with default noise', () {
      final gp = GaussianProcess(kernel: Matern52Kernel());
      expect(gp.noiseVariance, 1e-6);
      expect(gp.isFitted, false);
      expect(gp.dataSize, 0);
    });

    test('creates GP with custom noise', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(),
        noiseVariance: 1e-3,
      );
      expect(gp.noiseVariance, 1e-3);
    });

    test('throws on invalid noise variance', () {
      expect(
        () => GaussianProcess(
          kernel: Matern52Kernel(),
          noiseVariance: 0.0,
        ),
        throwsArgumentError,
      );
    });

    test('throws when predict() called before fit()', () {
      final gp = GaussianProcess(kernel: Matern52Kernel());

      expect(
        () => gp.predict([0.5]),
        throwsA(isA<GPException>()),
      );
    });

    test('throws when fitting with empty data', () {
      final gp = GaussianProcess(kernel: Matern52Kernel());

      expect(
        () => gp.fit([]),
        throwsA(isA<GPException>()),
      );
    });
  });

  group('GaussianProcess - Interpolation', () {
    test('interpolates single training point', () {
      final gp = GaussianProcess(kernel: Matern52Kernel());

      final data = [
        GPDataPoint(params: [0.5], reward: 1.0),
      ];
      gp.fit(data);

      expect(gp.isFitted, true);
      expect(gp.dataSize, 1);

      // Predict at training point (should match reward)
      final (mean, std) = gp.predict([0.5]);
      expect(mean, closeTo(1.0, 1e-3));

      // Predict at distant point (should have high uncertainty)
      final (meanFar, stdFar) = gp.predict([5.0]);
      expect(stdFar, greaterThan(0.5));
    });

    test('interpolates linear function', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(lengthScale: 1.0),
        noiseVariance: 1e-6,
      );

      // Linear function: f(x) = 2x
      final data = [
        GPDataPoint(params: [0.0], reward: 0.0),
        GPDataPoint(params: [1.0], reward: 2.0),
        GPDataPoint(params: [2.0], reward: 4.0),
      ];
      gp.fit(data);

      // Predict at training points (should interpolate exactly)
      final (mean0, _) = gp.predict([0.0]);
      final (mean1, _) = gp.predict([1.0]);
      final (mean2, _) = gp.predict([2.0]);

      expect(mean0, closeTo(0.0, 1e-2));
      expect(mean1, closeTo(2.0, 1e-2));
      expect(mean2, closeTo(4.0, 1e-2));

      // Predict at interpolation point
      final (mean15, std15) = gp.predict([1.5]);
      expect(mean15, closeTo(3.0, 0.5)); // Approximately linear
      expect(std15, lessThan(0.5)); // Low uncertainty (near training data)
    });

    test('interpolates quadratic function', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(lengthScale: 0.5),
        noiseVariance: 1e-6,
      );

      // Quadratic: f(x) = x²
      final data = [
        GPDataPoint(params: [0.0], reward: 0.0),
        GPDataPoint(params: [1.0], reward: 1.0),
        GPDataPoint(params: [2.0], reward: 4.0),
        GPDataPoint(params: [3.0], reward: 9.0),
      ];
      gp.fit(data);

      // Predict at interpolation point
      final (mean, _) = gp.predict([1.5]);
      expect(mean, closeTo(2.25, 1.0)); // f(1.5) = 2.25
    });
  });

  group('GaussianProcess - Multi-dimensional', () {
    test('fits 2D data', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(lengthScale: 1.0),
      );

      final data = [
        GPDataPoint(params: [0.0, 0.0], reward: 0.0),
        GPDataPoint(params: [1.0, 0.0], reward: 1.0),
        GPDataPoint(params: [0.0, 1.0], reward: 1.0),
        GPDataPoint(params: [1.0, 1.0], reward: 2.0),
      ];
      gp.fit(data);

      // Predict at center
      final (mean, std) = gp.predict([0.5, 0.5]);
      expect(mean, closeTo(1.0, 0.5)); // Sum of coordinates
      expect(std, greaterThan(0.0));
    });

    test('fits 3D data', () {
      final gp = GaussianProcess(kernel: Matern52Kernel());

      final data = [
        GPDataPoint(params: [0.0, 0.0, 0.0], reward: 0.0),
        GPDataPoint(params: [1.0, 1.0, 1.0], reward: 3.0),
      ];
      gp.fit(data);

      final (mean, _) = gp.predict([0.5, 0.5, 0.5]);
      expect(mean, greaterThan(0.0));
      expect(mean, lessThan(3.0));
    });
  });

  group('GaussianProcess - Uncertainty', () {
    test('uncertainty is zero at training points', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(),
        noiseVariance: 1e-10, // Very small noise
      );

      final data = [
        GPDataPoint(params: [0.0], reward: 1.0),
        GPDataPoint(params: [1.0], reward: 2.0),
      ];
      gp.fit(data);

      final (_, std0) = gp.predict([0.0]);
      final (_, std1) = gp.predict([1.0]);

      expect(std0, closeTo(0.0, 1e-3));
      expect(std1, closeTo(0.0, 1e-3));
    });

    test('uncertainty increases far from data', () {
      final gp = GaussianProcess(kernel: Matern52Kernel(lengthScale: 1.0));

      final data = [
        GPDataPoint(params: [0.0], reward: 1.0),
      ];
      gp.fit(data);

      final (_, stdNear) = gp.predict([0.1]);
      final (_, stdMid) = gp.predict([1.0]);
      final (_, stdFar) = gp.predict([5.0]);

      expect(stdNear, lessThan(stdMid));
      expect(stdMid, lessThan(stdFar));
    });

    test('uncertainty decreases with more data', () {
      final kernel = Matern52Kernel(lengthScale: 1.0);

      // GP with 2 points
      final gp2 = GaussianProcess(kernel: kernel);
      gp2.fit([
        GPDataPoint(params: [0.0], reward: 0.0),
        GPDataPoint(params: [2.0], reward: 2.0),
      ]);
      final (_, std2) = gp2.predict([1.0]);

      // GP with 5 points
      final gp5 = GaussianProcess(kernel: kernel);
      gp5.fit([
        GPDataPoint(params: [0.0], reward: 0.0),
        GPDataPoint(params: [0.5], reward: 0.5),
        GPDataPoint(params: [1.0], reward: 1.0),
        GPDataPoint(params: [1.5], reward: 1.5),
        GPDataPoint(params: [2.0], reward: 2.0),
      ]);
      final (_, std5) = gp5.predict([1.0]);

      expect(std5, lessThan(std2));
    });
  });

  group('GaussianProcess - Error Handling', () {
    test('retries on singular matrix', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(lengthScale: 1.0),
        noiseVariance: 1e-10, // Very small noise
      );

      // Nearly identical points (should be singular without retry)
      final data = [
        GPDataPoint(params: [0.0], reward: 1.0),
        GPDataPoint(params: [1e-9], reward: 1.1), // Very close to first
        GPDataPoint(params: [1.0], reward: 2.0),
      ];

      // Should succeed due to automatic noise increase
      expect(() => gp.fit(data), returnsNormally);
      expect(gp.isFitted, true);
    });

    test('throws after max retries on pathological data', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(lengthScale: 1e-20), // Pathological
        noiseVariance: 1e-20,
      );

      final data = [
        GPDataPoint(params: [0.0], reward: 1.0),
        GPDataPoint(params: [0.0], reward: 2.0), // Duplicate params
      ];

      expect(
        () => gp.fit(data),
        throwsA(isA<GPException>()),
      );
    });
  });

  group('GaussianProcess - Performance', () {
    test('fits 100 data points', () {
      final gp = GaussianProcess(kernel: Matern52Kernel());

      // Generate 100 random points
      final random = Random(42);
      final data = List.generate(
        100,
        (i) => GPDataPoint(
          params: [random.nextDouble()],
          reward: random.nextDouble(),
        ),
      );

      final stopwatch = Stopwatch()..start();
      gp.fit(data);
      stopwatch.stop();

      print('GP fit 100 points: ${stopwatch.elapsedMilliseconds}ms');

      // Should be fast enough (~50-200ms with pure Dart)
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(gp.isFitted, true);

      // Prediction should be instant
      final predStopwatch = Stopwatch()..start();
      gp.predict([0.5]);
      predStopwatch.stop();

      expect(predStopwatch.elapsedMilliseconds, lessThan(10));
    });
  });

  group('GaussianProcess - Optimization Use Case', () {
    test('finds optimum of simple function', () {
      final gp = GaussianProcess(
        kernel: Matern52Kernel(lengthScale: 0.3),
      );

      // Simulate optimization of f(x) = -(x - 0.7)²
      // Optimum at x = 0.7
      double f(double x) => -(x - 0.7) * (x - 0.7);

      // Initial random samples
      final data = [
        GPDataPoint(params: [0.1], reward: f(0.1)),
        GPDataPoint(params: [0.5], reward: f(0.5)),
        GPDataPoint(params: [0.9], reward: f(0.9)),
      ];
      gp.fit(data);

      // Find point with highest UCB (mean + 2*std)
      double bestUCB = -double.infinity;
      double bestX = 0.0;

      for (double x = 0.0; x <= 1.0; x += 0.01) {
        final (mean, std) = gp.predict([x]);
        final ucb = mean + 2.0 * std;

        if (ucb > bestUCB) {
          bestUCB = ucb;
          bestX = x;
        }
      }

      // GP should suggest exploring near optimum (0.7)
      expect(bestX, closeTo(0.7, 0.3));
    });
  });
}
