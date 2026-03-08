import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:everything_stack_template/io/patterns/request_response.dart';
import 'package:everything_stack_template/io/request_response/http_request_response.dart';
import 'package:everything_stack_template/auth/token_provider.dart';

class FakeTokenProvider implements TokenProvider {
  String token;
  FakeTokenProvider(this.token);

  @override
  Future<String> getAccessToken() async => token;

  @override
  bool get isAuthenticated => true;

  @override
  void dispose() {}
}

void main() {
  group('HttpRequestResponse', () {
    test('sends GET request to base URI plus path', () async {
      String? capturedUrl;
      String? capturedMethod;

      final mockClient = http_testing.MockClient((request) async {
        capturedUrl = request.url.toString();
        capturedMethod = request.method;
        return http.Response('{"status": "ok"}', 200);
      });

      final client = HttpRequestResponse(
        baseUri: Uri.parse('https://graph.microsoft.com/v1.0'),
        httpClient: mockClient,
      );

      final response = await client.send(RequestData.get('/me'));

      expect(capturedMethod, 'GET');
      expect(capturedUrl, contains('/v1.0/me'));
      expect(response.statusCode, 200);
      expect(response.body, '{"status": "ok"}');

      client.dispose();
    });

    test('injects Bearer token from TokenProvider', () async {
      String? capturedAuth;

      final mockClient = http_testing.MockClient((request) async {
        capturedAuth = request.headers['Authorization'];
        return http.Response('{}', 200);
      });

      final tokenProvider = FakeTokenProvider('test-token-abc');
      final client = HttpRequestResponse(
        baseUri: Uri.parse('https://graph.microsoft.com/v1.0'),
        httpClient: mockClient,
        tokenProvider: tokenProvider,
      );

      await client.send(RequestData.get('/me'));

      expect(capturedAuth, 'Bearer test-token-abc');

      client.dispose();
    });

    test('sends without auth header when no TokenProvider', () async {
      String? capturedAuth;

      final mockClient = http_testing.MockClient((request) async {
        capturedAuth = request.headers['Authorization'];
        return http.Response('{}', 200);
      });

      final client = HttpRequestResponse(
        baseUri: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      await client.send(RequestData.get('/public'));

      expect(capturedAuth, isNull);

      client.dispose();
    });

    test('includes query parameters in request URL', () async {
      String? capturedUrl;

      final mockClient = http_testing.MockClient((request) async {
        capturedUrl = request.url.toString();
        return http.Response('{}', 200);
      });

      final client = HttpRequestResponse(
        baseUri: Uri.parse('https://graph.microsoft.com/v1.0'),
        httpClient: mockClient,
      );

      await client.send(RequestData(
        method: 'GET',
        path: '/teams/t1/channels',
        queryParams: {'\$top': '10', '\$filter': 'active'},
      ));

      expect(capturedUrl, contains('%24top=10'));
      expect(capturedUrl, contains('%24filter=active'));

      client.dispose();
    });

    test('sends POST body', () async {
      String? capturedBody;

      final mockClient = http_testing.MockClient((request) async {
        capturedBody = request.body;
        return http.Response('{"created": true}', 201);
      });

      final client = HttpRequestResponse(
        baseUri: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      final response = await client.send(RequestData.post(
        '/items',
        body: jsonEncode({'name': 'test'}),
      ));

      expect(capturedBody, '{"name":"test"}');
      expect(response.statusCode, 201);

      client.dispose();
    });

    test('merges request headers with defaults', () async {
      Map<String, String>? capturedHeaders;

      final mockClient = http_testing.MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response('{}', 200);
      });

      final client = HttpRequestResponse(
        baseUri: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      await client.send(RequestData(
        method: 'GET',
        path: '/test',
        headers: {'X-Custom': 'value'},
      ));

      expect(capturedHeaders!['X-Custom'], 'value');

      client.dispose();
    });
  });
}
