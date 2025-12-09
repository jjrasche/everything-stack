/// # EmbeddingService
/// 
/// ## What it does
/// Generates vector embeddings from text. Used by Embeddable entities
/// to enable semantic search.
/// 
/// ## Implementation options
/// 1. On-device: Run embedding model locally (privacy, offline)
/// 2. Cloud API: Call embedding API (simpler, requires network)
/// 3. Hybrid: Cache embeddings locally, regenerate via API when needed
/// 
/// ## Current implementation
/// Stub - replace with actual embedding generation.
/// 
/// Recommended models:
/// - all-MiniLM-L6-v2: 384 dimensions, good quality/speed balance
/// - all-mpnet-base-v2: 768 dimensions, higher quality
/// - text-embedding-ada-002: OpenAI API, 1536 dimensions
/// 
/// ## Usage
/// ```dart
/// final embedding = await EmbeddingService.generate('search query');
/// final similarity = EmbeddingService.cosineSimilarity(a, b);
/// ```

class EmbeddingService {
  /// Embedding dimension - must match model output
  static const int dimension = 384; // all-MiniLM-L6-v2
  
  /// Generate embedding for text.
  /// Returns vector of length [dimension].
  static Future<List<double>> generate(String text) async {
    // TODO: Implement actual embedding generation
    // Options:
    // 1. On-device with tensorflow_lite or onnx_runtime
    // 2. API call to OpenAI, Cohere, etc.
    // 3. Self-hosted model via HTTP
    
    // Stub: return random vector for development
    // REMOVE THIS IN PRODUCTION
    return List.generate(
      dimension,
      (i) => (text.hashCode + i).toDouble() / 1000000000,
    );
  }
  
  /// Calculate cosine similarity between two embeddings.
  /// Returns value between -1 (opposite) and 1 (identical).
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
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
  
  /// Batch generate embeddings for multiple texts.
  /// More efficient than individual calls for API-based implementations.
  static Future<List<List<double>>> generateBatch(List<String> texts) async {
    // TODO: Implement batch generation for efficiency
    return Future.wait(texts.map(generate));
  }
}

// Math helper
double sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
