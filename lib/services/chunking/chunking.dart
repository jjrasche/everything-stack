/// Semantic chunking infrastructure for text segmentation
///
/// This module provides text chunking capabilities optimized for Everything Stack's
/// primary use case: unstructured content like voice transcriptions and stream-of-
/// consciousness notes.
///
/// ## Core Components
///
/// - [Chunk]: Represents a semantic text segment with token positions
/// - [ChunkingConfig]: Configuration for chunking behavior (window size, min/max, threshold)
/// - [ChunkingStrategy]: Interface for chunking algorithms
/// - [SemanticChunker]: Primary implementation using embedding similarity
/// - [SentenceSplitter]: Utility for sentence/window segmentation
///
/// ## Usage
///
/// **Single-level chunking (default parent config):**
/// ```dart
/// final chunker = SemanticChunker();
/// final chunks = await chunker.chunk(noteContent);
/// ```
///
/// **Two-level chunking (parent + child):**
/// ```dart
/// // Parent: Broad semantic boundaries, larger chunks
/// final parentChunker = SemanticChunker(config: ChunkingConfig.parent());
/// final parentChunks = await parentChunker.chunk(noteContent);
///
/// // Child: Fine-grained boundaries, smaller chunks
/// final childChunker = SemanticChunker(config: ChunkingConfig.child());
/// for (final parentChunk in parentChunks) {
///   final childChunks = await childChunker.chunk(parentChunk.text);
/// }
/// ```
///
/// **Custom configuration:**
/// ```dart
/// final config = ChunkingConfig(
///   windowSize: 100,
///   overlap: 25,
///   minChunkSize: 50,
///   maxChunkSize: 200,
///   similarityThreshold: 0.55,
/// );
/// final chunker = SemanticChunker(config: config);
/// ```
///
/// ## Architecture Decisions
///
/// **Why semantic chunking?**
/// - Use case alignment: Unstructured, rambling content without clear boundaries
/// - Research-backed: 70% retrieval improvement over recursive for unstructured text
/// - Marginal complexity: Reuses existing EmbeddingService infrastructure
///
/// **Why two-level chunking?**
/// - Parent level: Respects document structure, detects major topic shifts
/// - Child level: Precise semantic units within parent chunks
/// - Enables both broad and fine-grained retrieval
///
/// **Performance characteristics:**
/// - ~100ms per 2000-word note (with remote embedding API)
/// - Bulk operations are slow but acceptable for use case
/// - Quality over speed: Optimize for retrieval precision, not chunking speed
///
/// See docs/CHUNKING_ARCHITECTURE.md for full design rationale.
library chunking;

export 'chunk.dart';
export 'chunking_config.dart';
export 'chunking_strategy.dart';
export 'semantic_chunker.dart';
export 'sentence_splitter.dart';
