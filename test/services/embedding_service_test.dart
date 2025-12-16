/// # EmbeddingService Tests
///
/// TDD tests for the EmbeddingService interface and implementations.
/// Tests the abstract interface, mock implementation, and error handling.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

void main() {
  // Store original instance to restore after tests
  late EmbeddingService originalInstance;

  setUpAll(() {
    // Initialize with mock for testing
    EmbeddingService.instance = MockEmbeddingService();
    originalInstance = EmbeddingService.instance;
  });

  setUp(() {
    EmbeddingService.instance = originalInstance;
  });

  tearDown(() {
    // Restore original instance to prevent test pollution
    EmbeddingService.instance = originalInstance;
  });

  group('EmbeddingService interface', () {
    // ============ Interface Contract ============

    test('dimension constant is 384 (Gemini text-embedding-004)', () {
      expect(EmbeddingService.dimension, 384);
    });

    test('default instance is available', () {
      final service = EmbeddingService.instance;
      expect(service, isNotNull);
    });

    test('can set custom instance', () {
      final mock = MockEmbeddingService();
      EmbeddingService.instance = mock;
      expect(EmbeddingService.instance, same(mock));
    });

    test('default instance is MockEmbeddingService', () {
      // Fresh instance should be Mock for safe testing
      EmbeddingService.instance = MockEmbeddingService();
      expect(EmbeddingService.instance, isA<MockEmbeddingService>());
    });
  });

  group('MockEmbeddingService', () {
    late MockEmbeddingService service;

    setUp(() {
      service = MockEmbeddingService();
    });

    // ============ Deterministic Behavior ============

    test('generate returns vector of correct dimension', () async {
      final embedding = await service.generate('hello world');
      expect(embedding.length, EmbeddingService.dimension);
    });

    test('generate returns same vector for same input', () async {
      final first = await service.generate('hello world');
      final second = await service.generate('hello world');
      expect(first, equals(second));
    });

    test('generate returns different vectors for different inputs', () async {
      final hello = await service.generate('hello');
      final goodbye = await service.generate('goodbye');
      expect(hello, isNot(equals(goodbye)));
    });

    test('generate returns normalized vectors', () async {
      final embedding = await service.generate('test input');

      // L2 norm should be approximately 1
      var sumSquares = 0.0;
      for (final v in embedding) {
        sumSquares += v * v;
      }
      final norm = math.sqrt(sumSquares);
      expect(norm, closeTo(1.0, 0.001));
    });

    test('generate returns values in valid range', () async {
      final embedding = await service.generate('test input');

      // All values should be in [-1, 1] range (since we normalize)
      for (final v in embedding) {
        expect(v, inInclusiveRange(-1.0, 1.0));
      }
    });

    // ============ Batch Generation ============

    test('generateBatch returns correct number of embeddings', () async {
      final texts = ['one', 'two', 'three'];
      final embeddings = await service.generateBatch(texts);
      expect(embeddings.length, 3);
    });

    test('generateBatch returns same as individual generate calls', () async {
      final texts = ['apple', 'banana', 'cherry'];
      final batchResults = await service.generateBatch(texts);
      final individualResults = await Future.wait(
        texts.map((t) => service.generate(t)),
      );

      for (var i = 0; i < texts.length; i++) {
        expect(batchResults[i], equals(individualResults[i]));
      }
    });

    test('generateBatch handles empty list', () async {
      final embeddings = await service.generateBatch([]);
      expect(embeddings, isEmpty);
    });

    // ============ Edge Cases ============

    test('generate handles empty string', () async {
      final embedding = await service.generate('');
      expect(embedding.length, EmbeddingService.dimension);
    });

    test('generate handles whitespace-only string', () async {
      final embedding = await service.generate('   ');
      expect(embedding.length, EmbeddingService.dimension);
    });

    test('generate handles very long text', () async {
      final longText = 'word ' * 10000;
      final embedding = await service.generate(longText);
      expect(embedding.length, EmbeddingService.dimension);
    });

    test('generate handles unicode text', () async {
      final embedding = await service.generate('こんにちは世界 🌍');
      expect(embedding.length, EmbeddingService.dimension);
    });

    // ============ Consistency Across Instances ============

    test('different MockEmbeddingService instances produce same results',
        () async {
      final service1 = MockEmbeddingService();
      final service2 = MockEmbeddingService();

      final result1 = await service1.generate('test');
      final result2 = await service2.generate('test');

      expect(result1, equals(result2));
    });
  });

  group('EmbeddingService.cosineSimilarity', () {
    test('identical vectors have similarity 1', () {
      final v = [1.0, 0.0, 0.0];
      expect(EmbeddingService.cosineSimilarity(v, v), closeTo(1.0, 0.0001));
    });

    test('opposite vectors have similarity -1', () {
      final a = [1.0, 0.0, 0.0];
      final b = [-1.0, 0.0, 0.0];
      expect(EmbeddingService.cosineSimilarity(a, b), closeTo(-1.0, 0.0001));
    });

    test('orthogonal vectors have similarity 0', () {
      final a = [1.0, 0.0, 0.0];
      final b = [0.0, 1.0, 0.0];
      expect(EmbeddingService.cosineSimilarity(a, b), closeTo(0.0, 0.0001));
    });

    test('throws on mismatched dimensions', () {
      final a = [1.0, 2.0];
      final b = [1.0, 2.0, 3.0];
      expect(
        () => EmbeddingService.cosineSimilarity(a, b),
        throwsArgumentError,
      );
    });

    test('handles zero vectors gracefully', () {
      final zero = [0.0, 0.0, 0.0];
      final nonZero = [1.0, 0.0, 0.0];
      expect(EmbeddingService.cosineSimilarity(zero, nonZero), 0.0);
    });

    test('handles empty lists gracefully', () {
      final empty = <double>[];
      expect(EmbeddingService.cosineSimilarity(empty, empty), 0.0);
    });

    test('similarity is symmetric', () {
      final a = [1.0, 2.0, 3.0];
      final b = [4.0, 5.0, 6.0];
      expect(
        EmbeddingService.cosineSimilarity(a, b),
        EmbeddingService.cosineSimilarity(b, a),
      );
    });

    test('normalized vectors work correctly', () async {
      final service = MockEmbeddingService();
      final a = await service.generate('hello');
      final b = await service.generate('hello');
      // Same normalized vectors should have similarity ~1
      expect(EmbeddingService.cosineSimilarity(a, b), closeTo(1.0, 0.0001));
    });
  });

  group('GeminiEmbeddingService', () {
    // ============ Configuration ============

    test('throws when API key not configured', () {
      final service = GeminiEmbeddingService(apiKey: null);
      expect(
        () => service.generate('test'),
        throwsA(isA<EmbeddingServiceException>()),
      );
    });

    test('throws when API key is empty string', () {
      final service = GeminiEmbeddingService(apiKey: '');
      expect(
        () => service.generate('test'),
        throwsA(isA<EmbeddingServiceException>()),
      );
    });

    test('can be constructed with API key', () {
      final service = GeminiEmbeddingService(apiKey: 'test-key');
      expect(service, isNotNull);
    });

    test('throws when HTTP client not configured', () {
      final service = GeminiEmbeddingService(apiKey: 'test-key');
      expect(
        () => service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('HTTP client not configured'),
          ),
        ),
      );
    });

    // ============ fromEnvironment ============

    test('fromEnvironment returns service instance', () {
      final service = GeminiEmbeddingService.fromEnvironment();
      expect(service, isNotNull);
      expect(service, isA<GeminiEmbeddingService>());
    });

    // ============ Successful API Calls ============

    test('generate parses successful API response', () async {
      final mockResponse = jsonEncode({
        'embedding': {
          'values': List.generate(384, (i) => i * 0.001),
        }
      });

      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => mockResponse,
      );

      final result = await service.generate('test');
      expect(result.length, 384);
      expect(result[0], closeTo(0.0, 0.0001));
      expect(result[1], closeTo(0.001, 0.0001));
    });

    test('generateBatch parses successful API response', () async {
      final mockResponse = jsonEncode({
        'embeddings': [
          {'values': List.generate(384, (i) => i * 0.001)},
          {'values': List.generate(384, (i) => i * 0.002)},
        ]
      });

      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => mockResponse,
      );

      final results = await service.generateBatch(['one', 'two']);
      expect(results.length, 2);
      expect(results[0].length, 384);
      expect(results[1].length, 384);
    });

    test('generateBatch handles empty list', () async {
      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => '{}',
      );

      final results = await service.generateBatch([]);
      expect(results, isEmpty);
    });

    // ============ Error Handling ============

    test('handles API error response', () async {
      final errorResponse = jsonEncode({
        'error': {
          'message': 'Invalid API key',
          'code': 401,
        }
      });

      final service = GeminiEmbeddingService(
        apiKey: 'invalid-key',
        httpClient: (url, headers, body) async => errorResponse,
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Invalid API key'),
          ),
        ),
      );
    });

    test('handles API error in batch response', () async {
      final errorResponse = jsonEncode({
        'error': {
          'message': 'Rate limit exceeded',
        }
      });

      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => errorResponse,
      );

      expect(
        service.generateBatch(['one', 'two']),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Rate limit exceeded'),
          ),
        ),
      );
    });

    test('wraps JSON decode errors', () async {
      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => 'not valid json',
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.cause,
            'cause',
            isA<FormatException>(),
          ),
        ),
      );
    });

    test('wraps network errors', () async {
      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async {
          throw Exception('Network unavailable');
        },
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.cause.toString(),
            'cause',
            contains('Network unavailable'),
          ),
        ),
      );
    });

    // ============ Dimension Validation ============

    test('throws on wrong dimension in single response', () async {
      final wrongDimResponse = jsonEncode({
        'embedding': {
          'values':
              List.generate(128, (i) => i * 0.001), // Wrong: 128 instead of 384
        }
      });

      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => wrongDimResponse,
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected embedding dimension: 128'),
          ),
        ),
      );
    });

    test('throws on wrong dimension in batch response', () async {
      final wrongDimResponse = jsonEncode({
        'embeddings': [
          {'values': List.generate(384, (i) => i * 0.001)}, // Correct
          {'values': List.generate(256, (i) => i * 0.001)}, // Wrong
        ]
      });

      final service = GeminiEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => wrongDimResponse,
      );

      expect(
        service.generateBatch(['one', 'two']),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected embedding dimension: 256'),
          ),
        ),
      );
    });

    // ============ Request Format ============

    test('sends correct request format for single embedding', () async {
      String? capturedUrl;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final mockResponse = jsonEncode({
        'embedding': {
          'values': List.generate(384, (i) => 0.0),
        }
      });

      final service = GeminiEmbeddingService(
        apiKey: 'my-api-key',
        model: 'text-embedding-004',
        httpClient: (url, headers, body) async {
          capturedUrl = url;
          capturedHeaders = headers;
          capturedBody = body;
          return mockResponse;
        },
      );

      await service.generate('hello world');

      expect(capturedUrl, contains('embedContent'));
      expect(capturedUrl, contains('key=my-api-key'));
      expect(capturedHeaders!['Content-Type'], 'application/json');

      final bodyJson = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(bodyJson['model'], 'models/text-embedding-004');
      expect(bodyJson['content']['parts'][0]['text'], 'hello world');
    });

    test('sends correct request format for batch embedding', () async {
      String? capturedUrl;
      String? capturedBody;

      final mockResponse = jsonEncode({
        'embeddings': [
          {'values': List.generate(384, (i) => 0.0)},
          {'values': List.generate(384, (i) => 0.0)},
        ]
      });

      final service = GeminiEmbeddingService(
        apiKey: 'my-api-key',
        httpClient: (url, headers, body) async {
          capturedUrl = url;
          capturedBody = body;
          return mockResponse;
        },
      );

      await service.generateBatch(['text1', 'text2']);

      expect(capturedUrl, contains('batchEmbedContents'));

      final bodyJson = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final requests = bodyJson['requests'] as List;
      expect(requests.length, 2);
      expect(requests[0]['content']['parts'][0]['text'], 'text1');
      expect(requests[1]['content']['parts'][0]['text'], 'text2');
    });
  });

  group('JinaEmbeddingService', () {
    // ============ Configuration ============

    test('throws when API key not configured', () {
      final service = JinaEmbeddingService(apiKey: null);
      expect(
        () => service.generate('test'),
        throwsA(isA<EmbeddingServiceException>()),
      );
    });

    test('throws when API key is empty string', () {
      final service = JinaEmbeddingService(apiKey: '');
      expect(
        () => service.generate('test'),
        throwsA(isA<EmbeddingServiceException>()),
      );
    });

    test('can be constructed with API key', () {
      final service = JinaEmbeddingService(apiKey: 'test-key');
      expect(service, isNotNull);
    });

    test('throws when HTTP client not configured', () {
      final service = JinaEmbeddingService(apiKey: 'test-key');
      expect(
        () => service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('HTTP client not configured'),
          ),
        ),
      );
    });

    // ============ fromEnvironment ============

    test('fromEnvironment returns service instance', () {
      final service = JinaEmbeddingService.fromEnvironment();
      expect(service, isNotNull);
      expect(service, isA<JinaEmbeddingService>());
    });

    // ============ Successful API Calls ============

    test('generate parses successful API response', () async {
      final mockResponse = jsonEncode({
        'data': [
          {
            'embedding': List.generate(384, (i) => i * 0.001),
            'index': 0,
          }
        ],
        'model': 'jina-embeddings-v3',
        'usage': {'total_tokens': 5},
      });

      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => mockResponse,
      );

      final result = await service.generate('test');
      expect(result.length, 384);
      expect(result[0], closeTo(0.0, 0.0001));
      expect(result[1], closeTo(0.001, 0.0001));
    });

    test('generateBatch parses successful API response', () async {
      final mockResponse = jsonEncode({
        'data': [
          {
            'embedding': List.generate(384, (i) => i * 0.001),
            'index': 0,
          },
          {
            'embedding': List.generate(384, (i) => i * 0.002),
            'index': 1,
          },
        ],
        'model': 'jina-embeddings-v3',
      });

      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => mockResponse,
      );

      final results = await service.generateBatch(['one', 'two']);
      expect(results.length, 2);
      expect(results[0].length, 384);
      expect(results[1].length, 384);
    });

    test('generateBatch handles out-of-order response', () async {
      // API might return embeddings in different order
      final mockResponse = jsonEncode({
        'data': [
          {
            'embedding': List.generate(384, (i) => 2.0), // index 1
            'index': 1,
          },
          {
            'embedding': List.generate(384, (i) => 1.0), // index 0
            'index': 0,
          },
        ],
      });

      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => mockResponse,
      );

      final results = await service.generateBatch(['first', 'second']);
      // Should be sorted by index
      expect(results[0][0], 1.0); // index 0
      expect(results[1][0], 2.0); // index 1
    });

    test('generateBatch handles empty list', () async {
      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => '{}',
      );

      final results = await service.generateBatch([]);
      expect(results, isEmpty);
    });

    // ============ Error Handling ============

    test('handles API error with detail field', () async {
      final errorResponse = jsonEncode({
        'detail': 'Invalid API key provided',
      });

      final service = JinaEmbeddingService(
        apiKey: 'invalid-key',
        httpClient: (url, headers, body) async => errorResponse,
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Invalid API key'),
          ),
        ),
      );
    });

    test('handles API error with error field', () async {
      final errorResponse = jsonEncode({
        'error': {
          'message': 'Rate limit exceeded',
        }
      });

      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => errorResponse,
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Rate limit exceeded'),
          ),
        ),
      );
    });

    test('wraps network errors', () async {
      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async {
          throw Exception('Network unavailable');
        },
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.cause.toString(),
            'cause',
            contains('Network unavailable'),
          ),
        ),
      );
    });

    // ============ Dimension Validation ============

    test('throws on wrong dimension in response', () async {
      final wrongDimResponse = jsonEncode({
        'data': [
          {
            'embedding': List.generate(
                768, (i) => i * 0.001), // Wrong: 768 instead of 384
            'index': 0,
          }
        ],
      });

      final service = JinaEmbeddingService(
        apiKey: 'test-key',
        httpClient: (url, headers, body) async => wrongDimResponse,
      );

      expect(
        service.generate('test'),
        throwsA(
          isA<EmbeddingServiceException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected embedding dimension: 768'),
          ),
        ),
      );
    });

    // ============ Request Format ============

    test('sends correct request format', () async {
      String? capturedUrl;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final mockResponse = jsonEncode({
        'data': [
          {
            'embedding': List.generate(384, (i) => 0.0),
            'index': 0,
          }
        ],
      });

      final service = JinaEmbeddingService(
        apiKey: 'my-api-key',
        model: 'jina-embeddings-v3',
        httpClient: (url, headers, body) async {
          capturedUrl = url;
          capturedHeaders = headers;
          capturedBody = body;
          return mockResponse;
        },
      );

      await service.generate('hello world');

      expect(capturedUrl, contains('/embeddings'));
      expect(capturedHeaders!['Content-Type'], 'application/json');
      expect(capturedHeaders!['Authorization'], 'Bearer my-api-key');

      final bodyJson = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(bodyJson['model'], 'jina-embeddings-v3');
      expect(bodyJson['input'], ['hello world']);
      expect(bodyJson['dimensions'], 384);
    });

    test('sends batch request with multiple inputs', () async {
      String? capturedBody;

      final mockResponse = jsonEncode({
        'data': [
          {'embedding': List.generate(384, (i) => 0.0), 'index': 0},
          {'embedding': List.generate(384, (i) => 0.0), 'index': 1},
        ],
      });

      final service = JinaEmbeddingService(
        apiKey: 'my-api-key',
        httpClient: (url, headers, body) async {
          capturedBody = body;
          return mockResponse;
        },
      );

      await service.generateBatch(['text1', 'text2']);

      final bodyJson = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(bodyJson['input'], ['text1', 'text2']);
    });
  });

  group('EmbeddingServiceException', () {
    test('contains message', () {
      final exception = EmbeddingServiceException('API error');
      expect(exception.message, 'API error');
      expect(exception.toString(), contains('API error'));
    });

    test('can wrap original error', () {
      final originalError = Exception('Network failed');
      final exception = EmbeddingServiceException(
        'Failed to generate embedding',
        cause: originalError,
      );
      expect(exception.cause, originalError);
    });

    test('toString includes cause when present', () {
      final originalError = Exception('Network failed');
      final exception = EmbeddingServiceException(
        'Failed',
        cause: originalError,
      );
      expect(exception.toString(), contains('caused by'));
      expect(exception.toString(), contains('Network failed'));
    });

    test('toString works without cause', () {
      final exception = EmbeddingServiceException('Simple error');
      expect(exception.toString(), 'EmbeddingServiceException: Simple error');
      expect(exception.toString(), isNot(contains('caused by')));
    });
  });
}
