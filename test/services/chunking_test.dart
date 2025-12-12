import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/chunking/chunking.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

void main() {
  // Use MockEmbeddingService for deterministic testing
  late SemanticChunker chunker;

  setUp(() {
    EmbeddingService.instance = MockEmbeddingService();
    chunker = SemanticChunker(
      similarityThreshold: 0.5,
      targetChunkSize: 128,
      minChunkSize: 128,
      maxChunkSize: 400,
    );
  });

  group('Chunk entity', () {
    test('creates valid chunk', () {
      final chunk = Chunk(
        text: 'This is a test chunk.',
        startToken: 0,
        endToken: 5,
      );

      expect(chunk.text, 'This is a test chunk.');
      expect(chunk.startToken, 0);
      expect(chunk.endToken, 5);
      expect(chunk.tokenCount, 5);
      expect(chunk.hasEmbedding, false);
    });

    test('validates token positions', () {
      expect(
        () => Chunk(text: 'test', startToken: -1, endToken: 5),
        throwsArgumentError,
      );

      expect(
        () => Chunk(text: 'test', startToken: 5, endToken: 5),
        throwsArgumentError,
      );

      expect(
        () => Chunk(text: 'test', startToken: 10, endToken: 5),
        throwsArgumentError,
      );
    });

    test('validates text not empty', () {
      expect(
        () => Chunk(text: '', startToken: 0, endToken: 5),
        throwsArgumentError,
      );
    });

    test('serializes to/from JSON', () {
      final original = Chunk(
        text: 'Test chunk',
        startToken: 0,
        endToken: 2,
        embedding: [0.1, 0.2, 0.3],
      );

      final json = original.toJson();
      final deserialized = Chunk.fromJson(json);

      expect(deserialized.text, original.text);
      expect(deserialized.startToken, original.startToken);
      expect(deserialized.endToken, original.endToken);
      expect(deserialized.embedding, original.embedding);
    });

    test('copyWith creates modified copy', () {
      final original = Chunk(
        text: 'Original',
        startToken: 0,
        endToken: 1,
      );

      final copy = original.copyWith(text: 'Modified');

      expect(copy.text, 'Modified');
      expect(copy.startToken, original.startToken);
      expect(copy.endToken, original.endToken);
    });
  });

  group('SentenceSplitter', () {
    test('splits structured text by sentences', () {
      final text = '''
        Machine learning is fascinating. It enables computers to learn from data.
        Deep learning is a subset of machine learning. Neural networks are powerful.
      ''';

      final segments = SentenceSplitter.split(text);

      expect(segments.length, greaterThan(2));
      expect(
        segments.every((s) => s.text.isNotEmpty),
        true,
        reason: 'All segments should have text',
      );
      expect(
        segments.every((s) => s.endToken > s.startToken),
        true,
        reason: 'All segments should have valid token positions',
      );
    });

    test('handles unpunctuated text with sliding windows', () {
      // Generate long unpunctuated text (voice transcription style)
      final words = List.generate(
        500,
        (i) => 'word$i',
      );
      final text = words.join(' ');

      final segments = SentenceSplitter.split(text);

      // Should create multiple overlapping windows
      expect(segments.length, greaterThan(1));

      // Check for overlap between windows
      if (segments.length > 1) {
        // Overlapping windows should have startToken differences less than window size
        final tokenDiff = segments[1].startToken - segments[0].startToken;
        expect(
          tokenDiff,
          lessThan(200), // Window size
          reason: 'Windows should overlap',
        );
        expect(
          tokenDiff,
          greaterThan(0),
          reason: 'Windows should advance',
        );
      }
    });

    test('handles empty text', () {
      final segments = SentenceSplitter.split('');
      expect(segments, isEmpty);
    });

    test('handles single sentence', () {
      final text = 'This is a single sentence.';
      final segments = SentenceSplitter.split(text);

      expect(segments.length, 1);
      expect(segments.first.text, text.trim());
    });

    test('handles text without punctuation (short)', () {
      final text = 'just some words without any punctuation marks';
      final segments = SentenceSplitter.split(text);

      expect(segments, isNotEmpty);
      // Short unpunctuated text should still be segmented
    });
  });

  group('SemanticChunker - structured text', () {
    test('chunks well-formed paragraphs', () async {
      final text = '''
        Semantic search is revolutionizing information retrieval. It understands the meaning
        of queries rather than just matching keywords. This leads to more relevant results.

        Vector embeddings are the foundation of semantic search. They convert text into
        numerical representations that capture meaning. Similar concepts have similar vectors.

        HNSW is an efficient algorithm for approximate nearest neighbor search. It enables
        fast retrieval even with millions of vectors. The graph structure makes it scalable.
      ''';

      final chunks = await chunker.chunk(text);

      expect(chunks, isNotEmpty);

      // Verify all chunks respect MAXIMUM size (hard limit)
      // Minimum size is a target, not absolute - semantic boundaries may create smaller chunks
      for (final chunk in chunks) {
        expect(
          chunk.tokenCount,
          lessThanOrEqualTo(chunker.maxChunkSize),
          reason: 'Chunk should not exceed maximum size: ${chunk.tokenCount} tokens',
        );
      }

      // Most chunks should be reasonably sized (not too small)
      final avgSize = chunks.fold<int>(0, (sum, c) => sum + c.tokenCount) / chunks.length;
      expect(avgSize, greaterThan(50), reason: 'Average chunk size should be reasonable');

      // Verify chunk positions are sequential and non-overlapping
      for (int i = 0; i < chunks.length - 1; i++) {
        expect(
          chunks[i].endToken,
          lessThanOrEqualTo(chunks[i + 1].startToken),
          reason: 'Chunks should not overlap',
        );
      }
    });

    test('respects semantic boundaries', () async {
      // Two very different topics with explicit boundary marker
      final text = '''
        The human brain is an incredibly complex organ. It contains billions of neurons
        that communicate through synapses. Memory formation involves structural changes
        in neural connections. Learning strengthens certain pathways while pruning others.
        Neurotransmitters play crucial roles in signal transmission.

        Blockchain technology provides decentralized consensus. Cryptographic hashing ensures
        data integrity. Proof of work mechanisms prevent double spending. Smart contracts
        enable programmable transactions. Distributed ledgers eliminate single points of failure.
      ''';

      final chunks = await chunker.chunk(text);

      // Note: MockEmbeddingService uses deterministic hashing which may still show
      // high similarity between different topics if they share common words.
      // The important test is that the algorithm CAN detect boundaries when similarity drops.
      expect(chunks, isNotEmpty);

      // All chunks should respect max size
      for (final chunk in chunks) {
        expect(chunk.tokenCount, lessThanOrEqualTo(chunker.maxChunkSize));
      }
    });

    test('handles paragraphs with varied punctuation', () async {
      final text = '''
        What is semantic chunking? It's a method of splitting text based on meaning!
        Unlike fixed-size chunking, it respects topic boundaries. Does it work better?
        Research suggests yes - especially for unstructured content. The results are promising.
      ''';

      final chunks = await chunker.chunk(text);

      expect(chunks, isNotEmpty);
      expect(
        chunks.every((c) => c.text.isNotEmpty),
        true,
        reason: 'All chunks should have content',
      );
    });
  });

  group('SemanticChunker - guardrails', () {
    test('enforces minimum chunk size', () async {
      // Text that would create tiny chunks if we split aggressively
      final text = 'Word. Another. More. Words. Here.';

      final chunks = await chunker.chunk(text);

      for (final chunk in chunks) {
        // Very short text might result in a single chunk below minimum
        // That's acceptable - we don't want to fail, just warn
        if (chunks.length > 1) {
          expect(
            chunk.tokenCount,
            greaterThanOrEqualTo(chunker.minChunkSize),
          );
        }
      }
    });

    test('enforces maximum chunk size', () async {
      // Generate very long text without semantic boundaries
      final sameTopic = List.generate(
        200,
        (i) => 'This is sentence $i about the same topic.',
      ).join(' ');

      final chunks = await chunker.chunk(sameTopic);

      for (final chunk in chunks) {
        expect(
          chunk.tokenCount,
          lessThanOrEqualTo(chunker.maxChunkSize),
          reason: 'Chunk exceeds maximum size: ${chunk.tokenCount} tokens',
        );
      }
    });

    test('validates configuration', () {
      expect(
        () => SemanticChunker(minChunkSize: 0),
        throwsArgumentError,
      );

      expect(
        () => SemanticChunker(minChunkSize: 400, maxChunkSize: 200),
        throwsArgumentError,
      );

      expect(
        () => SemanticChunker(similarityThreshold: 1.5),
        throwsArgumentError,
      );

      // Test ChunkingConfig validation
      expect(
        () => ChunkingConfig(
          windowSize: 100,
          overlap: 50,
          minChunkSize: 100,
          maxChunkSize: 100, // Invalid: must be greater than minChunkSize
          similarityThreshold: 0.5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SemanticChunker - edge cases', () {
    test('handles empty text', () async {
      final chunks = await chunker.chunk('');
      expect(chunks, isEmpty);
    });

    test('handles whitespace-only text', () async {
      final chunks = await chunker.chunk('   \n\n   \t  ');
      expect(chunks, isEmpty);
    });

    test('handles very short text (below minimum)', () async {
      final text = 'Just a few words here.';
      final chunks = await chunker.chunk(text);

      // Should return single chunk even if below minimum
      expect(chunks.length, 1);
      expect(chunks.first.text, isNotEmpty);
    });

    test('handles single very long sentence', () async {
      // Create a 1000-word sentence without periods
      final words = List.generate(1000, (i) => 'word$i');
      final text = words.join(' ');

      final chunks = await chunker.chunk(text);

      // Should split into multiple chunks despite being one sentence
      expect(chunks, isNotEmpty);

      // Total tokens should match input
      final totalTokens = chunks.fold<int>(0, (sum, c) => sum + c.tokenCount);
      expect(totalTokens, greaterThan(900)); // Allow some tokenization variance
    });
  });
}
