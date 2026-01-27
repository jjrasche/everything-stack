import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/nerve/channel/retry_policy.dart';

void main() {
  group('RetryPolicy', () {
    group('shouldRetry', () {
      test('returns true for attempts less than maxAttempts', () {
        final policy = RetryPolicy(maxAttempts: 3);

        expect(policy.shouldRetry(0), isTrue);
        expect(policy.shouldRetry(1), isTrue);
        expect(policy.shouldRetry(2), isTrue);
      });

      test('returns false when attempts exhausted', () {
        final policy = RetryPolicy(maxAttempts: 3);

        expect(policy.shouldRetry(3), isFalse);
        expect(policy.shouldRetry(4), isFalse);
      });

      test('returns false for RetryPolicy.none', () {
        expect(RetryPolicy.none.shouldRetry(0), isFalse);
      });
    });

    group('delayForAttempt', () {
      test('returns initialDelay for attempt 0', () {
        final policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          useJitter: false,
        );

        expect(policy.delayForAttempt(0), Duration(seconds: 1));
      });

      test('applies exponential backoff', () {
        final policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          useJitter: false,
        );

        expect(policy.delayForAttempt(0), Duration(seconds: 1));
        expect(policy.delayForAttempt(1), Duration(seconds: 2));
        expect(policy.delayForAttempt(2), Duration(seconds: 4));
        expect(policy.delayForAttempt(3), Duration(seconds: 8));
      });

      test('caps at maxDelay', () {
        final policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          maxDelay: Duration(seconds: 5),
          useJitter: false,
        );

        expect(policy.delayForAttempt(0), Duration(seconds: 1));
        expect(policy.delayForAttempt(1), Duration(seconds: 2));
        expect(policy.delayForAttempt(2), Duration(seconds: 4));
        expect(policy.delayForAttempt(3), Duration(seconds: 5)); // Capped
        expect(
            policy.delayForAttempt(10), Duration(seconds: 5)); // Still capped
      });

      test('returns zero for negative attempts', () {
        final policy = RetryPolicy(useJitter: false);

        expect(policy.delayForAttempt(-1), Duration.zero);
        expect(policy.delayForAttempt(-100), Duration.zero);
      });

      test('adds jitter when enabled', () {
        final policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          useJitter: true,
          jitterFactor: 0.5,
        );

        // With jitter, delays should be in range [base, base * 1.5]
        final delays = List.generate(100, (_) => policy.delayForAttempt(0));
        final baseMs = 1000;
        final maxMs = 1500;

        for (final delay in delays) {
          expect(delay.inMilliseconds, greaterThanOrEqualTo(baseMs));
          expect(delay.inMilliseconds, lessThanOrEqualTo(maxMs));
        }

        // Not all delays should be exactly the same (jitter is random)
        final uniqueDelays = delays.toSet();
        expect(uniqueDelays.length, greaterThan(1));
      });

      test('uses provided random for reproducible tests', () {
        final policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          useJitter: true,
          jitterFactor: 0.25,
        );

        final random1 = Random(42);
        final random2 = Random(42);

        final delay1 = policy.delayForAttempt(0, random: random1);
        final delay2 = policy.delayForAttempt(0, random: random2);

        expect(delay1, delay2);
      });

      test('no jitter when jitterFactor is 0', () {
        final policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          useJitter: true,
          jitterFactor: 0.0,
        );

        final delays = List.generate(10, (_) => policy.delayForAttempt(0));
        expect(delays.toSet().length, 1); // All same
      });
    });

    group('predefined policies', () {
      test('none has maxAttempts 0', () {
        expect(RetryPolicy.none.maxAttempts, 0);
        expect(RetryPolicy.none.shouldRetry(0), isFalse);
      });

      test('defaultPolicy has reasonable defaults', () {
        expect(RetryPolicy.defaultPolicy.maxAttempts, 5);
        expect(RetryPolicy.defaultPolicy.initialDelay, Duration(seconds: 1));
        expect(RetryPolicy.defaultPolicy.backoffMultiplier, 2.0);
        expect(RetryPolicy.defaultPolicy.maxDelay, Duration(seconds: 30));
      });

      test('aggressive has more retries', () {
        expect(RetryPolicy.aggressive.maxAttempts, 10);
        expect(
            RetryPolicy.aggressive.initialDelay, Duration(milliseconds: 500));
      });
    });

    group('copyWith', () {
      test('creates copy with modified fields', () {
        final original = RetryPolicy.defaultPolicy;
        final modified = original.copyWith(maxAttempts: 10);

        expect(modified.maxAttempts, 10);
        expect(modified.initialDelay, original.initialDelay);
        expect(modified.backoffMultiplier, original.backoffMultiplier);
      });

      test('preserves original when no changes', () {
        final original = RetryPolicy(maxAttempts: 3);
        final copy = original.copyWith();

        expect(copy.maxAttempts, original.maxAttempts);
        expect(copy.initialDelay, original.initialDelay);
        expect(copy.backoffMultiplier, original.backoffMultiplier);
        expect(copy.maxDelay, original.maxDelay);
        expect(copy.useJitter, original.useJitter);
        expect(copy.jitterFactor, original.jitterFactor);
      });
    });

    group('toString', () {
      test('includes key parameters', () {
        final policy = RetryPolicy(
          maxAttempts: 5,
          initialDelay: Duration(seconds: 1),
        );

        final str = policy.toString();
        expect(str, contains('maxAttempts: 5'));
        expect(str, contains('1000ms'));
      });
    });

    group('real-world scenarios', () {
      test('full retry sequence', () {
        final policy = RetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 100),
          backoffMultiplier: 2.0,
          useJitter: false,
        );

        // Simulate retry loop
        final delays = <Duration>[];
        for (int attempt = 0; policy.shouldRetry(attempt); attempt++) {
          delays.add(policy.delayForAttempt(attempt));
        }

        expect(delays, [
          Duration(milliseconds: 100),
          Duration(milliseconds: 200),
          Duration(milliseconds: 400),
        ]);
      });

      test('no retries with RetryPolicy.none', () {
        final policy = RetryPolicy.none;

        final delays = <Duration>[];
        for (int attempt = 0; policy.shouldRetry(attempt); attempt++) {
          delays.add(policy.delayForAttempt(attempt));
        }

        expect(delays, isEmpty);
      });
    });
  });
}
