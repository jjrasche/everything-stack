import 'package:uuid/uuid.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';
import 'chunking_config.dart';
import 'chunking_strategy.dart';
import 'sentence_splitter.dart';

/// Detects topic boundaries via embedding similarity, creating semantically
/// coherent chunks. Supports parent/child granularity for two-level retrieval.
class SemanticChunker extends ChunkingStrategy {
  final EmbeddingService _embeddingService;
  final ChunkingConfig config;

  SemanticChunker({
    EmbeddingService? embeddingService,
    ChunkingConfig? config,
  })  : _embeddingService = embeddingService ?? EmbeddingService.instance,
        config = config ?? ChunkingConfig.parent();

  @override
  String get name => 'semantic-chunker-${config.name}';

  @override
  Future<List<Chunk>> chunk(String text) async {
    if (text.trim().isEmpty) return [];

    final segments = _segmentText(text);
    if (segments.isEmpty) return [];
    if (segments.length == 1) {
      final tokenCount = SentenceSplitter.countTokens(text);
      final chunks = <Chunk>[];

      // If single segment exceeds max, split it
      if (tokenCount > config.maxChunkSize) {
        final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
        int globalPos = 0;
        for (int i = 0; i < tokens.length; i += config.maxChunkSize) {
          final end = (i + config.maxChunkSize).clamp(0, tokens.length);
          final chunkText = tokens.sublist(i, end).join(' ');
          final chunkTokens = end - i;
          chunks.add(Chunk(
            id: const Uuid().v4(),
            sourceEntityId: '',
            sourceEntityType: '',
            text: chunkText,
            startToken: globalPos,
            endToken: globalPos + chunkTokens,
            config: 'parent',
          ));
          globalPos += chunkTokens;
        }
        return chunks;
      }

      return [
        Chunk(
          id: const Uuid().v4(),
          sourceEntityId: '',
          sourceEntityType: '',
          text: text,
          startToken: 0,
          endToken: tokenCount,
          config: 'parent',
        )
      ];
    }

    final embeddings = await _embeddingService.generateBatch(segments);

    final similarities = _calculateSimilarities(embeddings);

    final boundaries = _detectBoundaries(similarities);

    return _groupSegments(segments, boundaries);
  }

  /// Segment text into sentences (structured) or sliding windows (unstructured)
  List<String> _segmentText(String text) {
    if (SentenceSplitter.isUnstructured(text)) {
      return SentenceSplitter.slidingWindows(
        text,
        windowSize: config.windowSize,
        overlap: config.overlap,
      );
    } else {
      return SentenceSplitter.splitSentences(text);
    }
  }

  /// Calculate cosine similarity between adjacent segments
  List<double> _calculateSimilarities(List<List<double>> embeddings) {
    final similarities = <double>[];

    for (int i = 0; i < embeddings.length - 1; i++) {
      final sim = EmbeddingService.cosineSimilarity(
        embeddings[i],
        embeddings[i + 1],
      );
      similarities.add(sim);
    }

    return similarities;
  }

  /// Detect topic boundaries using similarity threshold
  ///
  /// Returns list of indices where chunks should start (after a boundary).
  List<int> _detectBoundaries(List<double> similarities) {
    final boundaries = <int>[];

    if (similarities.isEmpty) return boundaries;

    for (int i = 0; i < similarities.length; i++) {
      // Boundary if similarity drops below threshold
      if (similarities[i] < config.similarityThreshold) {
        boundaries.add(i + 1); // Boundary after segment i
      }
    }

    return boundaries;
  }

  /// Group segments into chunks based on boundaries and size limits
  List<Chunk> _groupSegments(List<String> segments, List<int> boundaries) {
    final chunks = <Chunk>[];
    var currentSegments = <String>[];
    var currentTokens = 0;
    var globalTokenPosition = 0;

    for (int i = 0; i < segments.length; i++) {
      final segmentTokens = SentenceSplitter.countTokens(segments[i]);

      // Size boundary: would exceed maxChunkSize
      final wouldExceed = currentTokens + segmentTokens > config.maxChunkSize;

      // Semantic boundary: topic change detected
      final hasBoundary = boundaries.contains(i);

      if ((hasBoundary || wouldExceed) && currentSegments.isNotEmpty) {
        final chunkText = currentSegments.join(' ');
        final chunkTokens = SentenceSplitter.countTokens(chunkText);

        // Only create chunk if it meets minimum size (soft limit)
        if (chunkTokens >= config.minChunkSize || chunks.isEmpty) {
          chunks.add(Chunk(
            id: const Uuid().v4(),
            sourceEntityId: '',
            sourceEntityType: '',
            text: chunkText,
            startToken: globalTokenPosition,
            endToken: globalTokenPosition + chunkTokens,
            config: 'parent',
          ));
          globalTokenPosition += chunkTokens;
          currentSegments.clear();
          currentTokens = 0;
        }
      }

      currentSegments.add(segments[i]);
      currentTokens += segmentTokens;
    }

    if (currentSegments.isNotEmpty) {
      final chunkText = currentSegments.join(' ');
      final chunkTokens = SentenceSplitter.countTokens(chunkText);

      if (chunkTokens < config.minChunkSize && chunks.isNotEmpty) {
        final lastChunk = chunks.removeLast();
        final mergedText = '${lastChunk.text} $chunkText';
        final mergedTokens = SentenceSplitter.countTokens(mergedText);
        chunks.add(Chunk(
          id: const Uuid().v4(),
          sourceEntityId: '',
          sourceEntityType: '',
          text: mergedText,
          startToken: lastChunk.startToken,
          endToken: lastChunk.startToken + mergedTokens,
          config: 'parent',
        ));
      } else {
        chunks.add(Chunk(
          id: const Uuid().v4(),
          sourceEntityId: '',
          sourceEntityType: '',
          text: chunkText,
          startToken: globalTokenPosition,
          endToken: globalTokenPosition + chunkTokens,
          config: 'parent',
        ));
      }
    }

    // Final pass: split any chunks that exceed maxChunkSize (hard limit enforcement)
    return _enforceSizeLimits(chunks);
  }

  /// Final pass to enforce maximum chunk size hard limit
  List<Chunk> _enforceSizeLimits(List<Chunk> chunks) {
    final result = <Chunk>[];

    for (final chunk in chunks) {
      if (chunk.tokenCount <= config.maxChunkSize) {
        result.add(chunk);
      } else {
        final tokens =
            chunk.text.split(' ').where((t) => t.isNotEmpty).toList();
        int chunkStart = chunk.startToken;

        for (int i = 0; i < tokens.length; i += config.maxChunkSize) {
          final end = (i + config.maxChunkSize).clamp(0, tokens.length);
          final splitText = tokens.sublist(i, end).join(' ');
          final splitTokens = end - i;

          result.add(Chunk(
            id: const Uuid().v4(),
            sourceEntityId: '',
            sourceEntityType: '',
            text: splitText,
            startToken: chunkStart,
            endToken: chunkStart + splitTokens,
            config: 'parent',
          ));
          chunkStart += splitTokens;
        }
      }
    }

    return result;
  }
}
