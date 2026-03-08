/// IO pattern for stateless request/response interactions.
/// Each send() is independent. No persistent connection.
///
/// Used by: REST APIs (Graph, Groq, Jina), gRPC unary calls.
abstract class RequestResponse {
  /// Unique identifier for this client.
  String get id;

  /// Send a request and receive a response.
  Future<ResponseData> send(RequestData request);

  /// Release resources.
  void dispose();
}

/// Describes an outgoing request.
class RequestData {
  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, String> queryParams;
  final String? body;

  const RequestData({
    required this.method,
    required this.path,
    this.headers = const {},
    this.queryParams = const {},
    this.body,
  });

  factory RequestData.get(
    String path, {
    Map<String, String> headers = const {},
    Map<String, String> queryParams = const {},
  }) =>
      RequestData(
        method: 'GET',
        path: path,
        headers: headers,
        queryParams: queryParams,
      );

  factory RequestData.post(
    String path, {
    Map<String, String> headers = const {},
    Map<String, String> queryParams = const {},
    String? body,
  }) =>
      RequestData(
        method: 'POST',
        path: path,
        headers: headers,
        queryParams: queryParams,
        body: body,
      );
}

/// Describes an incoming response.
class ResponseData {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  const ResponseData({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}
