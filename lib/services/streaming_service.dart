import 'dart:async';

/// Base contract for all streaming services (STT, TTS, LLM).
///
/// Streaming services have different lifecycle than request/response services:
/// - Long-lived connections (WebSocket, SSE)
/// - Bidirectional data flow (send audio → receive text)
/// - Multiple timeout types (connection, idle, total)
/// - Graceful cleanup on errors
///
/// ## Timeout Semantics
/// Streaming services need THREE types of timeouts:
///
/// 1. **Connection timeout**: How long to wait for initial connection
/// 2. **Idle timeout**: How long to wait between chunks (per-chunk deadline)
/// 3. **Total timeout**: Maximum duration for entire stream (caller-managed)
///
/// ## Lifecycle
/// ```dart
/// final service = DeepgramSTTService();
///
/// // 1. Initialize (authenticate, connect)
/// await service.initialize();
///
/// // 2. Stream data (bidirectional)
/// final subscription = service.stream(
///   input: audioStream,
///   onData: (text) => print('Transcript: $text'),
///   onError: (e) => print('Error: $e'),
///   onDone: () => print('Stream complete'),
/// );
///
/// // 3. Cleanup
/// await subscription.cancel();
/// service.dispose();
/// ```
///
/// ## Error Handling
/// - Timeout on connection → throw exception
/// - Timeout on idle (no data) → close stream, call onError
/// - Network error → close stream, call onError
/// - Caller cancels → clean up resources
abstract class StreamingService<Input, Output> {
  /// Initialize connection and authenticate.
  ///
  /// Call this before using [stream].
  /// May throw if connection fails or times out.
  Future<void> initialize();

  /// Start streaming data.
  ///
  /// Returns a subscription that can be cancelled to stop streaming.
  ///
  /// ## Parameters
  /// - [input]: Stream of input data (e.g., audio bytes, text prompts)
  /// - [onData]: Called for each output chunk (e.g., transcript, audio, tokens)
  /// - [onError]: Called on timeout, network error, or other failure
  /// - [onDone]: Called when stream completes normally
  ///
  /// ## Timeout Behavior
  /// - Connection timeout: Throws before returning subscription
  /// - Idle timeout: Calls onError, closes stream
  /// - Total timeout: Managed by caller (wrap with .timeout())
  ///
  /// ## Example
  /// ```dart
  /// final sub = service.stream(
  ///   input: audioStream,
  ///   onData: (text) => _handleTranscript(text),
  ///   onError: (e) => _handleError(e),
  ///   onDone: () => _handleComplete(),
  /// );
  ///
  /// // Later: cancel to stop streaming
  /// await sub.cancel();
  /// ```
  StreamSubscription<Output> stream({
    required Stream<Input> input,
    required void Function(Output) onData,
    required void Function(Object) onError,
    void Function()? onDone,
  });

  /// Cleanup resources (close connections, cancel timers, etc.)
  ///
  /// Always call this when done with the service.
  /// Safe to call multiple times.
  void dispose();

  /// Check if service is ready to use.
  ///
  /// Returns true after successful [initialize], false after [dispose].
  bool get isReady;
}
