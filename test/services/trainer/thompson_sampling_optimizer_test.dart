/// # Thompson Sampling Optimizer Tests
///
/// Unit tests for Thompson Sampling algorithm correctness.
/// Uses seeded random for deterministic tests.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/trainer/thompson_sampling_optimizer.dart';
import 'package:everything_stack_template/services/types/model_selector_types.dart';

void main() {
  group('ThompsonSamplingOptimizer', () {
    group('sampleBeta', () {
      test('returns values in [0, 1] range', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        for (int i = 0; i < 1000; i++) {
          final sample = optimizer.sampleBeta(1.0, 1.0);
          expect(sample, inInclusiveRange(0.0, 1.0),
              reason: 'Beta sample should be in [0, 1]');
        }
      });

      test('throws on non-positive alpha', () {
        final optimizer = ThompsonSamplingOptimizer();

        expect(
          () => optimizer.sampleBeta(0.0, 1.0),
          throwsArgumentError,
          reason: 'Alpha must be positive',
        );
        expect(
          () => optimizer.sampleBeta(-1.0, 1.0),
          throwsArgumentError,
          reason: 'Alpha must be positive',
        );
      });

      test('throws on non-positive beta', () {
        final optimizer = ThompsonSamplingOptimizer();

        expect(
          () => optimizer.sampleBeta(1.0, 0.0),
          throwsArgumentError,
          reason: 'Beta must be positive',
        );
        expect(
          () => optimizer.sampleBeta(1.0, -1.0),
          throwsArgumentError,
          reason: 'Beta must be positive',
        );
      });

      test('Beta(1,1) gives uniform distribution (mean ~0.5)', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));
        double sum = 0;
        const n = 10000;

        for (int i = 0; i < n; i++) {
          sum += optimizer.sampleBeta(1.0, 1.0);
        }

        final mean = sum / n;
        expect(mean, closeTo(0.5, 0.05),
            reason: 'Beta(1,1) should have mean ~0.5');
      });

      test('Beta(10,2) gives high mean (~0.83)', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));
        double sum = 0;
        const n = 10000;

        for (int i = 0; i < n; i++) {
          sum += optimizer.sampleBeta(10.0, 2.0);
        }

        final mean = sum / n;
        // Expected mean = alpha / (alpha + beta) = 10/12 ≈ 0.833
        expect(mean, closeTo(0.833, 0.05),
            reason: 'Beta(10,2) should have mean ~0.833');
      });

      test('Beta(2,10) gives low mean (~0.17)', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));
        double sum = 0;
        const n = 10000;

        for (int i = 0; i < n; i++) {
          sum += optimizer.sampleBeta(2.0, 10.0);
        }

        final mean = sum / n;
        // Expected mean = alpha / (alpha + beta) = 2/12 ≈ 0.167
        expect(mean, closeTo(0.167, 0.05),
            reason: 'Beta(2,10) should have mean ~0.167');
      });

      test('handles shape < 1 (Ahrens-Dieter case)', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        // Beta(0.5, 0.5) is the Jeffreys prior
        for (int i = 0; i < 100; i++) {
          final sample = optimizer.sampleBeta(0.5, 0.5);
          expect(sample, inInclusiveRange(0.0, 1.0),
              reason: 'Beta with small shape should still be in [0, 1]');
        }
      });
    });

    group('selectArm', () {
      test('returns null for empty stats', () {
        final optimizer = ThompsonSamplingOptimizer();

        final result = optimizer.selectArm({});

        expect(result, isNull, reason: 'Empty stats should return null');
      });

      test('returns the only arm when single arm', () {
        final optimizer = ThompsonSamplingOptimizer();

        final result = optimizer.selectArm({
          'model_a': ModelStats.empty(),
        });

        expect(result, equals('model_a'),
            reason: 'Single arm should always be selected');
      });

      test('deterministic with seeded random', () {
        final optimizer1 = ThompsonSamplingOptimizer(random: Random(123));
        final optimizer2 = ThompsonSamplingOptimizer(random: Random(123));

        final stats = {
          'model_a': ModelStats(successes: 5, failures: 5),
          'model_b': ModelStats(successes: 5, failures: 5),
        };

        final result1 = optimizer1.selectArm(stats);
        final result2 = optimizer2.selectArm(stats);

        expect(result1, equals(result2),
            reason: 'Same seed should give same selection');
      });

      test('tends to select arm with higher success rate over many trials', () {
        // Run many selections and verify the better arm wins more often
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final stats = {
          'good_model': ModelStats(successes: 80, failures: 20), // 80% rate
          'bad_model': ModelStats(successes: 20, failures: 80), // 20% rate
        };

        int goodWins = 0;
        const trials = 1000;

        for (int i = 0; i < trials; i++) {
          // Need fresh optimizer each time or results accumulate
          final result =
              ThompsonSamplingOptimizer(random: Random(42 + i)).selectArm(stats);
          if (result == 'good_model') goodWins++;
        }

        // Good model should win significantly more often
        expect(goodWins, greaterThan(trials * 0.9),
            reason: 'Better arm should be selected >90% of time with strong signal');
      });

      test('explores uncertain arms (cold start)', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        // One proven arm, one uncertain
        final stats = {
          'proven': ModelStats(successes: 50, failures: 50), // 50% certain
          'uncertain': ModelStats.empty(), // No data = explore
        };

        int uncertainSelected = 0;
        const trials = 100;

        for (int i = 0; i < trials; i++) {
          final result =
              ThompsonSamplingOptimizer(random: Random(42 + i)).selectArm(stats);
          if (result == 'uncertain') uncertainSelected++;
        }

        // Uncertain arm should get reasonable exploration (>20% of trials)
        expect(uncertainSelected, greaterThan(20),
            reason: 'Thompson Sampling should explore uncertain arms');
      });
    });

    group('selectArmWithScores', () {
      test('returns null for empty stats', () {
        final optimizer = ThompsonSamplingOptimizer();

        final result = optimizer.selectArmWithScores({});

        expect(result, isNull, reason: 'Empty stats should return null');
      });

      test('returns scores for all arms', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final stats = {
          'model_a': ModelStats(successes: 5, failures: 5),
          'model_b': ModelStats(successes: 3, failures: 7),
          'model_c': ModelStats(successes: 8, failures: 2),
        };

        final result = optimizer.selectArmWithScores(stats);

        expect(result, isNotNull);
        expect(result!.scores.keys, containsAll(['model_a', 'model_b', 'model_c']),
            reason: 'Scores should include all arms');
        expect(result.scores.length, equals(3),
            reason: 'Scores should have exactly 3 entries');
      });

      test('scores are in [0, 1] range', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final stats = {
          'model_a': ModelStats(successes: 5, failures: 5),
          'model_b': ModelStats(successes: 3, failures: 7),
        };

        final result = optimizer.selectArmWithScores(stats);

        for (final score in result!.scores.values) {
          expect(score, inInclusiveRange(0.0, 1.0),
              reason: 'Sampled scores should be in [0, 1]');
        }
      });

      test('selected arm has highest score', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final stats = {
          'model_a': ModelStats(successes: 5, failures: 5),
          'model_b': ModelStats(successes: 3, failures: 7),
          'model_c': ModelStats(successes: 8, failures: 2),
        };

        final result = optimizer.selectArmWithScores(stats);
        final selectedScore = result!.scores[result.arm]!;

        for (final entry in result.scores.entries) {
          expect(selectedScore, greaterThanOrEqualTo(entry.value),
              reason: 'Selected arm should have highest sampled score');
        }
      });
    });

    group('probabilityABetterThanB', () {
      test('returns ~1.0 when A is clearly better', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final statsA = ModelStats(successes: 90, failures: 10);
        final statsB = ModelStats(successes: 10, failures: 90);

        final prob = optimizer.probabilityABetterThanB(statsA, statsB);

        expect(prob, greaterThan(0.99),
            reason: 'A (90%) should almost always beat B (10%)');
      });

      test('returns ~0.0 when B is clearly better', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final statsA = ModelStats(successes: 10, failures: 90);
        final statsB = ModelStats(successes: 90, failures: 10);

        final prob = optimizer.probabilityABetterThanB(statsA, statsB);

        expect(prob, lessThan(0.01),
            reason: 'A (10%) should almost never beat B (90%)');
      });

      test('returns ~0.5 when arms are equal', () {
        final optimizer = ThompsonSamplingOptimizer(random: Random(42));

        final statsA = ModelStats(successes: 50, failures: 50);
        final statsB = ModelStats(successes: 50, failures: 50);

        final prob = optimizer.probabilityABetterThanB(statsA, statsB);

        expect(prob, closeTo(0.5, 0.05),
            reason: 'Equal arms should have ~50% probability');
      });
    });

    group('expectedRegretBound', () {
      test('returns 0 for 0 trials', () {
        expect(ThompsonSamplingOptimizer.expectedRegretBound(3, 0), equals(0));
      });

      test('increases with number of arms', () {
        final regret2Arms = ThompsonSamplingOptimizer.expectedRegretBound(2, 100);
        final regret5Arms = ThompsonSamplingOptimizer.expectedRegretBound(5, 100);

        expect(regret5Arms, greaterThan(regret2Arms),
            reason: 'More arms should have higher regret bound');
      });

      test('increases sublinearly with trials (sqrt growth)', () {
        final regret100 = ThompsonSamplingOptimizer.expectedRegretBound(3, 100);
        final regret400 = ThompsonSamplingOptimizer.expectedRegretBound(3, 400);

        // sqrt(4) = 2, so regret should roughly double
        expect(regret400 / regret100, closeTo(2.0, 0.5),
            reason: 'Regret should grow as sqrt(n)');
      });
    });
  });

  group('ModelStats', () {
    test('empty has 0 successes and 0 failures', () {
      final stats = ModelStats.empty();

      expect(stats.successes, equals(0));
      expect(stats.failures, equals(0));
      expect(stats.trials, equals(0));
    });

    test('alpha = successes + 1 (Beta prior)', () {
      final stats = ModelStats(successes: 10, failures: 5);

      expect(stats.alpha, equals(11.0),
          reason: 'Alpha should be successes + 1 for Beta prior');
    });

    test('beta = failures + 1 (Beta prior)', () {
      final stats = ModelStats(successes: 10, failures: 5);

      expect(stats.beta, equals(6.0),
          reason: 'Beta should be failures + 1 for Beta prior');
    });

    test('expectedRate = alpha / (alpha + beta)', () {
      final stats = ModelStats(successes: 10, failures: 5);

      // Expected = 11 / (11 + 6) = 11/17 ≈ 0.647
      expect(stats.expectedRate, closeTo(11.0 / 17.0, 0.001));
    });

    test('trials = successes + failures', () {
      final stats = ModelStats(successes: 10, failures: 5);

      expect(stats.trials, equals(15));
    });

    test('addSuccess increments successes', () {
      final stats = ModelStats(successes: 5, failures: 3);
      final updated = stats.addSuccess();

      expect(updated.successes, equals(6));
      expect(updated.failures, equals(3));
    });

    test('addFailure increments failures', () {
      final stats = ModelStats(successes: 5, failures: 3);
      final updated = stats.addFailure();

      expect(updated.successes, equals(5));
      expect(updated.failures, equals(4));
    });

    test('empty stats expectedRate is 0.5 (uniform prior)', () {
      final stats = ModelStats.empty();

      // With alpha=1, beta=1: expected = 1/(1+1) = 0.5
      expect(stats.expectedRate, equals(0.5),
          reason: 'Empty stats should give uniform (50%) expected rate');
    });
  });
}
