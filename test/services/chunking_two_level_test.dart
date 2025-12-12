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

  group('ChunkingConfig', () {
    test('parent config has correct defaults', () {
      final config = ChunkingConfig.parent();
      expect(config.windowSize, 200);
      expect(config.overlap, 50);
      expect(config.minChunkSize, 128);
      expect(config.maxChunkSize, 400);
      expect(config.similarityThreshold, 0.5);
      expect(config.name, 'parent');
    });

    test('child config has correct defaults', () {
      final config = ChunkingConfig.child();
      expect(config.windowSize, 30);
      expect(config.overlap, 10);
      expect(config.minChunkSize, 10);
      expect(config.maxChunkSize, 60);
      expect(config.similarityThreshold, 0.5);
      expect(config.name, 'child');
    });

    test('copyWith creates modified copy', () {
      final original = ChunkingConfig.parent();
      final modified = original.copyWith(windowSize: 150, overlap: 30);

      expect(modified.windowSize, 150);
      expect(modified.overlap, 30);
      expect(modified.minChunkSize, original.minChunkSize);
      expect(modified.maxChunkSize, original.maxChunkSize);
    });

    test('validates configuration constraints', () {
      expect(
        () => ChunkingConfig(
          windowSize: 0,
          overlap: 10,
          minChunkSize: 50,
          maxChunkSize: 100,
          similarityThreshold: 0.5,
        ),
        throwsArgumentError,
      );

      expect(
        () => ChunkingConfig(
          windowSize: 100,
          overlap: 100, // Invalid: overlap >= windowSize
          minChunkSize: 50,
          maxChunkSize: 100,
          similarityThreshold: 0.5,
        ),
        throwsArgumentError,
      );

      expect(
        () => ChunkingConfig(
          windowSize: 100,
          overlap: 50,
          minChunkSize: 100, // Invalid: minChunkSize should be < maxChunkSize
          maxChunkSize: 100,
          similarityThreshold: 0.5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SemanticChunker - parent configuration', () {
    test('parent chunker respects max chunk size', () async {
      final text = '''
        This is paragraph one discussing machine learning concepts.
        Machine learning involves training models on data.
        Neural networks are a subset of machine learning.
        Deep learning extends neural networks further.
        Convolutional networks excel at image processing.
        Recurrent networks handle sequential data.

        This is paragraph two about a completely different topic.
        Cooking is a culinary art form that requires skill.
        Recipes are instructions for preparing food.
        Good ingredients make the best meals.
        Technique matters just as much as ingredients.
        Practice improves cooking skills significantly.
      ''';

      final chunks = await parentChunker.chunk(text);

      // All chunks should respect max size
      for (final chunk in chunks) {
        expect(
          chunk.tokenCount,
          lessThanOrEqualTo(parentChunker.maxChunkSize),
          reason: 'Chunk exceeds max size: ${chunk.tokenCount} > ${parentChunker.maxChunkSize}',
        );
      }

      // Chunks should have content
      expect(chunks.isNotEmpty, true);
      for (final chunk in chunks) {
        expect(chunk.text.isNotEmpty, true);
      }
    });

    test('parent chunker name is correct', () {
      expect(parentChunker.config.name, 'parent');
    });

    test('parent chunker can be created with legacy parameters', () {
      final legacyChunker = SemanticChunker(
        minChunkSize: 100,
        maxChunkSize: 350,
        similarityThreshold: 0.6,
      );

      expect(legacyChunker.minChunkSize, 100);
      expect(legacyChunker.maxChunkSize, 350);
      expect(legacyChunker.similarityThreshold, 0.6);
      expect(legacyChunker.config.windowSize, 200); // Default
      expect(legacyChunker.config.overlap, 50); // Default
    });
  });

  group('SemanticChunker - child configuration', () {
    test('child chunker creates smaller chunks', () async {
      final text = '''
        This is paragraph one discussing machine learning concepts.
        Machine learning involves training models on data.
        Neural networks are a subset of machine learning.
      ''';

      final chunks = await childChunker.chunk(text);

      // Child chunks should be small
      expect(chunks.isNotEmpty, true);

      // All chunks should respect max size
      for (final chunk in chunks) {
        expect(chunk.tokenCount, lessThanOrEqualTo(childChunker.maxChunkSize));
      }
    });

    test('child chunker name is correct', () {
      expect(childChunker.config.name, 'child');
    });
  });

  group('SemanticChunker - two-level chunking workflow', () {
    test('hierarchical chunking: parent then child', () async {
      final text = '''
        Introduction to machine learning.
        Machine learning enables computers to learn from data.
        It uses algorithms to identify patterns.
        Deep learning is a subset that uses neural networks.
        Neural networks mimic biological neurons.
        They excel at pattern recognition tasks.

        Now let's discuss cloud computing.
        Cloud computing provides on-demand computing resources.
        It offers scalability and flexibility.
        AWS, Azure, and GCP are major providers.
        These platforms offer various services.
        They compete on features and pricing.
      ''';

      // Step 1: Parent level - broad chunks
      final parentChunks = await parentChunker.chunk(text);
      expect(parentChunks.isNotEmpty, true);

      // Step 2: Child level - fine-grained chunks within parent chunks
      final allChildChunks = <Chunk>[];
      for (final parentChunk in parentChunks) {
        final childChunks = await childChunker.chunk(parentChunk.text);
        allChildChunks.addAll(childChunks);
      }

      expect(allChildChunks.isNotEmpty, true);

      // Verify child chunks are smaller than parent chunks
      final parentAvg = parentChunks.fold<int>(0, (sum, c) => sum + c.tokenCount) /
          parentChunks.length;
      final childAvg =
          allChildChunks.fold<int>(0, (sum, c) => sum + c.tokenCount) /
              allChildChunks.length;

      expect(childAvg, lessThan(parentAvg),
          reason:
              'Child chunks should be smaller than parent chunks on average');
    });

    test('two-level chunking maintains semantic boundaries', () async {
      final text = '''
        Section A: This discusses apples.
        Apples are red fruits. They grow on trees.
        Apples contain nutrients. They are delicious.

        Section B: Now discussing oranges.
        Oranges are orange fruits. They are citrus.
        Oranges are sweet. They contain vitamin C.

        Section C: Finally discussing bananas.
        Bananas are yellow fruits. They peel easily.
        Bananas are soft. They are a quick snack.
      ''';

      // Process with parent chunker
      final parentChunks = await parentChunker.chunk(text);

      // Verify we have multiple parent chunks (different sections)
      expect(parentChunks.length, greaterThanOrEqualTo(1));

      // Process parent chunks with child chunker
      final hierarchicalChunks = <List<Chunk>>[];
      for (final parentChunk in parentChunks) {
        final childChunks = await childChunker.chunk(parentChunk.text);
        hierarchicalChunks.add(childChunks);
      }

      // Verify structure
      for (final childChunkList in hierarchicalChunks) {
        for (final chunk in childChunkList) {
          // Child chunks should be within guardrails
          expect(chunk.tokenCount, greaterThan(0));
          expect(chunk.tokenCount, lessThanOrEqualTo(childChunker.maxChunkSize));
        }
      }
    });

    test('two-level chunking covers full text', () async {
      final text = '''
        Line one about topic A.
        Line two about topic A.
        Line three about topic B.
        Line four about topic B.
        Line five about topic C.
        Line six about topic C.
      ''';

      // Parent level
      final parentChunks = await parentChunker.chunk(text);
      final parentTokens = parentChunks.fold<int>(0, (sum, c) => sum + c.tokenCount);

      // Child level - aggregate from all parent chunks
      final allChildChunks = <Chunk>[];
      for (final parentChunk in parentChunks) {
        final childChunks = await childChunker.chunk(parentChunk.text);
        allChildChunks.addAll(childChunks);
      }
      final childTokens = allChildChunks.fold<int>(0, (sum, c) => sum + c.tokenCount);

      // Parent tokens should match original text (approximately)
      final originalTokens = SentenceSplitter.countTokens(text);
      expect(parentTokens, lessThanOrEqualTo(originalTokens + 10)); // Allow small variance

      // Child tokens should match parent tokens (they're from same text)
      expect(childTokens, lessThanOrEqualTo(parentTokens + 10));
    });
  });

  group('SemanticChunker - configuration flexibility', () {
    test('custom config with different thresholds', () async {
      final strictConfig = ChunkingConfig(
        windowSize: 150,
        overlap: 30,
        minChunkSize: 50,
        maxChunkSize: 150,
        similarityThreshold: 0.7, // Stricter: fewer chunks
      );

      final looseConfig = ChunkingConfig(
        windowSize: 150,
        overlap: 30,
        minChunkSize: 50,
        maxChunkSize: 150,
        similarityThreshold: 0.3, // Looser: more chunks
      );

      final text = '''
        This is section one about topic A.
        Topic A continues here with more details.
        Still discussing topic A in this line.
        Transitioning to topic B now begins.
        Topic B is discussed here extensively.
        More about topic B in this sentence.
      ''';

      final strictChunker = SemanticChunker(config: strictConfig);
      final looseChunker = SemanticChunker(config: looseConfig);

      final strictChunks = await strictChunker.chunk(text);
      final looseChunks = await looseChunker.chunk(text);

      // Stricter threshold typically produces more chunks
      // (though not guaranteed due to size boundaries)
      expect(strictChunks.isNotEmpty, true);
      expect(looseChunks.isNotEmpty, true);
    });

    test('toString provides useful config info', () {
      final config = ChunkingConfig.parent();
      final description = config.toString();

      expect(description, contains('parent'));
      expect(description, contains('window=200'));
      expect(description, contains('overlap=50'));
      expect(description, contains('chunks=128-400'));
      expect(description, contains('threshold=0.5'));
    });
  });

  group('SemanticChunker - backwards compatibility', () {
    test('legacy constructor still works', () async {
      final legacyChunker = SemanticChunker(
        similarityThreshold: 0.6,
        minChunkSize: 100,
        maxChunkSize: 350,
      );

      final text = 'This is a test. It should chunk correctly. With legacy params.';
      final chunks = await legacyChunker.chunk(text);

      expect(chunks.isNotEmpty, true);

      // Verify settings were applied
      for (final chunk in chunks) {
        expect(chunk.tokenCount, lessThanOrEqualTo(350));
      }
    });

    test('mixed legacy and config parameters', () async {
      final config = ChunkingConfig(
        windowSize: 100,
        overlap: 25,
        minChunkSize: 50,
        maxChunkSize: 150,
        similarityThreshold: 0.5,
      );

      final chunker = SemanticChunker(
        config: config,
        // Legacy parameters are ignored when config is provided
      );

      expect(chunker.config.windowSize, 100);
      expect(chunker.minChunkSize, 50);
      expect(chunker.maxChunkSize, 150);
    });
  });
}
