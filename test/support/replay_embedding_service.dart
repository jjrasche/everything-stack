import 'package:everything_stack_template/services/embedding_service.dart';

/// Replays captured embeddings from smoke test.
/// Falls back to mock generation if text not in captured set.
class ReplayEmbeddingService extends EmbeddingService {
  final Map<String, List<double>> capturedEmbeddings;

  ReplayEmbeddingService({required this.capturedEmbeddings});

  @override
  Future<List<double>> generate(String text) async {
    // Return captured embedding if available
    if (capturedEmbeddings.containsKey(text)) {
      return capturedEmbeddings[text]!;
    }

    // Fallback: simple hash-based mock (for unexpected text)
    print('⚠️ No captured embedding for: "$text" - using fallback');
    return _mockEmbedding(text);
  }

  List<double> _mockEmbedding(String text) {
    final hash = text.hashCode;
    return List.generate(384, (i) => ((hash + i) % 1000) / 1000.0);
  }

  @override
  Future<void> initialize() async {
    // No-op
  }

  @override
  void dispose() {
    // No-op
  }
}
