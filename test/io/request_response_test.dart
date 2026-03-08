import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/io/patterns/request_response.dart';

void main() {
  group('RequestData', () {
    test('get factory creates GET request without body', () {
      final request = RequestData.get('/api/test');

      expect(request.method, 'GET');
      expect(request.path, '/api/test');
      expect(request.body, isNull);
    });

    test('post factory creates POST request with body', () {
      final request = RequestData.post(
        '/api/test',
        body: '{"key": "value"}',
      );

      expect(request.method, 'POST');
      expect(request.path, '/api/test');
      expect(request.body, '{"key": "value"}');
    });

    test('preserves headers and query params', () {
      final request = RequestData(
        method: 'GET',
        path: '/teams/123/channels',
        headers: {'X-Custom': 'value'},
        queryParams: {'limit': '10'},
      );

      expect(request.headers['X-Custom'], 'value');
      expect(request.queryParams['limit'], '10');
    });
  });

  group('ResponseData', () {
    test('isSuccess is true for 2xx status codes', () {
      expect(
        ResponseData(statusCode: 200, headers: {}, body: '').isSuccess,
        isTrue,
      );
      expect(
        ResponseData(statusCode: 201, headers: {}, body: '').isSuccess,
        isTrue,
      );
      expect(
        ResponseData(statusCode: 299, headers: {}, body: '').isSuccess,
        isTrue,
      );
    });

    test('isSuccess is false for non-2xx status codes', () {
      expect(
        ResponseData(statusCode: 400, headers: {}, body: '').isSuccess,
        isFalse,
      );
      expect(
        ResponseData(statusCode: 401, headers: {}, body: '').isSuccess,
        isFalse,
      );
      expect(
        ResponseData(statusCode: 500, headers: {}, body: '').isSuccess,
        isFalse,
      );
    });
  });
}
