import 'dart:io';
import 'package:everything_stack_template/services/chunking/chunking.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

/// Benchmarking script for semantic chunking performance
///
/// Run with: dart run benchmarks/chunking_benchmark.dart
///
/// Measures:
/// - Time to chunk 2000-word notes (punctuated and unpunctuated)
/// - Average chunk count per 1000-token note
/// - Average chunk size distribution
/// - Bulk operation performance (100 notes)
void main() async {
  // Use MockEmbeddingService for consistent, fast benchmarks
  // Real embedding API would add network latency (~100ms per note)
  EmbeddingService.instance = MockEmbeddingService();

  final chunker = SemanticChunker(
    similarityThreshold: 0.5,
    targetChunkSize: 128,
    minChunkSize: 128,
    maxChunkSize: 400,
  );

  print('=== Semantic Chunking Performance Benchmark ===\n');
  print('Configuration:');
  print('  Target chunk size: ${chunker.targetChunkSize} tokens');
  print('  Min chunk size: ${chunker.minChunkSize} tokens');
  print('  Max chunk size: ${chunker.maxChunkSize} tokens');
  print('  Similarity threshold: ${chunker.similarityThreshold}');
  print('  Embedding service: MockEmbeddingService (no network latency)\n');

  // Benchmark 1: 2000-word punctuated note
  await _benchmark1(chunker);

  // Benchmark 2: 2000-word unpunctuated note
  await _benchmark2(chunker);

  // Benchmark 3: Average chunk count per 1000-token note
  await _benchmark3(chunker);

  // Benchmark 4: Chunk size distribution
  await _benchmark4(chunker);

  // Benchmark 5: Bulk operations (100 notes)
  await _benchmark5(chunker);

  print('\n=== Benchmark Complete ===');
}

/// Benchmark 1: 2000-word punctuated note
Future<void> _benchmark1(SemanticChunker chunker) async {
  print('--- Benchmark 1: 2000-word Punctuated Note ---');

  // Generate 2000-word structured note with clear paragraphs
  final paragraphs = List.generate(20, (i) => '''
    Paragraph $i discusses semantic search and vector embeddings. It contains
    multiple sentences that are clearly delineated with punctuation. The content
    covers topics like HNSW indexing, cosine similarity, and retrieval quality.
    Each paragraph is approximately 100 words long to reach our target of 2000 words.
    This structured format represents well-written notes with proper grammar.
  ''');

  final text = paragraphs.join('\n\n');
  final wordCount = text.split(RegExp(r'\s+')).length;

  // Warm-up run
  await chunker.chunk(text);

  // Timed run
  final stopwatch = Stopwatch()..start();
  final chunks = await chunker.chunk(text);
  stopwatch.stop();

  print('  Word count: $wordCount');
  print('  Chunks generated: ${chunks.length}');
  print('  Time: ${stopwatch.elapsedMilliseconds}ms');
  print('  Average chunk size: ${_avgChunkSize(chunks).toStringAsFixed(1)} tokens');
  print('  Min chunk size: ${_minChunkSize(chunks)} tokens');
  print('  Max chunk size: ${_maxChunkSize(chunks)} tokens\n');
}

/// Benchmark 2: 2000-word unpunctuated note
Future<void> _benchmark2(SemanticChunker chunker) async {
  print('--- Benchmark 2: 2000-word Unpunctuated Note ---');

  // Generate 2000-word voice transcription style (no punctuation)
  final words = <String>[];
  for (int i = 0; i < 2000; i++) {
    words.add('word$i');
  }
  final text = words.join(' ');

  // Warm-up run
  await chunker.chunk(text);

  // Timed run
  final stopwatch = Stopwatch()..start();
  final chunks = await chunker.chunk(text);
  stopwatch.stop();

  print('  Word count: ${words.length}');
  print('  Chunks generated: ${chunks.length}');
  print('  Time: ${stopwatch.elapsedMilliseconds}ms');
  print('  Average chunk size: ${_avgChunkSize(chunks).toStringAsFixed(1)} tokens');
  print('  Min chunk size: ${_minChunkSize(chunks)} tokens');
  print('  Max chunk size: ${_maxChunkSize(chunks)} tokens\n');
}

/// Benchmark 3: Average chunk count per 1000-token note
Future<void> _benchmark3(SemanticChunker chunker) async {
  print('--- Benchmark 3: Chunk Count per 1000-Token Note ---');

  // Generate 10 different 1000-token notes
  final chunkCounts = <int>[];

  for (int n = 0; n < 10; n++) {
    final sentences = List.generate(100, (i) =>
      'This is sentence $i for note $n discussing semantic chunking and retrieval.'
    );
    final text = sentences.join(' ');

    final chunks = await chunker.chunk(text);
    chunkCounts.add(chunks.length);
  }

  final avgChunkCount = chunkCounts.reduce((a, b) => a + b) / chunkCounts.length;
  final minChunks = chunkCounts.reduce((a, b) => a < b ? a : b);
  final maxChunks = chunkCounts.reduce((a, b) => a > b ? a : b);

  print('  Sample size: 10 notes');
  print('  Tokens per note: ~1000');
  print('  Average chunks per note: ${avgChunkCount.toStringAsFixed(2)}');
  print('  Min chunks: $minChunks');
  print('  Max chunks: $maxChunks\n');
}

