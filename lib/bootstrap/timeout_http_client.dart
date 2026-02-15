import 'package:http/http.dart';
import '../services/timeout_config.dart';

/// HTTP client wrapper that enforces global timeouts on all requests.
///
/// ## Why this exists
/// Without timeouts, HTTP requests can hang indefinitely (server unresponsive,
/// network drop, DNS hang), causing connection leaks and socket exhaustion.
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
