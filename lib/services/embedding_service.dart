/// # EmbeddingService
///
/// ## What it does
/// Generates vector embeddings from text. Used by Embeddable entities
/// to enable semantic search.
///
/// ## Architecture
/// Abstract interface with swappable implementations:
/// - MockEmbeddingService: Deterministic hash-based vectors for testing
/// - JinaEmbeddingService: Production implementation using Jina AI API
/// - GeminiEmbeddingService: Alternative using Google Gemini API
///
/// ## Usage
/// ```dart
/// // Use default instance (configured at startup)
/// final embedding = await EmbeddingService.instance.generate('query');
///
/// // Or inject specific implementation
/// EmbeddingService.instance = MockEmbeddingService();
///
/// // Batch generation for efficiency
/// final embeddings = await service.generateBatch(['a', 'b', 'c']);
///
/// // Similarity comparison
/// final score = EmbeddingService.cosineSimilarity(a, b);
/// ```
///
/// ## Configuration
/// For JinaEmbeddingService (recommended), pass the API key to constructor:
/// ```dart
/// EmbeddingService.instance = JinaEmbeddingService(apiKey: 'your-key');
/// ```
///
/// Or use compile-time environment variable (must be passed at build time):
/// ```dart
/// // Run with: flutter run --dart-define=JINA_API_KEY=your-key
/// EmbeddingService.instance = JinaEmbeddingService.fromEnvironment();
/// ```
///
/// Note: `String.fromEnvironment` is evaluated at compile time, not runtime.
/// You cannot use `export JINA_API_KEY=xxx` - it must be passed via
/// `--dart-define` during compilation.

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
  /// Must be set before any repository is used.
  static late EmbeddingService instance;

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
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Embeddings must have same dimension');
    }

    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0;

    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
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
      // Return zero vector for empty text
      return List.filled(EmbeddingService.dimension, 0.0);
    }

    // Sum word vectors
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
    return texts.map((t) => mockEmbedding(t)).toList();
  }

  /// Tokenize text into lowercase words
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Remove punctuation
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
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
    for (final v in vector) {
      sumSquares += v * v;
    }

    if (sumSquares == 0) {
      // Return arbitrary unit vector if input is zero
      return List.generate(
        vector.length,
        (i) => i == 0 ? 1.0 : 0.0,
      );
    }

    final norm = sqrt(sumSquares);
    return vector.map((v) => v / norm).toList();
  }
}
///
/// Requires API key passed to constructor or via compile-time environment.
/// Uses jina-embeddings-v3 model with Matryoshka Representation Learning
/// to output exactly 384 dimensions (matching our standard).
///
/// ## Features
/// - High quality multilingual embeddings
/// - Matryoshka dimension flexibility (32-1024)
/// - OpenAI-compatible API format
///
/// ## Rate limits
/// Check your Jina AI plan for specific limits.
///
/// ## Usage
/// ```dart
/// // Direct API key (recommended)
/// final service = JinaEmbeddingService(apiKey: 'your-key');
///
/// // Or compile-time env var (requires --dart-define at build time)
/// final service = JinaEmbeddingService.fromEnvironment();
///
/// EmbeddingService.instance = service;
/// ```
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

      final data = response['data'] as List;
      final results = <List<double>>[];

      // Sort by index to ensure correct order
      final sortedData = List<Map<String, dynamic>>.from(
        data.map((e) => e as Map<String, dynamic>),
      )..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

      for (final item in sortedData) {
        final embedding = (item['embedding'] as List).cast<num>();
        _validateDimension(embedding.length);
        results.add(embedding.map((v) => v.toDouble()).toList());
      }

      return results;
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
    // Jina returns error in 'detail' field
    if (response.containsKey('detail')) {
      throw EmbeddingServiceException(
        'Jina API error: ${response['detail']}',
      );
    }
    // Also check for standard 'error' field
    if (response.containsKey('error')) {
      final error = response['error'];
      final message = error is Map ? error['message'] : error.toString();
      throw EmbeddingServiceException(
        'Jina API error: $message',
      );
    }
  }
}

/// Production implementation using Google Gemini API.
///
/// Requires API key passed to constructor or via compile-time environment.
/// Uses text-embedding-004 model which outputs 384-dimensional embeddings.
///
/// ## Rate limits
/// - 1500 requests per minute
/// - 1M tokens per minute
///
/// ## Security note
/// The API key is passed in the URL query string (as required by Gemini API).
/// Be aware this may be logged by proxies or monitoring tools.
///
/// ## Usage
/// ```dart
/// // Direct API key (recommended for most cases)
/// final service = GeminiEmbeddingService(apiKey: 'your-key');
///
/// // Or compile-time env var (requires --dart-define at build time)
/// final service = GeminiEmbeddingService.fromEnvironment();
///
/// EmbeddingService.instance = service;
/// ```
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

      final embedding = response['embedding'] as Map<String, dynamic>;
      final values = (embedding['values'] as List).cast<num>();

      _validateDimension(values.length);

      return values.map((v) => v.toDouble()).toList();
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
      final results = <List<double>>[];
      for (final text in texts) {
        results.add(await generate(text));
      }
      return results;
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

      final embeddings = response['embeddings'] as List;
      final results = <List<double>>[];

      for (final e in embeddings) {
        final values =
            ((e as Map<String, dynamic>)['values'] as List).cast<num>();
        _validateDimension(values.length);
        results.add(values.map((v) => v.toDouble()).toList());
      }

      return results;
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
