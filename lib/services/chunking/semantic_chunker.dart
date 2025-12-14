import 'package:everything_stack_template/services/embedding_service.dart';
import 'chunk.dart';
import 'chunking_config.dart';
import 'chunking_strategy.dart';
import 'sentence_splitter.dart';

/// Semantic chunking implementation that detects topic boundaries in text.
///
/// Uses embedding similarity to identify where topics change, creating semantically
/// coherent chunks. Supports configurable window sizes and overlap for two-level
/// chunking (parent level for broad topics, child level for fine-grained units).
///
/// ## Key Features
///
/// - **Adaptive text handling**: Detects structured vs unstructured (unpunctuated) text
/// - **Configurable granularity**: Parent/child presets for different retrieval levels
/// - **Sliding windows**: For unpunctuated text (voice transcriptions)
/// - **Soft + hard limits**: Respects semantic boundaries while enforcing size guardrails
/// - **Batch embedding**: Uses EmbeddingService for efficient API usage
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

    // Step 1: Segment text (sentences or sliding windows)
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
            text: chunkText,
            startToken: globalPos,
            endToken: globalPos + chunkTokens,
          ));
          globalPos += chunkTokens;
        }
        return chunks;
      }
      
      return [Chunk(text: text, startToken: 0, endToken: tokenCount)];
    }

    // Step 2: Generate embeddings for all segments
    final embeddings = await _embeddingService.generateBatch(segments);

    // Step 3: Calculate similarity between adjacent segments
    final similarities = _calculateSimilarities(embeddings);

    // Step 4: Detect topic boundaries based on similarity drops
    final boundaries = _detectBoundaries(similarities);

    // Step 5: Group segments into chunks
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

      // Create chunk if we hit a boundary or size limit
      if ((hasBoundary || wouldExceed) && currentSegments.isNotEmpty) {
        final chunkText = currentSegments.join(' ');
        final chunkTokens = SentenceSplitter.countTokens(chunkText);

        // Only create chunk if it meets minimum size (soft limit)
        if (chunkTokens >= config.minChunkSize || chunks.isEmpty) {
          chunks.add(Chunk(
            text: chunkText,
            startToken: globalTokenPosition,
            endToken: globalTokenPosition + chunkTokens,
          ));
          globalTokenPosition += chunkTokens;
          currentSegments.clear();
          currentTokens = 0;
        }
      }

      // Add segment to current chunk
      currentSegments.add(segments[i]);
      currentTokens += segmentTokens;
    }

    // Handle remaining segments
    if (currentSegments.isNotEmpty) {
      final chunkText = currentSegments.join(' ');
      final chunkTokens = SentenceSplitter.countTokens(chunkText);

      // Merge small chunk with previous if possible
      if (chunkTokens < config.minChunkSize && chunks.isNotEmpty) {
        final lastChunk = chunks.removeLast();
        final mergedText = '${lastChunk.text} $chunkText';
        final mergedTokens = SentenceSplitter.countTokens(mergedText);
        chunks.add(Chunk(
          text: mergedText,
          startToken: lastChunk.startToken,
          endToken: lastChunk.startToken + mergedTokens,
        ));
      } else {
        chunks.add(Chunk(
          text: chunkText,
          startToken: globalTokenPosition,
          endToken: globalTokenPosition + chunkTokens,
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
        // Split oversized chunk
        final tokens = chunk.text.split(' ').where((t) => t.isNotEmpty).toList();
        int chunkStart = chunk.startToken;
        
        for (int i = 0; i < tokens.length; i += config.maxChunkSize) {
          final end = (i + config.maxChunkSize).clamp(0, tokens.length);
          final splitText = tokens.sublist(i, end).join(' ');
          final splitTokens = end - i;
          
          result.add(Chunk(
            text: splitText,
            startToken: chunkStart,
            endToken: chunkStart + splitTokens,
          ));
          chunkStart += splitTokens;
        }
      }
    }
    
    return result;
  }
}
