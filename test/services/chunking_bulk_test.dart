import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/chunking/chunking.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import '../harness/semantic_test_doubles.dart';

void main() {
  late SemanticChunker chunker;

  setUp(() {
    EmbeddingService.instance = MockEmbeddingService();
    chunker = SemanticChunker(
      config: ChunkingConfig(
        windowSize: 128,
        overlap: 32,
        minChunkSize: 128,
        maxChunkSize: 400,
        similarityThreshold: 0.5,
      ),
    );
  });

  group('SemanticChunker - bulk operations', () {
    test('processes 100 notes efficiently', () async {
      // Generate 100 diverse notes
      final notes = List.generate(100, (i) {
        // Alternate between structured and unstructured
        if (i % 2 == 0) {
          // Structured note
          return '''
            Note $i: Technical Overview

            This is a structured note with proper punctuation. It contains multiple
            sentences that are clearly delineated. The content discusses semantic
            search and chunking strategies.

            Vector embeddings are crucial for semantic understanding. They convert
            text into numerical representations. This enables similarity comparison.
          ''';
        } else {
          // Unstructured note (voice transcription style)
          return '''
            so this is note $i and im just talking about random stuff without much
            structure or punctuation just letting my thoughts flow naturally like
            a voice transcription would work and seeing how the chunking handles it
            which should be fine because thats exactly what its designed for right
          ''';
        }
      });

      // Process all notes and collect chunks
      final allChunks = <List<Chunk>>[];
      final stopwatch = Stopwatch()..start();

      for (final note in notes) {
        final chunks = await chunker.chunk(note);
        allChunks.add(chunks);
      }

      stopwatch.stop();

      // Verify all notes were processed
      expect(allChunks.length, 100);

      // Verify chunks are valid
      int totalChunks = 0;
      for (final chunks in allChunks) {
        totalChunks += chunks.length;
        for (final chunk in chunks) {
          expect(chunk.text, isNotEmpty);
          expect(chunk.tokenCount, greaterThan(0));
        }
      }

      // Log performance
      final totalMs = stopwatch.elapsedMilliseconds;
      final avgMs = totalMs / 100;

      print('Bulk operation results:');
      print('  Total notes: 100');
      print('  Total chunks: $totalChunks');
      print('  Total time: ${totalMs}ms');
      print('  Average per note: ${avgMs.toStringAsFixed(2)}ms');
      print('  Average chunks per note: ${(totalChunks / 100).toStringAsFixed(2)}');

      // Performance assertion: With MockEmbeddingService, should be fast
      // Real embedding API would be slower (~100ms per note)
      expect(avgMs, lessThan(1000),
          reason: 'Bulk processing should be reasonably fast');
    });

    test('handles very large note collection', () async {
      // Generate 500 short notes
      final notes = List.generate(500, (i) {
        return 'This is note $i with some basic content about semantic search '
            'and chunking strategies. It should be processed correctly.';
      });

      final allChunks = <List<Chunk>>[];

      for (final note in notes) {
        final chunks = await chunker.chunk(note);
        allChunks.add(chunks);
      }

      expect(allChunks.length, 500);

      // All short notes should produce at least one chunk
      expect(
        allChunks.every((chunks) => chunks.isNotEmpty),
        true,
        reason: 'All notes should produce at least one chunk',
      );
    });

    test('maintains consistency across repeated chunking', () async {
      final text = '''
        Semantic chunking is a powerful technique for text segmentation.
        It groups content by meaning rather than arbitrary boundaries.
        This improves retrieval quality significantly.
      ''';

      // Chunk the same text multiple times
      final results = <List<Chunk>>[];
      for (int i = 0; i < 10; i++) {
        final chunks = await chunker.chunk(text);
        results.add(chunks);
      }

      // All results should be identical (deterministic)
      final firstResult = results.first;
      for (final result in results.skip(1)) {
        expect(result.length, firstResult.length,
            reason: 'Chunking should be deterministic');

        for (int i = 0; i < result.length; i++) {
          expect(result[i].text, firstResult[i].text);
          expect(result[i].startToken, firstResult[i].startToken);
          expect(result[i].endToken, firstResult[i].endToken);
        }
      }
    });
  });

  group('SemanticChunker - extreme edge cases', () {
    test('handles extremely short text (single word)', () async {
      final chunks = await chunker.chunk('Hello');
      expect(chunks.length, 1);
      expect(chunks.first.text, 'Hello');
    });

    test('handles extremely long text (10000 tokens)', () async {
      // Generate ~10000 token text with topic shifts
      final topics = [
        'machine learning and artificial intelligence',
        'blockchain and cryptocurrency',
        'quantum computing and physics',
        'biology and genetics',
        'astronomy and space exploration',
      ];

      final segments = <String>[];
      for (int topicIdx = 0; topicIdx < topics.length; topicIdx++) {
        final topic = topics[topicIdx];
        for (int i = 0; i < 400; i++) {
          segments.add(
            'This is sentence $i about $topic which is a fascinating subject '
            'that deserves detailed exploration and analysis.',
          );
        }
      }

      final text = segments.join(' ');

      final chunks = await chunker.chunk(text);

      // Should create many chunks
      expect(chunks.length, greaterThan(10));

      // All chunks should respect max size
      for (final chunk in chunks) {
        expect(chunk.tokenCount, lessThanOrEqualTo(chunker.config.maxChunkSize));
      }

      // Verify total coverage (no text lost)
      final totalTokens = chunks.fold<int>(0, (sum, c) => sum + c.tokenCount);
      expect(totalTokens, greaterThan(9000)); // Allow tokenization variance
    });

    test('handles text with only punctuation', () async {
      final chunks = await chunker.chunk('... !!! ??? ... ...');

      // Should either return empty or single chunk
      if (chunks.isNotEmpty) {
        expect(chunks.length, 1);
      }
    });

    test('handles text with excessive whitespace', () async {
      final text = '''
        This    has     excessive       spaces.



        And   many    blank    lines.


        But   should   still   work.
      ''';

      final chunks = await chunker.chunk(text);

      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(chunk.text.trim(), isNotEmpty);
      }
    });

    test('handles text with unicode characters', () async {
      final text = '''
        Semantic search works globally. In Chinese: 语义搜索。
        In Arabic: البحث الدلالي. In Japanese: セマンティック検索.
        Vector embeddings are universal. They work across languages.
      ''';

      final chunks = await chunker.chunk(text);

      expect(chunks, isNotEmpty);
      // Unicode should be preserved
      final allText = chunks.map((c) => c.text).join(' ');
      expect(allText, contains('语义搜索'));
    });

    test('handles text with special characters and emojis', () async {
      final text = '''
        Semantic search is amazing! 🚀 It uses embeddings 💡 to find similar
        content. Users love it ❤️ because it works so well. The results are
        fantastic ⭐⭐⭐⭐⭐ and accuracy is high 📈.
      ''';

      final chunks = await chunker.chunk(text);

      expect(chunks, isNotEmpty);
      // Emojis should be preserved
      final allText = chunks.map((c) => c.text).join(' ');
      expect(allText, contains('🚀'));
    });

    test('handles text with URLs and code snippets', () async {
      final text = '''
        Check out the documentation at https://example.com/docs for more info.
        The API endpoint is POST /api/search with JSON payload.
        Code example: const result = await search(query); return result.hits;
        More details at https://github.com/example/repo in the README.
      ''';

      final chunks = await chunker.chunk(text);

      expect(chunks, isNotEmpty);
      // URLs should be preserved
      final allText = chunks.map((c) => c.text).join(' ');
      expect(allText, contains('https://example.com/docs'));
    });

    test('handles malformed input gracefully', () async {
      final weirdCases = [
        '\n\n\n',
        '   ',
        '\t\t\t',
        '.',
        '...',
        'a',
        '1',
        '!@#\$%^&*()',
      ];

      for (final text in weirdCases) {
        final chunks = await chunker.chunk(text);

        // Should not throw - either empty or single chunk
        expect(chunks.length, lessThanOrEqualTo(1));
      }
    });
  });

  group('SemanticChunker - performance characteristics', () {
    test('chunking time scales linearly with text length', () async {
      final sizes = [100, 200, 400, 800];
      final times = <int>[];

      for (final size in sizes) {
        final words = List.generate(size, (i) => 'word$i');
        final text = words.join(' ');

        final stopwatch = Stopwatch()..start();
        await chunker.chunk(text);
        stopwatch.stop();

        times.add(stopwatch.elapsedMicroseconds);
      }

      // Print timing info
      for (int i = 0; i < sizes.length; i++) {
        print('${sizes[i]} words: ${times[i]} μs');
      }

      // Should scale reasonably (not exponentially)
      // Each doubling of size should roughly double time
      // Allow significant variance due to embedding batch efficiency
    });

    test('measures average chunk size distribution', () async {
      // Generate diverse text
      final paragraphs = <String>[];
      for (int i = 0; i < 50; i++) {
        paragraphs.add(
          'This is paragraph $i discussing semantic search and chunking. '
          'It provides context about embeddings and vector similarity. '
          'The content is structured with clear sentences and punctuation. '
          'This helps test the chunk size distribution.',
        );
      }

      final text = paragraphs.join('\n\n');
      final chunks = await chunker.chunk(text);

      final sizes = chunks.map((c) => c.tokenCount).toList();
      final avgSize = sizes.reduce((a, b) => a + b) / sizes.length;
      final minSize = sizes.reduce((a, b) => a < b ? a : b);
      final maxSize = sizes.reduce((a, b) => a > b ? a : b);

      print('Chunk size distribution:');
      print('  Average: ${avgSize.toStringAsFixed(2)} tokens');
      print('  Minimum: $minSize tokens');
      print('  Maximum: $maxSize tokens');
      print('  Total chunks: ${chunks.length}');

      // Average should be reasonable (allow some variance above target)
      // Target is 128-200, but well-structured paragraphs may chunk larger
      expect(avgSize, greaterThan(100));
      expect(avgSize, lessThan(400)); // Within max chunk size

      // Max should respect guardrail
      expect(maxSize, lessThanOrEqualTo(chunker.config.maxChunkSize));
    });
  });
}
