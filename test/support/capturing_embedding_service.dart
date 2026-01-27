import 'package:everything_stack_template/services/embedding_service.dart';

/// Wraps an EmbeddingService to capture all generated embeddings.
/// Used in smoke test to record embeddings for later replay in CI tests.
class CapturingEmbeddingService extends EmbeddingService {
  final EmbeddingService innerService;
  final Function(String, List<double>) onCapture;

  CapturingEmbeddingService({
    required this.innerService,
    required this.onCapture,
  });

  @override
  Future<List<double>> generate(String text) async {
    final embedding = await innerService.generate(text);
    onCapture(text, embedding);
    return embedding;
  }

  @override
  Future<void> initialize() => innerService.initialize();

  @override
  void dispose() => innerService.dispose();
}
