import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/chunking/chunking.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

void main() {
  late SemanticChunker parentChunker;
  late SemanticChunker childChunker;

  setUp(() {
    EmbeddingService.instance = MockEmbeddingService();

    parentChunker = SemanticChunker(
      config: ChunkingConfig.parent(
        windowSize: 200,
        overlap: 50,
        minChunkSize: 128,
        maxChunkSize: 400,
        similarityThreshold: 0.5,
      ),
    );

    childChunker = SemanticChunker(
      config: ChunkingConfig.child(
        windowSize: 30,
        overlap: 10,
        minChunkSize: 10,
        maxChunkSize: 60,
        similarityThreshold: 0.5,
      ),
    );
  });

  group('Two-level chunking benchmarks', () {
    test('measures parent and child chunk size distributions', () async {
      // Generate diverse test text
      final paragraphs = <String>[];
      for (int i = 0; i < 50; i++) {
        paragraphs.add(
          'This is paragraph $i discussing semantic search and chunking. '
          'It provides context about embeddings and vector similarity. '
          'The content is structured with clear sentences and punctuation. '
          'This helps test the chunk size distribution across levels.',
        );
      }

      final text = paragraphs.join('\n\n');

      // Parent level chunking
      final stopwatch = Stopwatch()..start();
      final parentChunks = await parentChunker.chunk(text);
      stopwatch.stop();

      final parentTime = stopwatch.elapsedMilliseconds;
      final parentSizes = parentChunks.map((c) => c.tokenCount).toList();
      final parentAvg = parentSizes.reduce((a, b) => a + b) / parentSizes.length;
      final parentMin = parentSizes.reduce((a, b) => a < b ? a : b);
      final parentMax = parentSizes.reduce((a, b) => a > b ? a : b);

      print('\n=== Parent Level Chunking ===');
      print('Config: window=200, overlap=50, min=128, max=400');
      print('Chunks generated: ${parentChunks.length}');
      print('Average chunk size: ${parentAvg.toStringAsFixed(2)} tokens');
      print('Min chunk size: $parentMin tokens');
      print('Max chunk size: $parentMax tokens');
      print('Time: ${parentTime}ms');

      // Child level chunking
      final childResults = <int>[];
      stopwatch.reset();
      stopwatch.start();

      for (final parentChunk in parentChunks) {
        final childChunks = await childChunker.chunk(parentChunk.text);
        final childSizes = childChunks.map((c) => c.tokenCount).toList();
        childResults.addAll(childSizes);
      }

      stopwatch.stop();
      final childTime = stopwatch.elapsedMilliseconds;

      if (childResults.isNotEmpty) {
        final childAvg =
            childResults.reduce((a, b) => a + b) / childResults.length;
        final childMin = childResults.reduce((a, b) => a < b ? a : b);
        final childMax = childResults.reduce((a, b) => a > b ? a : b);

        print('\n=== Child Level Chunking ===');
        print('Config: window=30, overlap=10, min=10, max=60');
        print('Total chunks generated: ${childResults.length}');
        print('Average chunk size: ${childAvg.toStringAsFixed(2)} tokens');
        print('Min chunk size: $childMin tokens');
        print('Max chunk size: $childMax tokens');
        print('Time: ${childTime}ms');

        // Verify size hierarchy
        print('\n=== Size Hierarchy ===');
        print('Parent average: ${parentAvg.toStringAsFixed(2)} tokens');
        print('Child average: ${childAvg.toStringAsFixed(2)} tokens');
        print('Ratio: ${(parentAvg / childAvg).toStringAsFixed(2)}x');

        // Assertions
        expect(childAvg, lessThan(parentAvg),
            reason:
                'Child chunks should be smaller than parent chunks on average');
        expect(childMax, lessThanOrEqualTo(60),
            reason: 'Child chunks should respect max size of 60');
        expect(parentMax, lessThanOrEqualTo(400),
            reason: 'Parent chunks should respect max size of 400');
      }

      // Print distribution analysis
      print('\n=== Parent Distribution Analysis ===');
      final parentUnder128 =
          parentSizes.where((s) => s < 128).length;
      final parentTarget =
          parentSizes.where((s) => s >= 128 && s <= 200).length;
      final parentLarge =
          parentSizes.where((s) => s > 200).length;

      print('< 128 tokens: $parentUnder128 (${(parentUnder128 / parentSizes.length * 100).toStringAsFixed(1)}%)');
      print('128-200 tokens (target): $parentTarget (${(parentTarget / parentSizes.length * 100).toStringAsFixed(1)}%)');
      print('201-400 tokens: $parentLarge (${(parentLarge / parentSizes.length * 100).toStringAsFixed(1)}%)');

      if (childResults.isNotEmpty) {
        print('\n=== Child Distribution Analysis ===');
        final childUnder10 = childResults.where((s) => s < 10).length;
        final childTarget = childResults.where((s) => s >= 10 && s <= 30).length;
        final childLarge = childResults.where((s) => s > 30).length;

        print('< 10 tokens: $childUnder10 (${(childUnder10 / childResults.length * 100).toStringAsFixed(1)}%)');
        print('10-30 tokens (target): $childTarget (${(childTarget / childResults.length * 100).toStringAsFixed(1)}%)');
        print('31-60 tokens: $childLarge (${(childLarge / childResults.length * 100).toStringAsFixed(1)}%)');
      }
    });

    test('compares different window size configurations', () async {
      final text = '''
        Machine learning is transforming technology today.
        Deep learning enables complex pattern recognition tasks.
        Neural networks excel at image and language processing.
        Transformers have revolutionized natural language understanding.

        Cloud computing provides scalable on-demand resources.
        Microservices enable flexible application architecture design.
        Containers simplify deployment across different environments.
        Kubernetes orchestrates containerized workloads automatically.

        Quantum computing promises exponential speedups.
        Qubits enable superposition and entanglement capabilities.
        Quantum algorithms could break current encryption methods.
        Quantum hardware remains challenging to build and maintain.
      ''';

      final configs = [
        ChunkingConfig(
          name: 'small_window',
          windowSize: 30,
          overlap: 10,
          minChunkSize: 10,
          maxChunkSize: 60,
          similarityThreshold: 0.5,
        ),
        ChunkingConfig(
          name: 'medium_window',
          windowSize: 100,
          overlap: 25,
          minChunkSize: 50,
          maxChunkSize: 150,
          similarityThreshold: 0.5,
        ),
        ChunkingConfig(
          name: 'large_window',
          windowSize: 200,
          overlap: 50,
          minChunkSize: 128,
          maxChunkSize: 400,
          similarityThreshold: 0.5,
        ),
      ];

      print('\n=== Configuration Comparison ===\n');

      for (final config in configs) {
        final chunker = SemanticChunker(config: config);
        final chunks = await chunker.chunk(text);

        if (chunks.isNotEmpty) {
          final sizes = chunks.map((c) => c.tokenCount).toList();
          final avg = sizes.reduce((a, b) => a + b) / sizes.length;
          final min = sizes.reduce((a, b) => a < b ? a : b);
          final max = sizes.reduce((a, b) => a > b ? a : b);

          print('${config.name.padRight(15)} | '
              'chunks: ${chunks.length.toString().padLeft(2)} | '
              'avg: ${avg.toStringAsFixed(1).padLeft(5)} | '
              'min: $min | '
              'max: $max');
        }
      }
    });

    test('similarity threshold impact on chunking', () async {
      final text = '''
        This section discusses apples and oranges.
        Apples are red fruits that grow on trees.
        They contain various nutrients and vitamins.

        Oranges are citrus fruits with vitamin C.
        They have a thick peel and juicy interior.
        Citrus fruits are popular worldwide commodities.
      ''';

      final thresholds = [0.3, 0.5, 0.7];

      print('\n=== Similarity Threshold Impact ===\n');

      for (final threshold in thresholds) {
        final config = ChunkingConfig.parent(
          similarityThreshold: threshold,
        );
        final chunker = SemanticChunker(config: config);
        final chunks = await chunker.chunk(text);

        if (chunks.isNotEmpty) {
          final sizes = chunks.map((c) => c.tokenCount).toList();
          final avg = sizes.reduce((a, b) => a + b) / sizes.length;

          print('Threshold: $threshold | '
              'chunks: ${chunks.length} | '
              'avg size: ${avg.toStringAsFixed(1)} tokens');
        }
      }
    });
  });
}
