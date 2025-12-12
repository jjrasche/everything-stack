# ChunkingConfig Quick Start Guide

## TL;DR

```dart
// Parent level: Broad topics, larger chunks
final parentChunker = SemanticChunker(
  config: ChunkingConfig.parent(),
);
final parentChunks = await parentChunker.chunk(text);

// Child level: Fine-grained, smaller chunks
final childChunker = SemanticChunker(
  config: ChunkingConfig.child(),
);
for (final parentChunk in parentChunks) {
  final childChunks = await childChunker.chunk(parentChunk.text);
}
```

---

## Configuration Presets

### Parent Level Configuration

**Use case:** Document structure, topic transitions, first-pass retrieval

```dart
ChunkingConfig.parent(
  windowSize: 200,          // Coarse topic detection
  overlap: 50,              // 25% overlap
  minChunkSize: 128,        // Minimum context
  maxChunkSize: 400,        // Hard limit
  similarityThreshold: 0.5, // Balanced boundary detection
)
```

**Results:**
- ~6 chunks from 50 paragraphs
- Average: 383 tokens
- Range: 300-400 tokens

**When to use:**
- Document-level structure
- Topic transitions
- Broad semantic grouping

---

### Child Level Configuration

**Use case:** Precise semantic units, query-level retrieval, fine-grained search

```dart
ChunkingConfig.child(
  windowSize: 30,           // Granular topic detection
  overlap: 10,              // 33% overlap
  minChunkSize: 10,         // Light minimum
  maxChunkSize: 60,         // Strict limit
  similarityThreshold: 0.5, // Balanced boundary detection
)
```

**Results:**
- ~74 chunks from 6 parent chunks
- Average: 46 tokens
- Range: 20-60 tokens

**When to use:**
- Query-level retrieval
- Precise semantic units
- Granular search results

---

## Create Custom Configuration

```dart
final customConfig = ChunkingConfig(
  windowSize: 100,          // Customize window size
  overlap: 25,              // Customize overlap
  minChunkSize: 50,         // Customize minimum
  maxChunkSize: 150,        // Customize maximum
  similarityThreshold: 0.55, // Customize threshold
  name: 'my-config',        // Give it a name
);

final chunker = SemanticChunker(config: customConfig);
```

---

## Parameter Tuning Tips

### Window Size

- **Smaller (30-50):** More segments to analyze → finer topic boundaries → more chunks
- **Larger (150-200):** Fewer segments to analyze → coarser topic boundaries → fewer chunks

**Choose based on:**
- Content type: Use 30-50 for voice transcriptions, 150-200 for structured docs
- Desired chunk count: Need fewer chunks? Use larger windows

### Overlap

- **Standard:** 10-25% of window size
- **No overlap (0):** Faster, but may miss boundaries at window edges
- **High overlap (>50%):** More thorough, but slower and more overlapping segments

**Recommendation:** 25% of window size (e.g., window=100 → overlap=25)

### Chunk Size Guardrails

- **Min chunk size:** Ensure chunks have sufficient context
  - Too small: Insufficient context for retrieval
  - Too large: Defeats the purpose of min limit
  - Typical: 10-50 for child, 100-150 for parent

- **Max chunk size:** Hard limit on chunk size
  - Too small: May split important concepts
  - Too large: Dilutes relevance
  - Typical: 60-100 for child, 300-400 for parent

### Similarity Threshold

- **Lower (0.3-0.4):** Stricter boundaries → more chunks
  - Use when: Content has many subtle topic shifts

- **Higher (0.6-0.7):** Looser boundaries → fewer chunks
  - Use when: Content has clear topic boundaries

- **Standard (0.5):** Balanced
  - Good starting point

---

## Practical Examples

### Example 1: Chunking a Voice Transcription

```dart
// Voice transcriptions have rambling, unpunctuated text
// Use smaller windows to detect topic boundaries better

final config = ChunkingConfig(
  windowSize: 50,        // Smaller windows for rambling speech
  overlap: 15,
  minChunkSize: 20,
  maxChunkSize: 100,
  similarityThreshold: 0.5,
  name: 'voice-transcript',
);

final chunker = SemanticChunker(config: config);
final chunks = await chunker.chunk(voiceTranscriptionText);
```

### Example 2: Hierarchical Chunking for Search

```dart
// First pass: Group by major topics
final parentChunks = await SemanticChunker(
  config: ChunkingConfig.parent(),
).chunk(text);

// Second pass: Find precise chunks within topics
final searchResults = <Chunk>[];
for (final parentChunk in parentChunks) {
  final childChunks = await SemanticChunker(
    config: ChunkingConfig.child(),
  ).chunk(parentChunk.text);

  searchResults.addAll(childChunks);
}

// Now you have precise chunks sorted by parent topic
```

