import 'dart:math' as math;

import '../embedding_service.dart';
import 'chunk.dart';
import 'chunking_config.dart';
import 'chunking_strategy.dart';
import 'sentence_splitter.dart';

/// Semantic chunking strategy using embedding similarity
///
/// **Algorithm:**
///
/// 1. Split text into sentences (or sliding windows if unpunctuated)
/// 2. Generate embeddings for each sentence/window using batch API
/// 3. Calculate cosine similarity between adjacent segments
/// 4. Detect topic boundaries where similarity drops below threshold
/// 5. Group segments into chunks within min/max size guardrails
/// 6. Apply size constraints while respecting semantic boundaries
///
/// **Configuration:**
///
/// The algorithm accepts a [ChunkingConfig] that controls:
/// - Window size and overlap for unpunctuated text
/// - Min/max chunk sizes and similarity threshold
/// - Supports two-level chunking (parent and child) with different configs
///
/// **Example:**
///
/// ```dart
/// // Parent-level: Broad topic boundaries, larger chunks
/// final parentChunker = SemanticChunker(
///   config: ChunkingConfig.parent(),
/// );
///
/// // Child-level: Fine-grained boundaries, smaller chunks
/// final childChunker = SemanticChunker(
///   config: ChunkingConfig.child(),
/// );
/// ```
///
/// **Use Case Alignment:**
///
/// Optimized for unstructured content:
/// - Voice transcriptions, stream-of-consciousness notes
/// - Rambling text without clear boundaries
/// - Research shows 70% retrieval improvement over recursive
///
/// **Performance:**
///
/// - ~100ms per 2000-word note (with remote embedding API)
/// - Bulk operations inherently slow; users expect this
/// - Optimize for retrieval quality, not chunking speed
class SemanticChunker implements ChunkingStrategy {
  final EmbeddingService _embeddingService;
  final ChunkingConfig config;

  SemanticChunker({
    EmbeddingService? embeddingService,
    ChunkingConfig? config,
    // Legacy parameters for backwards compatibility
    double? similarityThreshold,
    int? targetChunkSize,
    int? minChunkSize,
    int? maxChunkSize,
  }) : _embeddingService = embeddingService ?? EmbeddingService.instance,
       config = config ??
           _buildLegacyConfig(
             similarityThreshold: similarityThreshold,
             targetChunkSize: targetChunkSize,
             minChunkSize: minChunkSize,
             maxChunkSize: maxChunkSize,
           );

  /// Build ChunkingConfig from legacy parameters (for backwards compatibility)
  static ChunkingConfig _buildLegacyConfig({
    double? similarityThreshold,
    int? targetChunkSize,
    int? minChunkSize,
    int? maxChunkSize,
  }) {
    return ChunkingConfig.parent(
      similarityThreshold: similarityThreshold ?? 0.5,
      windowSize: 200,
      overlap: 50,
      minChunkSize: minChunkSize ?? 128,
      maxChunkSize: maxChunkSize ?? 400,
    );
  }

  // Convenience getters for backwards compatibility
  double get similarityThreshold => config.similarityThreshold;
  int get minChunkSize => config.minChunkSize;
  int get maxChunkSize => config.maxChunkSize;

  @override
  String get name => 'semantic';

  @override
  Future<List<Chunk>> chunk(String text) async {
    if (text.trim().isEmpty) {
      return [];
    }

    // Step 1: Split into sentences or windows using config parameters
    final segments = SentenceSplitter.split(
      text,
      windowSize: config.windowSize,
      overlap: config.overlap,
    );

    if (segments.isEmpty) {
      return [];
    }

    // Handle single segment (very short text)
    if (segments.length == 1) {
      final segment = segments.first;
      if (segment.tokenCount < config.minChunkSize) {
        // Text is too short to chunk - return as single chunk
        return [
          Chunk(
            text: segment.text,
            startToken: segment.startToken,
            endToken: segment.endToken,
          )
        ];
      }
    }

    // Step 2: Generate embeddings for all segments in batch
    final segmentTexts = segments.map((s) => s.text).toList();
    final embeddings = await _embeddingService.generateBatch(segmentTexts);

    // Step 3: Calculate similarity between adjacent segments
    final similarities = <double>[];
    for (int i = 0; i < embeddings.length - 1; i++) {
      final similarity =
          EmbeddingService.cosineSimilarity(embeddings[i], embeddings[i + 1]);
      similarities.add(similarity);
    }

    // Step 4: Detect topic boundaries (similarity drops + size limits)
    final boundaries = _detectBoundaries(similarities, segments);

    // Step 5: Group segments into chunks based on boundaries and target size
    final chunks = _createChunks(segments, boundaries);

    // Step 6: Recalculate token positions to ensure sequential, non-overlapping chunks
    // This is necessary because sliding windows may overlap
    final normalizedChunks = _normalizeTokenPositions(chunks);

    return normalizedChunks;
  }

  /// Normalize token positions to be sequential and non-overlapping
  ///
  /// When using sliding windows with overlap, chunks may inherit overlapping
  /// token positions. This method recalculates positions based on actual
  /// token counts to ensure chunks are properly sequential.
  ///
  /// Additionally enforces maxChunkSize as a hard limit - if recounting reveals
  /// a chunk exceeds the maximum, it splits the chunk.
  List<Chunk> _normalizeTokenPositions(List<Chunk> chunks) {
    if (chunks.isEmpty) return chunks;

    final normalized = <Chunk>[];
    int currentPosition = 0;

    for (final chunk in chunks) {
      final tokenCount = SentenceSplitter.countTokens(chunk.text);

      // Check if chunk exceeds maximum after normalization
      if (tokenCount > config.maxChunkSize) {
        // Split this chunk further
        final tokens = SentenceSplitter.tokenize(chunk.text);
        int start = 0;

        while (start < tokens.length) {
          final end = (start + config.maxChunkSize).clamp(0, tokens.length);
          final chunkTokens = tokens.sublist(start, end);
          final chunkText = chunkTokens.join(' ');

          normalized.add(Chunk(
            text: chunkText,
            startToken: currentPosition,
            endToken: currentPosition + chunkTokens.length,
            embedding: chunk.embedding,
          ));

          currentPosition += chunkTokens.length;
          start = end;
        }
      } else {
        // Chunk is within bounds
        normalized.add(Chunk(
          text: chunk.text,
          startToken: currentPosition,
          endToken: currentPosition + tokenCount,
          embedding: chunk.embedding,
        ));
        currentPosition += tokenCount;
      }
    }

    return normalized;
  }

