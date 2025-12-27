/// # Event Retry Utilities
///
/// ## What it does
/// Provides retry backoff calculation for failed events.
///
/// ## Retry Policies
/// - **Exponential Backoff**: 1s, 10s, 100s (capped at 5min)
/// - **Linear Backoff**: 1s, 2s, 3s, ... (capped at 5min)
/// - **None**: No retries
///
/// ## Usage
/// ```dart
/// final nextRetryAt = calculateNextRetryAt(
///   retryPolicy: RetryPolicy.exponentialBackoff,
///   retryCount: 2,  // Third attempt
/// );
/// event.nextRetryAt = nextRetryAt;
/// ```

import 'event.dart';

/// Maximum backoff time in milliseconds (5 minutes)
const int _maxBackoffMs = 5 * 60 * 1000; // 300000ms

/// Calculate next retry time in Unix milliseconds
///
/// Returns Unix timestamp (milliseconds since epoch) when event should retry.
/// Returns null if retry policy is 'none'.
///
/// ## Exponential Backoff
/// - Attempt 1: 1 second  (1000ms)
/// - Attempt 2: 10 seconds (10000ms)
/// - Attempt 3: 100 seconds (100000ms)
/// - Attempt 4+: 5 minutes (300000ms, capped)
///
/// Formula: 10^retryCount seconds (capped at 5min)
///
/// ## Linear Backoff
/// - Attempt 1: 1 second (1000ms)
/// - Attempt 2: 2 seconds (2000ms)
/// - Attempt 3: 3 seconds (3000ms)
/// - ...
/// - Attempt 300+: 5 minutes (300000ms, capped)
///
/// Formula: retryCount seconds (capped at 5min)
int? calculateNextRetryAt({
  required RetryPolicy retryPolicy,
  required int retryCount,
}) {
  if (retryPolicy == RetryPolicy.none) {
    return null;
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  int backoffMs;

  switch (retryPolicy) {
    case RetryPolicy.exponentialBackoff:
      // 10^retryCount seconds, converted to milliseconds
      // retryCount=1 -> 10^1 = 10s -> 10000ms
      // retryCount=2 -> 10^2 = 100s -> 100000ms
      // retryCount=3 -> 10^3 = 1000s -> 1000000ms (exceeds cap, use cap)
      backoffMs = _pow10(retryCount) * 1000;
      break;

    case RetryPolicy.linearBackoff:
      // retryCount seconds, converted to milliseconds
      // retryCount=1 -> 1s -> 1000ms
      // retryCount=2 -> 2s -> 2000ms
      // retryCount=300 -> 300s -> 300000ms (5min, at cap)
      backoffMs = retryCount * 1000;
      break;

    case RetryPolicy.none:
      return null; // Already handled above, but for exhaustiveness
  }

  // Cap at 5 minutes
  if (backoffMs > _maxBackoffMs) {
    backoffMs = _maxBackoffMs;
  }

  return now + backoffMs;
}

/// Integer power of 10
///
/// Returns 10^exponent as an integer.
/// Used for exponential backoff calculation.
///
/// Examples:
/// - _pow10(1) = 10
/// - _pow10(2) = 100
/// - _pow10(3) = 1000
int _pow10(int exponent) {
  int result = 1;
  for (int i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// Check if event should retry
///
/// Returns true if event has retry attempts remaining.
/// Returns false if retries exhausted or retry policy is 'none'.
bool shouldRetry({
  required RetryPolicy retryPolicy,
  required int retryCount,
  required int maxRetries,
}) {
  if (retryPolicy == RetryPolicy.none) {
    return false;
  }

  return retryCount < maxRetries;
}