### Example 3: Strict Chunking for Classification

```dart
// Want very precise, uniform chunks for classification
final config = ChunkingConfig(
  windowSize: 40,
  overlap: 10,
  minChunkSize: 30,
  maxChunkSize: 50,      // Strict limit for uniformity
  similarityThreshold: 0.6, // Stricter boundaries
  name: 'classification',
);

final chunker = SemanticChunker(config: config);
```

---

## Comparing Configurations

Run benchmarks to compare:

```dart
final configs = [
  ChunkingConfig.child(),
  ChunkingConfig.parent(),
  ChunkingConfig.child().copyWith(similarityThreshold: 0.7),
];

for (final config in configs) {
  final chunker = SemanticChunker(config: config);
  final chunks = await chunker.chunk(text);

  print('${config.name}: ${chunks.length} chunks, '
        'avg ${chunks.map((c) => c.tokenCount).reduce((a, b) => a + b) ~/ chunks.length} tokens');
}
```

---

## Common Mistakes

### ❌ Mistake 1: Window size too small for unpunctuated text

```dart
// BAD: Window too small for long monologues
final config = ChunkingConfig(
  windowSize: 10,  // Too small!
  minChunkSize: 5,
  maxChunkSize: 20,
);
```

**Fix:**
```dart
// GOOD: Reasonable window for unpunctuated text
final config = ChunkingConfig(
  windowSize: 50,   // Adequate segmentation
  minChunkSize: 10,
  maxChunkSize: 80,
);
```

### ❌ Mistake 2: Min size too close to max size

```dart
// BAD: No room for flexibility
final config = ChunkingConfig(
  minChunkSize: 100,
  maxChunkSize: 110,  // Only 10 token range!
);
```

**Fix:**
```dart
// GOOD: Reasonable range
final config = ChunkingConfig(
  minChunkSize: 50,
  maxChunkSize: 150,  // 100 token range for flexibility
);
```

### ❌ Mistake 3: Overlap larger than window size

```dart
// BAD: Invalid overlap
final config = ChunkingConfig(
  windowSize: 100,
  overlap: 150,  // ERROR: overlap >= windowSize
);
```

**Fix:**
```dart
// GOOD: Valid overlap
final config = ChunkingConfig(
  windowSize: 100,
  overlap: 25,  // 25% of window size
);
```

---

## Performance Notes

- **Chunking speed:** ~20-30ms per level (with MockEmbeddingService)
- **With real API:** Add ~100ms network latency per chunking level
- **Memory:** ~2-5MB per 1000 tokens of embeddings
- **Scaling:** Linear with text size and chunk count

---

## Backwards Compatibility

Old code still works without changes:

```dart
// This still works (builds parent config internally)
final chunker = SemanticChunker(
  minChunkSize: 128,
  maxChunkSize: 400,
  similarityThreshold: 0.5,
);
```

No migration needed unless you want to use new features.

---

## Testing Your Configuration

```dart
test('measure my config performance', () async {
  final config = ChunkingConfig(
    windowSize: 75,
    overlap: 20,
    minChunkSize: 40,
    maxChunkSize: 120,
    similarityThreshold: 0.55,
    name: 'my-config',
  );

  final chunker = SemanticChunker(config: config);
  final chunks = await chunker.chunk(testText);

  // Verify results
  expect(chunks.every((c) => c.tokenCount <= 120), true);
  expect(chunks.every((c) => c.text.isNotEmpty), true);

  // Print stats
  final sizes = chunks.map((c) => c.tokenCount).toList();
  final avg = sizes.reduce((a, b) => a + b) / sizes.length;
  print('${config.name}: ${chunks.length} chunks, avg $avg tokens');
});
```

---

## When to Use Two-Level Chunking

**Use two-level when you need:**
- ✅ Document structure understanding
- ✅ Both broad and fine-grained retrieval
- ✅ Hierarchical search results
- ✅ Topic-aware chunk grouping

**Use single-level when:**
- ✅ Simple uniform chunking is fine
- ✅ Performance is critical
- ✅ You don't need document structure

---

## Next Steps

1. Choose your configuration (parent, child, or custom)
2. Test on real data
3. Measure retrieval quality (precision, recall, MRR)
4. Adjust threshold and window size based on results
5. Consider two-level chunking for complex documents

See `docs/CHUNKING_CONFIG_REFACTOR.md` for detailed documentation.