/// Benchmark 4: Chunk size distribution
Future<void> _benchmark4(SemanticChunker chunker) async {
  print('--- Benchmark 4: Chunk Size Distribution ---');

  // Generate diverse notes with different structures
  final allChunks = <Chunk>[];

  // Structured notes
  for (int i = 0; i < 5; i++) {
    final text = '''
      Introduction to semantic search and its applications. Vector embeddings
      enable similarity-based retrieval. HNSW indexing provides fast lookups.

      Chunking strategies affect retrieval quality significantly. Research shows
      128-token chunks achieve optimal precision. Semantic chunking outperforms
      recursive splitting for unstructured content.
    ''';
    allChunks.addAll(await chunker.chunk(text));
  }

  // Unstructured notes
  for (int i = 0; i < 5; i++) {
    final words = List.generate(500, (i) => 'word$i');
    allChunks.addAll(await chunker.chunk(words.join(' ')));
  }

  final sizes = allChunks.map((c) => c.tokenCount).toList();
  final avg = sizes.reduce((a, b) => a + b) / sizes.length;
  final min = sizes.reduce((a, b) => a < b ? a : b);
  final max = sizes.reduce((a, b) => a > b ? a : b);

  // Calculate distribution buckets
  final under128 = sizes.where((s) => s < 128).length;
  final range128to200 = sizes.where((s) => s >= 128 && s <= 200).length;
  final range201to300 = sizes.where((s) => s > 200 && s <= 300).length;
  final range301to400 = sizes.where((s) => s > 300 && s <= 400).length;
  final over400 = sizes.where((s) => s > 400).length;

  print('  Total chunks analyzed: ${allChunks.length}');
  print('  Average size: ${avg.toStringAsFixed(1)} tokens');
  print('  Min size: $min tokens');
  print('  Max size: $max tokens');
  print('');
  print('  Size distribution:');
  print('    < 128 tokens: $under128 chunks (${(under128/allChunks.length*100).toStringAsFixed(1)}%)');
  print('    128-200 tokens: $range128to200 chunks (${(range128to200/allChunks.length*100).toStringAsFixed(1)}%)');
  print('    201-300 tokens: $range201to300 chunks (${(range201to300/allChunks.length*100).toStringAsFixed(1)}%)');
  print('    301-400 tokens: $range301to400 chunks (${(range301to400/allChunks.length*100).toStringAsFixed(1)}%)');
  print('    > 400 tokens: $over400 chunks (${(over400/allChunks.length*100).toStringAsFixed(1)}%)\n');
}

/// Benchmark 5: Bulk operations (100 notes)
Future<void> _benchmark5(SemanticChunker chunker) async {
  print('--- Benchmark 5: Bulk Operations (100 Notes) ---');

  // Generate 100 diverse notes
  final notes = List.generate(100, (i) {
    if (i % 2 == 0) {
      // Structured
      return 'Note $i: This is a structured note with proper sentences. '
          'It discusses semantic search and chunking strategies. '
          'The content is clear and well-formatted with punctuation.';
    } else {
      // Unstructured
      final words = List.generate(100, (j) => 'word${i}_$j');
      return words.join(' ');
    }
  });

  // Warm-up
  await chunker.chunk(notes[0]);

  // Timed bulk operation
  final stopwatch = Stopwatch()..start();
  int totalChunks = 0;

  for (final note in notes) {
    final chunks = await chunker.chunk(note);
    totalChunks += chunks.length;
  }

  stopwatch.stop();

  final totalMs = stopwatch.elapsedMilliseconds;
  final avgMs = totalMs / notes.length;

  print('  Notes processed: ${notes.length}');
  print('  Total chunks generated: $totalChunks');
  print('  Average chunks per note: ${(totalChunks/notes.length).toStringAsFixed(2)}');
  print('  Total time: ${totalMs}ms');
  print('  Average time per note: ${avgMs.toStringAsFixed(2)}ms');
  print('  Throughput: ${(notes.length / (totalMs / 1000)).toStringAsFixed(1)} notes/sec\n');
}

// Helper functions
double _avgChunkSize(List<Chunk> chunks) {
  if (chunks.isEmpty) return 0;
  return chunks.fold<int>(0, (sum, c) => sum + c.tokenCount) / chunks.length;
}

int _minChunkSize(List<Chunk> chunks) {
  if (chunks.isEmpty) return 0;
  return chunks.map((c) => c.tokenCount).reduce((a, b) => a < b ? a : b);
}

int _maxChunkSize(List<Chunk> chunks) {
  if (chunks.isEmpty) return 0;
  return chunks.map((c) => c.tokenCount).reduce((a, b) => a > b ? a : b);
}
