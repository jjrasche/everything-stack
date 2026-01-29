/// # IO Exception Hierarchy
///
/// All exceptions thrown by the IO communication layer extend [NerveException].
/// This allows callers to catch all IO-related errors with a single catch block,
/// or handle specific failure modes individually.
///
/// ## Exception Types
/// - [ConnectionFailedException] - Initial connection attempt failed
/// - [ConnectionLostException] - Established connection was lost
/// - [TimeoutException] - Operation exceeded time limit
/// - [ProtocolException] - Protocol-level error (invalid frames, handshake failure)
///
/// ## Usage
/// ```dart
/// try {
///   await channel.connect();
/// } on ConnectionFailedException catch (e) {
///   // Handle connection failure specifically
/// } on NerveException catch (e) {
///   // Handle any IO error
/// }
/// ```

/// Base exception for all Nerve System errors.
class NerveException implements Exception {
  /// Human-readable error description.
  final String message;

  /// Optional underlying cause (for exception chaining).
  final Object? cause;

  NerveException(this.message, [this.cause]);

  @override
  String toString() {
    final buffer = StringBuffer()..write('$runtimeType: $message');
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    return buffer.toString();
  }
}

/// Thrown when initial connection attempt fails.
///
/// Common causes:
/// - Host unreachable (DNS failure, network down)
/// - Connection refused (server not listening)
/// - TLS/SSL handshake failure
/// - Authentication rejected
class ConnectionFailedException extends NerveException {
  ConnectionFailedException(super.message, [super.cause]);
}

/// Thrown when an established connection is lost unexpectedly.
///
/// Common causes:
/// - Network interruption
/// - Server shutdown
/// - Idle timeout
/// - Connection reset by peer
class ConnectionLostException extends NerveException {
  ConnectionLostException(super.message, [super.cause]);
}

/// Thrown when an operation exceeds its time limit.
///
/// Common causes:
/// - Connect timeout (server slow to respond)
/// - Read timeout (no data received)
/// - Write timeout (send buffer full)
class TimeoutException extends NerveException {
  TimeoutException(super.message, [super.cause]);
}

/// Thrown when a protocol-level error occurs.
///
/// Common causes:
/// - Invalid message frame
/// - Unexpected message type
/// - Protocol version mismatch
/// - Handshake failure (after transport connected)
class ProtocolException extends NerveException {
  ProtocolException(super.message, [super.cause]);
}
