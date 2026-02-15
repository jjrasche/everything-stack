import 'dart:convert';
import 'dart:math' as math;

import 'dart:math' show sqrt, sin;

/// Exception thrown when embedding generation fails.
class EmbeddingServiceException implements Exception {
  final String message;
  final Object? cause;

  EmbeddingServiceException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'EmbeddingServiceException: $message (caused by: $cause)';
    }
    return 'EmbeddingServiceException: $message';
  }
}

/// Abstract interface for embedding generation.
///
/// Implementations must generate embeddings of exactly [dimension] floats.
/// Embeddings should be normalized (L2 norm = 1) for consistent similarity
/// calculations.
abstract class EmbeddingService {
  /// Embedding dimension - must match model output.
  /// Using 384 to match Gemini text-embedding-004 output.
  static const int dimension = 384;

  /// Global instance for dependency injection.
  /// Set this at app startup to configure the embedding backend.
  /// Defaults to NullEmbeddingService (embeddings disabled).
  static EmbeddingService instance = NullEmbeddingService();

  /// Initialize the embedding service.
  /// Called once at startup to set up resources.
  /// Default is no-op; override if needed.
  Future<void> initialize() async {}

  /// Generate embedding for a single text input.
  /// Returns vector of length [dimension].
  ///
  /// Throws [EmbeddingServiceException] on failure.
  Future<List<double>> generate(String text);

  /// Generate embeddings for multiple texts.
  /// More efficient than individual calls for API-based implementations.
  ///
  /// Default implementation calls [generate] for each text.
  /// Override for batch API optimization.
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    if (texts.isEmpty) return [];
    return Future.wait(texts.map(generate));
  }

  /// Calculate cosine similarity between two embeddings.
  /// Returns value between -1 (opposite) and 1 (identical).
  ///
  /// Throws [ArgumentError] if embeddings have different dimensions.
  /// Returns 0 for zero vectors or empty lists.
  static double cosineSimilarity(List<double> embeddingA, List<double> embeddingB) {
    if (embeddingA.length != embeddingB.length) {
      throw ArgumentError('Embeddings must have same dimension');
    }

    double dotProduct = 0;
    double normSquaredA = 0;
    double normSquaredB = 0;

    for (int i = 0; i < embeddingA.length; i++) {
      dotProduct += embeddingA[i] * embeddingB[i];
      normSquaredA += embeddingA[i] * embeddingA[i];
      normSquaredB += embeddingB[i] * embeddingB[i];
    }

    if (normSquaredA == 0 || normSquaredB == 0) return 0;

    return dotProduct / (math.sqrt(normSquaredA) * math.sqrt(normSquaredB));
  }
}

/// Null Object implementation for production when embeddings are disabled.
///
/// Returns zero vectors and logs warnings when embedding generation is attempted.
/// Use this when no embedding API key is configured - semantic search will not work,
/// but the application continues to function.
///
/// This is NOT a mock - it's intentional production behavior for graceful degradation.
/// For testing with deterministic embeddings, use MockEmbeddingService instead.
class NullEmbeddingService extends EmbeddingService {
  @override
  Future<List<double>> generate(String text) async {
    print(
      'Warning: NullEmbeddingService - embeddings disabled. '
      'Configure JINA_API_KEY or GEMINI_API_KEY to enable semantic search.',
    );
    return List.filled(EmbeddingService.dimension, 0.0);
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    if (texts.isEmpty) return [];
    print(
      'Warning: NullEmbeddingService - embeddings disabled. '
      'Returning ${texts.length} zero vectors.',
    );
    return List.generate(
      texts.length,
      (_) => List.filled(EmbeddingService.dimension, 0.0),
    );
  }
}

/// Mock implementation for testing.
///
/// Generates deterministic embeddings based on input hash.
/// Same input always produces same output, enabling reproducible tests.
/// Uses FNV-1a hashing + trigonometric functions for distribution.
///
/// The mock does NOT have semantic understanding - it just produces
/// consistent vectors. Use for testing infrastructure, not semantics.
class MockEmbeddingService extends EmbeddingService {
  final Map<String, List<double>> _cache = {};

  @override
  Future<List<double>> generate(String text) async {
    return mockEmbedding(text);
  }

  /// Generate deterministic embedding for text.
  /// Cached for performance - same text always returns same vector.
  List<double> mockEmbedding(String text) {
    if (_cache.containsKey(text)) {
      return _cache[text]!;
    }

    // Generate semantic vector based on word content
    // Documents with shared words will have similar vectors
    final words = _tokenize(text);

    if (words.isEmpty) {
      return List.filled(EmbeddingService.dimension, 0.0);
    }

    final vector = List<double>.filled(EmbeddingService.dimension, 0.0);
    for (final word in words) {
      final wordHash = _hashString(word);
      for (var i = 0; i < EmbeddingService.dimension; i++) {
        vector[i] += _deterministicFloat(wordHash, i);
      }
    }

    // Normalize to unit length
    final normalized = _normalize(vector);
    _cache[text] = normalized;
    return normalized;
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    return texts.map((inputText) => mockEmbedding(inputText)).toList();
  }

