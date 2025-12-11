/// HTTP client wrapper for embedding services.
///
/// Provides a simple HTTP POST function matching the signature required by
/// JinaEmbeddingService and GeminiEmbeddingService.
library;

import 'package:http/http.dart' as http;

/// HTTP client function type expected by embedding services.
typedef HttpClientFunction = Future<String> Function(
  String url,
  Map<String, String> headers,
  String body,
);

/// Default HTTP client implementation using package:http.
///
/// Makes a POST request and returns the response body.
/// Throws on non-2xx status codes.
Future<String> defaultHttpClient(
  String url,
  Map<String, String> headers,
  String body,
) async {
  final response = await http.post(
    Uri.parse(url),
    headers: headers,
    body: body,
  );

  if (response.statusCode >= 200 && response.statusCode < 300) {
    return response.body;
  }

  throw HttpClientException(
    'HTTP ${response.statusCode}: ${response.reasonPhrase}',
    statusCode: response.statusCode,
    body: response.body,
  );
}

/// Exception thrown when HTTP request fails.
class HttpClientException implements Exception {
  final String message;
  final int statusCode;
  final String? body;

  HttpClientException(this.message, {required this.statusCode, this.body});

  @override
  String toString() => 'HttpClientException: $message';
}
