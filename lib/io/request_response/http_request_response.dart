import 'package:http/http.dart' as http;
import '../../auth/token_provider.dart';
import '../patterns/request_response.dart';

/// HTTP implementation of the RequestResponse pattern.
/// Handles base URL construction, auth token injection, and timeouts.
class HttpRequestResponse implements RequestResponse {
  static int _idCounter = 0;

  @override
  final String id;

  final Uri _baseUri;
  final http.Client _httpClient;
  final TokenProvider? _tokenProvider;
  final Duration _timeout;

  HttpRequestResponse({
    required Uri baseUri,
    http.Client? httpClient,
    TokenProvider? tokenProvider,
    Duration timeout = const Duration(seconds: 30),
    String? id,
  })  : _baseUri = baseUri,
        _httpClient = httpClient ?? http.Client(),
        _tokenProvider = tokenProvider,
        _timeout = timeout,
        id = id ?? 'http-rr-${++_idCounter}';

  @override
  Future<ResponseData> send(RequestData request) async {
    final uri = _buildUri(request);
    final headers = await _buildHeaders(request.headers);
    final httpResponse = await _execute(request.method, uri, headers, request.body);
    return _toResponseData(httpResponse);
  }

  @override
  void dispose() {
    _httpClient.close();
  }

  Uri _buildUri(RequestData request) {
    return _baseUri.replace(
      path: '${_baseUri.path}${request.path}',
      queryParameters:
          request.queryParams.isEmpty ? null : request.queryParams,
    );
  }

  Future<Map<String, String>> _buildHeaders(
      Map<String, String> requestHeaders) async {
    final headers = <String, String>{
      ...requestHeaders,
    };
    if (_tokenProvider != null) {
      final token = await _tokenProvider.getAccessToken();
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _execute(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    if (body != null) {
      request.body = body;
    }

    final streamedResponse =
        await _httpClient.send(request).timeout(_timeout);
    return http.Response.fromStream(streamedResponse);
  }

  ResponseData _toResponseData(http.Response httpResponse) {
    return ResponseData(
      statusCode: httpResponse.statusCode,
      headers: httpResponse.headers,
      body: httpResponse.body,
    );
  }
}
