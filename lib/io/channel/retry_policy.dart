
import 'dart:math';

/// Retry policy configuration.
class RetryPolicy {
  /// Maximum number of retry attempts (0 = no retries, just initial attempt).
  final int maxAttempts;

  /// Initial delay before first retry.
  final Duration initialDelay;

  /// Multiplier for exponential backoff.
  final double backoffMultiplier;

  /// Maximum delay between retries (caps exponential growth).
  final Duration maxDelay;

  /// Whether to add random jitter to delays (prevents thundering herd).
  final bool useJitter;

  /// Jitter factor (0.0 = no jitter, 1.0 = up to 100% of delay).
  final double jitterFactor;

  const RetryPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.useJitter = true,
    this.jitterFactor = 0.25,
  });

  /// No retries - fail immediately.
  static const none = RetryPolicy(maxAttempts: 0);

  /// Default policy for production use.
  static const defaultPolicy = RetryPolicy();

  /// Aggressive retry for critical connections.
  static const aggressive = RetryPolicy(
    maxAttempts: 10,
    initialDelay: Duration(milliseconds: 500),
    backoffMultiplier: 1.5,
    maxDelay: Duration(seconds: 60),
  );

  /// Check if another retry should be attempted.
  ///
  /// [attempt] is 0-indexed (0 = first retry, not initial attempt).
  bool shouldRetry(int attempt) {
    return attempt < maxAttempts;
  }

  /// Calculate delay before the given retry attempt.
  ///
  /// [attempt] is 0-indexed (0 = first retry after initial failure).
  Duration delayForAttempt(int attempt, {Random? random}) {
    if (attempt < 0) return Duration.zero;

    final baseMs = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt).toDouble();

    // Cap at maximum delay
    final cappedMs = min(baseMs, maxDelay.inMilliseconds.toDouble());

    if (useJitter && jitterFactor > 0) {
      final rng = random ?? Random();
      final jitterMs = cappedMs * jitterFactor * rng.nextDouble();
      return Duration(milliseconds: (cappedMs + jitterMs).round());
    }

    return Duration(milliseconds: cappedMs.round());
  }

  /// Create a copy with modified parameters.
  RetryPolicy copyWith({
    int? maxAttempts,
    Duration? initialDelay,
    double? backoffMultiplier,
    Duration? maxDelay,
    bool? useJitter,
    double? jitterFactor,
  }) {
    return RetryPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      initialDelay: initialDelay ?? this.initialDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      maxDelay: maxDelay ?? this.maxDelay,
      useJitter: useJitter ?? this.useJitter,
      jitterFactor: jitterFactor ?? this.jitterFactor,
    );
  }

  @override
  String toString() => 'RetryPolicy('
      'maxAttempts: $maxAttempts, '
      'initialDelay: ${initialDelay.inMilliseconds}ms, '
      'backoffMultiplier: $backoffMultiplier, '
      'maxDelay: ${maxDelay.inMilliseconds}ms'
      ')';
}