  /// Tokenize text into lowercase words
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Remove punctuation
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
  }

  /// Hash string to int using FNV-1a algorithm.
  int _hashString(String text) {
    const fnvPrime = 0x01000193;
    const fnvOffset = 0x811c9dc5;
    var hash = fnvOffset;

    final bytes = utf8.encode(text);
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }

    return hash;
  }

  /// Generate deterministic float from hash and index.
  double _deterministicFloat(int hash, int index) {
    // Combine hash with index to get unique value per dimension
    final combined = (hash + index * 31) & 0xFFFFFFFF;
    // Use sine for smooth distribution in [-1, 1] range
    return sin(combined.toDouble() / 1000000);
  }

  /// Normalize vector to unit length.
  List<double> _normalize(List<double> vector) {
    var sumSquares = 0.0;
    for (final component in vector) {
      sumSquares += component * component;
    }

    if (sumSquares == 0) {
      return List.generate(
        vector.length,
        (i) => i == 0 ? 1.0 : 0.0,
      );
    }

    final magnitude = sqrt(sumSquares);
    return vector.map((component) => component / magnitude).toList();
  }
}

class JinaEmbeddingService extends EmbeddingService {
  final String? _apiKey;
  final String _model;
  final String _baseUrl;

  /// HTTP client function for dependency injection.
  /// Signature: (url, headers, body) -> response body
  ///
  /// If null, the service will throw EmbeddingServiceException.
  /// Inject an HTTP client implementation for production use.
  final Future<String> Function(
      String url, Map<String, String> headers, String body)? _httpClient;

  JinaEmbeddingService({
    String? apiKey,
    String model = 'jina-embeddings-v3',
    String baseUrl = 'https://api.jina.ai/v1',
    Future<String> Function(
            String url, Map<String, String> headers, String body)?
        httpClient,
  })  : _apiKey = apiKey,
        _model = model,
        _baseUrl = baseUrl,
        _httpClient = httpClient;

  /// Create from JINA_API_KEY compile-time environment variable.
  ///
  /// IMPORTANT: This uses `String.fromEnvironment` which is evaluated
  /// at compile time, not runtime. You must pass the key during build:
  /// ```
  /// flutter run --dart-define=JINA_API_KEY=your-key
  /// flutter build --dart-define=JINA_API_KEY=your-key
  /// ```
  ///
  /// Setting `export JINA_API_KEY=xxx` at runtime will NOT work.
  /// For runtime configuration, use the regular constructor instead.
  factory JinaEmbeddingService.fromEnvironment() {
    const apiKey = String.fromEnvironment('JINA_API_KEY');
    return JinaEmbeddingService(
      apiKey: apiKey.isNotEmpty ? apiKey : null,
    );
  }

  @override
  Future<List<double>> generate(String text) async {
    final results = await generateBatch([text]);
    return results.first;
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    if (texts.isEmpty) return [];

    _validateApiKey();
    _validateHttpClient();

    try {
      final url = '$_baseUrl/embeddings';
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      };
      final body = jsonEncode({
        'model': _model,
        'input': texts,
        'dimensions': EmbeddingService.dimension, // Matryoshka truncation
      });

      final responseBody = await _httpClient!(url, headers, body);
      final response = jsonDecode(responseBody) as Map<String, dynamic>;

      _checkForApiError(response);

      final embeddingEntries = response['data'] as List;
      final batchEmbeddings = <List<double>>[];

      final sortedEntries = List<Map<String, dynamic>>.from(
        embeddingEntries.map((entry) => entry as Map<String, dynamic>),
      )..sort((entryA, entryB) => (entryA['index'] as int).compareTo(entryB['index'] as int));

      for (final embeddingEntry in sortedEntries) {
        final embeddingValues = (embeddingEntry['embedding'] as List).cast<num>();
        _validateDimension(embeddingValues.length);
        batchEmbeddings.add(embeddingValues.map((numValue) => numValue.toDouble()).toList());
      }

      return batchEmbeddings;
    } on EmbeddingServiceException {
      rethrow;
    } catch (e) {
      throw EmbeddingServiceException(
        'Failed to generate embeddings',
        cause: e,
      );
    }
  }

  void _validateApiKey() {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw EmbeddingServiceException(
        'JINA_API_KEY not configured. '
        'Pass apiKey to constructor or use --dart-define=JINA_API_KEY=your-key at build time.',
      );
    }
  }

  void _validateHttpClient() {
    if (_httpClient == null) {
      throw EmbeddingServiceException(
        'HTTP client not configured. '
        'Inject an httpClient function to make API calls.',
      );
    }
  }

  void _validateDimension(int actual) {
    if (actual != EmbeddingService.dimension) {
      throw EmbeddingServiceException(
        'Unexpected embedding dimension: $actual '
        '(expected ${EmbeddingService.dimension})',
      );
    }
  }

  void _checkForApiError(Map<String, dynamic> response) {
    if (response.containsKey('detail')) {
      throw EmbeddingServiceException(
        'Jina API error: ${response['detail']}',
      );
    }
    if (response.containsKey('error')) {
      final error = response['error'];
      final message = error is Map ? error['message'] : error.toString();
      throw EmbeddingServiceException(
        'Jina API error: $message',
      );
    }
  }
}