  /// Detect topic boundaries from similarity scores
  ///
  /// A boundary exists between segments i and i+1 if:
  /// 1. Similarity drops below threshold (semantic boundary), OR
  /// 2. Adding next segment would exceed maxChunkSize (size boundary)
  ///
  /// This ensures we respect both semantic coherence AND size guardrails.
  List<int> _detectBoundaries(
    List<double> similarities,
    List<TextSegment> segments,
  ) {
    final boundaries = <int>[];
    int currentChunkTokens = segments.first.tokenCount;

    for (int i = 0; i < similarities.length; i++) {
      final nextSegmentTokens = segments[i + 1].tokenCount;

      // Check if we should create a boundary
      final semanticBoundary = similarities[i] < config.similarityThreshold;
      final sizeBoundary = currentChunkTokens + nextSegmentTokens > config.maxChunkSize;

      if (semanticBoundary || sizeBoundary) {
        boundaries.add(i + 1); // Boundary is AFTER index i
        currentChunkTokens = nextSegmentTokens; // Start new chunk
      } else {
        currentChunkTokens += nextSegmentTokens;
      }
    }

    return boundaries;
  }

  /// Create chunks from segments and boundaries
  ///
  /// Groups consecutive segments into chunks while:
  /// - Respecting detected topic boundaries
  /// - Targeting optimal chunk size per config
  /// - Enforcing min/max guardrails
  List<Chunk> _createChunks(List<TextSegment> segments, List<int> boundaries) {
    final chunks = <Chunk>[];
    int chunkStart = 0;

    // Add final boundary at end
    final allBoundaries = [...boundaries, segments.length];

    for (final boundaryIndex in allBoundaries) {
      // Collect segments for this chunk
      final chunkSegments = segments.sublist(chunkStart, boundaryIndex);

      if (chunkSegments.isEmpty) continue;

      // Calculate total tokens in chunk
      final totalTokens = chunkSegments.fold<int>(
        0,
        (sum, seg) => sum + seg.tokenCount,
      );

      // Check if chunk needs splitting due to size
      if (totalTokens > config.maxChunkSize) {
        // Split large chunk into smaller chunks
        chunks.addAll(_splitLargeChunk(chunkSegments));
      } else if (totalTokens < config.minChunkSize && chunks.isNotEmpty) {
        // Merge small chunk with previous chunk
        final lastChunk = chunks.removeLast();
        final mergedSegments = [
          TextSegment(
            text: lastChunk.text,
            startToken: lastChunk.startToken,
            endToken: lastChunk.endToken,
          ),
          ...chunkSegments,
        ];
        chunks.add(_mergeSegments(mergedSegments));
      } else {
        // Chunk size is within bounds - create chunk
        chunks.add(_mergeSegments(chunkSegments));
      }

      chunkStart = boundaryIndex;
    }

    return chunks;
  }

  /// Split a large chunk into smaller chunks
  ///
  /// When a semantic chunk exceeds maxChunkSize, split it into smaller chunks
  /// respecting the minChunkSize and maxChunkSize guardrails.
  /// This maintains semantic coherence while respecting size guardrails.
  List<Chunk> _splitLargeChunk(List<TextSegment> segments) {
    final chunks = <Chunk>[];
    final buffer = <TextSegment>[];
    int bufferTokens = 0;

    for (final segment in segments) {
      final wouldExceedMax = bufferTokens + segment.tokenCount > config.maxChunkSize;
      final wouldExceedMin = bufferTokens + segment.tokenCount >= config.minChunkSize;

      // Hard limit: Never exceed maxChunkSize
      // Soft limit: Split when we hit minimum size unless it's the first segment
      if (bufferTokens > 0 && (wouldExceedMax || (wouldExceedMin && bufferTokens >= config.minChunkSize))) {
        // Create chunk from buffer
        chunks.add(_mergeSegments(buffer));
        buffer.clear();
        bufferTokens = 0;
      }

      buffer.add(segment);
      bufferTokens += segment.tokenCount;
    }

    // Add remaining segments as final chunk
    if (buffer.isNotEmpty) {
      chunks.add(_mergeSegments(buffer));
    }

    return chunks;
  }

  /// Merge multiple segments into a single chunk
  ///
  /// Combines segment texts and tracks token positions from first to last segment.
  Chunk _mergeSegments(List<TextSegment> segments) {
    if (segments.isEmpty) {
      throw ArgumentError('Cannot merge empty segments');
    }

    if (segments.length == 1) {
      final seg = segments.first;
      return Chunk(
        text: seg.text,
        startToken: seg.startToken,
        endToken: seg.endToken,
      );
    }

    // Join segment texts with space
    final text = segments.map((s) => s.text).join(' ');

    // Token positions span from first segment start to last segment end
    final startToken = segments.first.startToken;
    final endToken = segments.last.endToken;

    return Chunk(
      text: text,
      startToken: startToken,
      endToken: endToken,
    );
  }
}
