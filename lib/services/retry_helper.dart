import 'dart:async';
import 'dart:math' as math;

/// Retry helper for idempotent operations with exponential backoff.
///
/// Use this to wrap network operations that are safe to retry (read operations,
/// generation operations, etc.). Do NOT use for mutations (save, delete, etc.)
/// as they might have side effects.
///
/// ## Usage
/// ```dart
/// final result = await retryWithBackoff(
///   operation: () => embeddingService.generate(text),
///   maxAttempts: 3,
///   initialDelay: Duration(seconds: 1),
///   onAttempt: (attempt) => print('Attempt $attempt'),
/// );
/// ```
///
/// ## Exponential Backoff
/// Delays between retries increase exponentially:
/// - Attempt 1: No delay
/// - Attempt 2: initialDelay (e.g., 1s)
/// - Attempt 3: initialDelay * 2 (e.g., 2s)
/// - Attempt 4: initialDelay * 4 (e.g., 4s)
///
/// This prevents overwhelming a struggling service.
///
/// ## When to Use
/// ✅ **Safe to retry (idempotent):**
/// - Embedding generation
/// - Semantic search
/// - File download
/// - Read operations
///
/// ❌ **NOT safe to retry (side effects):**
/// - Entity save/update/delete
/// - File upload (might duplicate)
/// - Payment processing
/// - Sending emails
///
/// For non-idempotent operations, use queue-based reconciliation instead.
Future<T> retryWithBackoff<T>({
  required Future<T> Function() operation,
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
  void Function(int attempt)? onAttempt,
  void Function(int attempt, Object error)? onError,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError('maxAttempts must be >= 1');
  }

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    onAttempt?.call(attempt);

    try {
      return await operation();
    } catch (e) {
      // Last attempt - rethrow
      if (attempt == maxAttempts) {
        onError?.call(attempt, e);
        rethrow;
      }

      // Not last attempt - log and retry after backoff
      onError?.call(attempt, e);

      // Exponential backoff: delay * 2^(attempt-1)
      // Attempt 1→2: delay * 1 = 1s
      // Attempt 2→3: delay * 2 = 2s
      // Attempt 3→4: delay * 4 = 4s
      final backoffDelay = initialDelay * math.pow(2, attempt - 1).toInt();
      await Future.delayed(backoffDelay);
    }
  }

  // Should be unreachable due to rethrow in loop
  throw StateError('Retry loop completed without return or rethrow');
}

/// Retry with jitter to prevent thundering herd.
///
/// Like [retryWithBackoff], but adds random jitter (0-50%) to delay
/// to prevent multiple clients from retrying at the same time.
///
/// ## Usage
/// ```dart
/// final result = await retryWithJitter(
///   operation: () => api.get('/users'),
///   maxAttempts: 3,
/// );
/// ```
///
/// ## When to Use
/// Use this when:
/// - Multiple clients might fail simultaneously (e.g., service outage)
/// - You want to spread out retry attempts to avoid overwhelming a recovering service
///
/// Don't use this when:
/// - You're the only client (jitter adds unnecessary delay)
/// - Timing is critical (jitter makes retry timing unpredictable)
Future<T> retryWithJitter<T>({
  required Future<T> Function() operation,
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
  void Function(int attempt)? onAttempt,
  void Function(int attempt, Object error)? onError,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError('maxAttempts must be >= 1');
  }

  final random = math.Random();

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    onAttempt?.call(attempt);

    try {
      return await operation();
    } catch (e) {
      // Last attempt - rethrow
      if (attempt == maxAttempts) {
        onError?.call(attempt, e);
        rethrow;
      }

      // Not last attempt - log and retry after jittered backoff
      onError?.call(attempt, e);

      // Exponential backoff with 0-50% jitter
      final baseDelay = initialDelay * math.pow(2, attempt - 1).toInt();
      final jitterFactor = 0.5 + (random.nextDouble() * 0.5); // 0.5 to 1.0
      final jitteredDelay = baseDelay * jitterFactor;

      await Future.delayed(jitteredDelay);
    }
  }

  // Should be unreachable due to rethrow in loop
  throw StateError('Retry loop completed without return or rethrow');
}

/// Retry configuration for common scenarios.
///
/// Pre-configured retry strategies for different operation types.
class RetryConfig {
  final int maxAttempts;
  final Duration initialDelay;

  const RetryConfig({
    required this.maxAttempts,
    required this.initialDelay,
  });

  /// Quick operations (embedding, search)
  ///
  /// 3 attempts, 1s initial delay (1s, 2s total ~3s overhead)
  static const quick = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
  );

  /// Standard operations (API calls, downloads)
  ///
  /// 3 attempts, 2s initial delay (2s, 4s total ~6s overhead)
  static const standard = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 2),
  );

  /// Slow operations (large uploads, batch processing)
  ///
  /// 5 attempts, 5s initial delay (5s, 10s, 20s, 40s total ~75s overhead)
  static const slow = RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 5),
  );

  /// Critical operations (must succeed if possible)
  ///
  /// 10 attempts, 1s initial delay (1s, 2s, 4s, 8s, ... total ~1023s = ~17min overhead)
  static const critical = RetryConfig(
    maxAttempts: 10,
    initialDelay: Duration(seconds: 1),
  );
}