/// Gemini API passes the key in the URL query string (required by their API).
/// Be aware this may be logged by proxies or monitoring tools.
class GeminiEmbeddingService extends EmbeddingService {
  final String? _apiKey;
  final String _model;
  final String _baseUrl;

  /// HTTP client function for dependency injection.
  /// Signature: (url, headers, body) -> response body
  ///
  /// If null, the service will throw EmbeddingServiceException.
  /// Inject an HTTP client implementation for production use.
  final Future<String> Function(
      String url, Map<String, String> headers, String body)? _httpClient;

  GeminiEmbeddingService({
    String? apiKey,
    String model = 'text-embedding-004',
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    Future<String> Function(
            String url, Map<String, String> headers, String body)?
        httpClient,
  })  : _apiKey = apiKey,
        _model = model,
        _baseUrl = baseUrl,
        _httpClient = httpClient;

  /// Create from GEMINI_API_KEY compile-time environment variable.
  ///
  /// IMPORTANT: This uses `String.fromEnvironment` which is evaluated
  /// at compile time, not runtime. You must pass the key during build:
  /// ```
  /// flutter run --dart-define=GEMINI_API_KEY=your-key
  /// flutter build --dart-define=GEMINI_API_KEY=your-key
  /// ```
  ///
  /// Setting `export GEMINI_API_KEY=xxx` at runtime will NOT work.
  /// For runtime configuration, use the regular constructor instead.
  factory GeminiEmbeddingService.fromEnvironment() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    return GeminiEmbeddingService(
      apiKey: apiKey.isNotEmpty ? apiKey : null,
    );
  }

  @override
  Future<List<double>> generate(String text) async {
    _validateApiKey();
    _validateHttpClient();

    try {
      final url = '$_baseUrl/models/$_model:embedContent?key=$_apiKey';
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'model': 'models/$_model',
        'content': {
          'parts': [
            {'text': text}
          ]
        }
      });

      final responseBody = await _httpClient!(url, headers, body);
      final response = jsonDecode(responseBody) as Map<String, dynamic>;

      _checkForApiError(response);

      final embeddingMap = response['embedding'] as Map<String, dynamic>;
      final embeddingValues = (embeddingMap['values'] as List).cast<num>();

      _validateDimension(embeddingValues.length);

      return embeddingValues.map((numValue) => numValue.toDouble()).toList();
    } on EmbeddingServiceException {
      rethrow;
    } catch (e) {
      throw EmbeddingServiceException(
        'Failed to generate embedding',
        cause: e,
      );
    }
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    if (texts.isEmpty) return [];

    _validateApiKey();

    // If no HTTP client, fall back to sequential individual calls
    // (which will each validate and potentially throw)
    if (_httpClient == null) {
      final sequentialEmbeddings = <List<double>>[];
      for (final text in texts) {
        sequentialEmbeddings.add(await generate(text));
      }
      return sequentialEmbeddings;
    }

    try {
      final url = '$_baseUrl/models/$_model:batchEmbedContents?key=$_apiKey';
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'requests': texts
            .map((text) => {
                  'model': 'models/$_model',
                  'content': {
                    'parts': [
                      {'text': text}
                    ]
                  }
                })
            .toList(),
      });

      final responseBody = await _httpClient!(url, headers, body);
      final response = jsonDecode(responseBody) as Map<String, dynamic>;

      _checkForApiError(response);

      final embeddingEntries = response['embeddings'] as List;
      final batchEmbeddings = <List<double>>[];

      for (final embeddingEntry in embeddingEntries) {
        final embeddingValues =
            ((embeddingEntry as Map<String, dynamic>)['values'] as List).cast<num>();
        _validateDimension(embeddingValues.length);
        batchEmbeddings.add(embeddingValues.map((numValue) => numValue.toDouble()).toList());
      }

      return batchEmbeddings;
    } on EmbeddingServiceException {
      rethrow;
    } catch (e) {
      throw EmbeddingServiceException(
        'Failed to generate batch embeddings',
        cause: e,
      );
    }
  }

  void _validateApiKey() {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw EmbeddingServiceException(
        'GEMINI_API_KEY not configured. '
        'Pass apiKey to constructor or use --dart-define=GEMINI_API_KEY=your-key at build time.',
      );
    }
  }

  void _validateHttpClient() {
    if (_httpClient == null) {
      throw EmbeddingServiceException(
        'HTTP client not configured. '
        'Inject an httpClient function to make API calls.',
      );
    }
  }

  void _validateDimension(int actual) {
    if (actual != EmbeddingService.dimension) {
      throw EmbeddingServiceException(
        'Unexpected embedding dimension: $actual '
        '(expected ${EmbeddingService.dimension})',
      );
    }
  }

  void _checkForApiError(Map<String, dynamic> response) {
    if (response.containsKey('error')) {
      final error = response['error'] as Map<String, dynamic>;
      throw EmbeddingServiceException(
        'Gemini API error: ${error['message']}',
      );
    }
  }
}
