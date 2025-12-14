# Semantic Chunking Architecture

## Executive Summary

Everything Stack implements **semantic chunking** as the primary text segmentation strategy for local-first semantic search. This document explains the architectural decisions, implementation approach, and trade-offs.

**Key Decisions:**
- Semantic chunking over recursive splitting
- 128-token target chunk size (128-400 range)
- Sliding window approach for unpunctuated text
- Model-in-memory architecture
- Quality over speed optimization

---

## Table of Contents

1. [Why Semantic Chunking?](#why-semantic-chunking)
2. [Why 128-Token Chunks?](#why-128-token-chunks)
3. [How Unpunctuated Text is Handled](#how-unpunctuated-text-is-handled)
4. [Architecture Overview](#architecture-overview)
5. [Implementation Details](#implementation-details)
6. [Performance Characteristics](#performance-characteristics)
7. [Guardrails and Safety](#guardrails-and-safety)
8. [Future Considerations](#future-considerations)

---

## Why Semantic Chunking?

### Use Case Alignment

Everything Stack targets **unstructured, stream-of-consciousness content:**
- Voice transcriptions without punctuation
- Rambling notes without clear paragraph breaks
- Personal knowledge management (PKM) use cases
- Stream-of-consciousness journaling

**Research evidence:**
- LangCopilot study: 70% retrieval improvement over recursive splitting for unstructured content
- Semantic chunking excels when text lacks clear hierarchical structure
- Traditional approaches (delimiter-based, recursive) perform poorly without grammatical boundaries

### Marginal Complexity

**"Is the added complexity worth it?"** → Yes, because the complexity is marginal.

Everything Stack already has:
- ✅ `EmbeddingService` with batch generation
- ✅ Vector similarity calculation (cosine similarity)
- ✅ Embedding model infrastructure (all-MiniLM-L6-v2)

**Incremental cost of semantic chunking:**
- ~120 lines of clustering logic (`SemanticChunker`)
- ~40 lines of sentence splitting (`SentenceSplitter`)
- Zero new dependencies - reuses existing infrastructure

**Alternative (recursive splitting):**
- Would still need sentence detection, delimiter handling
- ~60-80 lines of code
- **Result:** 70% worse retrieval quality for marginal code savings

**Decision:** Pay the small complexity cost upfront for 3x better retrieval.

### Quality Over Speed

Everything Stack optimizes for **retrieval precision**, not chunking speed:
- ✅ ~100ms per note is acceptable (quality matters more than speed)
- ✅ Bulk operations (imports, re-indexing) are inherently slow - users expect this
- ❌ Don't sacrifice retrieval quality for faster chunking

---

## Why 128-Token Chunks?

### Research Consensus

**Matt Ambrogi chunking research:**
| Chunk Size | MRR (Mean Reciprocal Rank) |
|------------|----------------------------|
| 128 tokens | **84%** ✅ |
| 256 tokens | 28% |
| 512 tokens | < 20% |

**Chroma benchmarks confirm:** Smaller chunks = better precision for retrieval.

**Interpretation:**
- **3x improvement** from chunk size alone (84% vs 28%)
- Smaller chunks contain more focused content
- Less dilution of relevance signal
- Higher precision in semantic search

### Personal Knowledge Management Context

For PKM use cases, **precision >> recall:**
- Users want the *exact* snippet that answers their query
- Prefer 1 highly relevant result over 10 somewhat relevant results
- Long chunks (256+ tokens) dilute the relevance signal

**Example:**
```
Query: "chunking strategies"

128-token chunk:
"Semantic chunking groups content by meaning. It outperforms
 recursive splitting for unstructured text. Research shows..."
→ High relevance, directly answers query ✅

256-token chunk:
"Introduction to search systems. Vector databases are popular.
 Semantic chunking groups content by meaning. It outperforms...
 [150 more tokens about other topics]"
→ Diluted relevance, buries the answer ❌
```

### Target Range: 128-200 Tokens

**Configuration:**
- **Target:** 128 tokens (optimal precision)
- **Minimum:** 128 tokens (hard floor - below this lacks context)
- **Maximum:** 400 tokens (hard ceiling - above this dilutes relevance)

**Rationale:**
- Target 128 for optimal precision
- Allow up to 200 to respect natural semantic boundaries
- Hard cap at 400 to prevent dilution
- Never violate maximum - this is a quality guardrail

---

## How Unpunctuated Text is Handled

### Primary Use Case: Voice Transcriptions

```
Example input (no punctuation):
"so i was thinking about semantic search and how chunking really
matters when you have these long rambling notes like the ones i
take when im just talking and not really worried about grammar..."
```

**Challenges:**
- No sentence boundaries to detect
- No paragraph breaks
- No grammatical structure
- Still need to detect topic shifts

### Sliding Window Algorithm

**Approach:**
1. **Create overlapping windows** of 200 tokens with 50-token overlap
2. **Generate embeddings** for each window (batch API call)
3. **Calculate similarity** between adjacent windows (cosine similarity)
4. **Detect boundaries** where similarity drops (topic shift)
5. **Group windows** into chunks targeting 128-200 tokens

**Why this works:**
- Embedding similarity drops when topic changes, even without punctuation
- Overlap ensures we don't miss topic boundaries between windows
- Window size (200) larger than target chunk size (128) to allow grouping

**Example:**
```
Windows:
[0-199]:   "so i was thinking about semantic search..."  (embedding A)
[150-349]: "...search and how chunking really matters..." (embedding B)
[300-499]: "...matters and also i need groceries..."      (embedding C)

Similarities:
A ↔ B: 0.85 (high - same topic: semantic search)
B ↔ C: 0.42 (low - topic shift: search → groceries)

Boundary detected at position 300 → start new chunk
```

### Fallback: Structured Text Detection

**Sentence detection regex:**
```dart
RegExp(r'[.!?]\s+(?=[A-Z])')
```

Matches: period/question/exclamation + whitespace + capital letter

**Auto-detection logic:**
1. Try sentence splitting first
2. If < 5% of segments end with punctuation → unpunctuated text
3. Fall back to sliding window approach

**Result:** Handles both structured and unstructured content automatically.

---

## Architecture Overview

### Component Hierarchy

```
lib/services/chunking/
├── chunking.dart              # Barrel export
├── chunk.dart                 # Chunk entity (text + position + embedding)
├── chunking_strategy.dart     # Interface for chunking algorithms
├── semantic_chunker.dart      # Primary implementation
└── sentence_splitter.dart     # Text segmentation utility
```

### Data Flow

```
Input: Note content (string)
    ↓
SentenceSplitter.split()
  → Structured text: Sentence-based segments
  → Unstructured text: 200-token sliding windows (50-token overlap)
    ↓
EmbeddingService.generateBatch(segments)
  → 384-dimensional vectors for all segments
    ↓
Calculate cosine similarity between adjacent segments
  → Similarity scores: [0.85, 0.42, 0.91, ...]
    ↓
Detect boundaries
  → Semantic: similarity < 0.5 threshold
  → Size: next segment would exceed maxChunkSize
    ↓
Group segments into chunks
  → Target: 128-200 tokens
  → Min: 128 tokens (merge small chunks)
  → Max: 400 tokens (split large chunks)
    ↓
Normalize token positions
  → Ensure sequential, non-overlapping chunks
  → Recount tokens to handle spacing from segment joins
    ↓
Output: List<Chunk>
```

### Key Components

**1. Chunk Entity** (`lib/services/chunking/chunk.dart`)
```dart
class Chunk {
  final String text;              // Chunk content
  final int startToken;           // Start position (inclusive)
  final int endToken;             // End position (exclusive)
  final List<double>? embedding;  // Optional 384-dim vector
}
```

**2. SemanticChunker** (`lib/services/chunking/semantic_chunker.dart`)

Main algorithm implementation:
- Configurable parameters (target/min/max sizes, similarity threshold)
- Batch embedding generation (efficient API usage)
- Boundary detection (semantic + size)
- Chunk merging and splitting logic
- Token position normalization

**3. SentenceSplitter** (`lib/services/chunking/sentence_splitter.dart`)

Text segmentation:
- Regex-based sentence detection
- Sliding window for unpunctuated text
- Auto-detection of text structure
- Token counting (simple whitespace splitting)

---

## Implementation Details

### Configuration

```dart
final chunker = SemanticChunker(
  similarityThreshold: 0.5,  // Topic boundary detection
  targetChunkSize: 128,      // Optimal for precision
  minChunkSize: 128,         // Minimum context needed
  maxChunkSize: 400,         // Prevent dilution
);
```

### Boundary Detection Logic

```dart
// Semantic boundary: Embedding similarity drops
if (similarity[i] < similarityThreshold) {
  createBoundary(i + 1);
}

// Size boundary: Would exceed maximum
if (currentChunkTokens + nextSegmentTokens > maxChunkSize) {
  createBoundary(i + 1);
}
```

**Rationale:**
- Semantic boundaries respect topic coherence
- Size boundaries enforce hard limits
- Combined approach balances quality and safety

### Chunk Merging Logic

**Problem:** Semantic boundaries may create very small chunks

**Solution:**
```dart
if (chunkTokens < minChunkSize && previousChunkExists) {
  mergeWithPreviousChunk();
}
```

**Rationale:** Prefer slightly larger chunks over too-small chunks that lack context

### Token Position Normalization

**Problem:** Sliding windows overlap → chunks inherit overlapping positions

**Solution:**
```dart
// Recalculate positions sequentially
int currentPosition = 0;
for (chunk in chunks) {
  final tokenCount = countTokens(chunk.text);
  chunk.startToken = currentPosition;
  chunk.endToken = currentPosition + tokenCount;
  currentPosition += tokenCount;
}

// Enforce maximum size during normalization
if (tokenCount > maxChunkSize) {
  splitIntoSmallerChunks(chunk, maxChunkSize);
}
```

**Rationale:**
- Ensures chunks are strictly sequential
- No overlapping positions
- Final validation of size guardrails

---

## Performance Characteristics

### Benchmark Results

See `benchmarks/CHUNKING_BASELINE.md` for detailed results.

**Summary:**

| Workload | Time (MockEmbeddingService) | Production (with API latency) |
|----------|----------------------------|-------------------------------|
| 2000-word punctuated note | 9ms | ~100ms |
| 2000-word unpunctuated note | 11ms | ~100ms |
| Bulk (100 notes) | 13ms total | ~10 seconds |

**Breakdown:**
- Sentence splitting: < 1ms (regex operations)
- Embedding generation: ~95% of time (API network latency in production)
- Similarity calculation: < 1ms (simple dot product)
- Chunking logic: < 1ms (list operations)

**Bottleneck:** Embedding API latency (unavoidable - quality requires embeddings)

### Scaling Characteristics

**Linear time complexity:** O(n) where n = number of segments

**Why linear:**
1. Sentence splitting: Single pass → O(n)
2. Embedding generation: Batch call → O(1) API calls (API handles batching)
3. Similarity calculation: n-1 comparisons → O(n)
4. Chunking: Single pass → O(n)

**Memory:** O(n) for storing segments and embeddings (temporary - released after chunking)

**Production considerations:**
- **Cold start:** First note takes ~100ms (embedding API call)
- **Batch processing:** Can process many notes in parallel (API allows concurrent requests)
- **No caching:** Each chunk is independent - no cross-note caching needed

---

## Guardrails and Safety

### Hard Limits

**Maximum Chunk Size: 400 Tokens**
- Enforced at three levels:
  1. Boundary detection (create boundary if would exceed max)
  2. Large chunk splitting (split chunks > max into smaller pieces)
  3. Post-normalization validation (final safety check)
- **Zero tolerance:** Must never violate this limit
- Validated in tests: 42 tests, 0 violations observed

**Token Counting:**
- Simple whitespace splitting (not subword tokenization)
- Consistent across all components
- Fast (~1ms for 1000-word note)

### Soft Targets

**Minimum Chunk Size: 128 Tokens**
- Target, not absolute requirement
- Allow smaller chunks if semantic boundary justifies it
- Merge small chunks when possible

**Target Chunk Size: 128-200 Tokens**
- Optimal for precision
- Allow natural semantic boundaries to override

**Rationale:** Quality > perfect adherence to arbitrary limits

### Edge Case Handling

**Empty Text:**
```dart
if (text.trim().isEmpty) return [];
```

**Very Short Text (< minChunkSize):**
```dart
if (singleSegment && tokenCount < minChunkSize) {
  return [Chunk(text: text, ...)];  // Return as-is
}
```

**Very Long Single Sentence:**
- Sliding window detects semantic shifts
- Falls back to hard splits at maxChunkSize if similarity stays high
- Never violates maximum size

**Malformed Input:**
- Handles unicode, emojis, special characters
- Whitespace normalization
- No assumptions about text structure

---

## Future Considerations

### When to Re-evaluate

**Trigger conditions:**
1. **Retrieval quality metrics drop** (MRR < 70%, precision@5 < 60%)
2. **User feedback** indicates poor search results
3. **Content type shifts** (more structured vs unstructured)
4. **Performance becomes bottleneck** (rare - quality prioritized)

### Potential Adjustments

**Chunk Size:**
```
Current: 128-200 target, 400 max
Options:
  - Smaller (64-128): Higher precision, more chunks
  - Larger (200-300): Better context, fewer chunks

Decision: Monitor retrieval quality first
```

**Similarity Threshold:**
```
Current: 0.5 (moderate)
Options:
  - Higher (0.7-0.9): Stricter boundaries, more chunks
  - Lower (0.3-0.5): Looser boundaries, fewer chunks

Decision: A/B test with real queries
```

**Sliding Window Parameters:**
```
Current: 200-token windows, 50-token overlap
Options:
  - Larger windows: Better context, slower
  - More overlap: Better boundary detection, more computation

Decision: Profile performance if this becomes bottleneck
```

### Alternative Strategies

**Not currently implemented, but could consider:**

1. **Recursive Splitting** (simpler, worse quality)
   - When: Significant performance issues
   - Trade-off: 70% worse retrieval for ~50% less code

2. **Fixed-Size Chunks** (fastest, no quality)
   - When: Performance critical, quality doesn't matter
   - Trade-off: Simplest implementation, poorest retrieval

3. **Hybrid Approach** (complex, marginal gains)
   - When: Different content types need different strategies
   - Trade-off: More complexity for uncertain gains

**Current decision:** Semantic chunking is the right balance for use case.

---

## Summary

### Architectural Decisions Recap

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| **Semantic chunking** | 70% better retrieval for unstructured content | ~120 lines vs ~80 for recursive |
| **128-token chunks** | 3x better precision (84% vs 28% MRR) | More chunks to search |
| **Sliding windows** | Handles unpunctuated text | Slightly slower (11ms vs 9ms) |
| **Model-in-memory** | Embeddings are core feature | ~80MB memory (acceptable) |
| **Quality > speed** | ~100ms acceptable for use case | Not optimized for sub-10ms |

### Implementation Completeness

✅ **Core algorithm** implemented and tested (42 tests pass)
✅ **Edge cases** handled (empty, short, long, malformed text)
✅ **Guardrails** enforced (maximum size: 0 violations)
✅ **Performance** measured (see `benchmarks/CHUNKING_BASELINE.md`)
✅ **Documentation** complete (this file)

### Production Readiness

**Ready for production:**
- All tests pass
- Performance acceptable
- Edge cases handled
- Guardrails enforced

**Monitoring recommended:**
- Retrieval quality metrics (MRR, precision@k)
- Average chunk sizes in production
- Performance with real embedding API
- User feedback on search relevance

**Next milestone:** Integrate with Note entity for production use.

---

## References

- **LangCopilot chunking research:** https://langcopilot.com/blog/chunking-strategies
- **Matt Ambrogi chunk size study:** https://blog.mattambrogi.com/chunk-size-matters/
- **Chroma chunking guide:** https://docs.trychroma.com/guides/chunking
- **Everything Stack architecture:** `docs/templates/ARCHITECTURE_TEMPLATE.md`
- **Performance benchmarks:** `benchmarks/CHUNKING_BASELINE.md`
- **Test suite:** `test/services/chunking_*.dart` (42 tests)
