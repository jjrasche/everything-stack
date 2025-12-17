import 'package:http/http.dart';
import '../services/timeout_config.dart';

/// HTTP client wrapper that applies timeouts to all requests.
///
/// Layer 1 defense against hanging connections.
/// Wraps any HTTP client and enforces a global timeout on all operations.
///
/// ## Usage
/// ```dart
/// final client = TimeoutHttpClient(Client());
/// final response = await client.get(Uri.parse('https://api.example.com'));
/// // Automatically times out after 30 seconds
/// ```
///
/// ## Why This Exists
/// Without timeouts, HTTP requests can hang indefinitely:
/// - Server doesn't respond
/// - Network drops mid-request
/// - DNS lookup hangs
///
/// This prevents connection leaks and socket exhaustion.
///
/// ## Timeout Strategy
/// - Default timeout: [TimeoutConfig.httpDefault] (30 seconds)
/// - Configurable per-instance
/// - Services can override with their own timeouts (Layer 2)
/// - Callers can override with user-facing deadlines (Layer 3)
class TimeoutHttpClient extends BaseClient {
  final Client _inner;
  final Duration timeout;

  /// Creates a timeout wrapper around an HTTP client.
  ///
  /// [timeout] defaults to [TimeoutConfig.httpDefault] (30 seconds).
  TimeoutHttpClient(
    this._inner, {
    this.timeout = TimeoutConfig.httpDefault,
  });

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    return await _inner.send(request).timeout(
          timeout,
          onTimeout: () => throw TimeoutHttpException(
            'HTTP request timed out after ${timeout.inSeconds}s',
            uri: request.url,
          ),
        );
  }

  @override
  void close() {
    _inner.close();
  }
}

/// Exception thrown when HTTP request times out.
///
/// Includes the URI that timed out for debugging.
class TimeoutHttpException implements Exception {
  final String message;
  final Uri? uri;

  TimeoutHttpException(this.message, {this.uri});

  @override
  String toString() {
    if (uri != null) {
      return 'TimeoutHttpException: $message (URI: $uri)';
    }
    return 'TimeoutHttpException: $message';
  }
}
