# Memory Encoder Pipeline

## Glossary

| Term | Definition |
|------|-----------|
| **Memory System** | The complete module. Encoder + working memory + knowledge store + entity resolution + consolidation. Input: episodic sources. Output: structured, entity-linked, temporally-versioned knowledge. |
| **Encoder** | The pipeline: normalize → segment → cohere → recohere → filter → decontextualize → dedup. Input: episodic source + working memory state. Output: working memory diff. Scope ends at working memory. |
| **Episodic Source** | Raw input to the encoder: a conversation turn, transcript segment, article, or any temporal unit of text. |
| **Sentence** | Atomic text unit from segmentation. Verbatim from source. Identified by `S1`, `S2`, etc. |
| **Concept Span** | One or more sentences grouped by discourse coherence. The unit that filter scores and decontext decomposes. |
| **Proposition** | Self-contained, decontextualized knowledge unit. Encoder output. Contains content + sourceIds + scope + type. No pronouns, no inline provenance. Lives in working memory. |
| **Fact** | A proposition after entity resolution and persistence. Proposition + entity links + temporal metadata. Lives in the knowledge store. Not built yet. |
| **Working Memory** | Bounded set of propositions relevant to the current processing context. Versioned via event-sourced diffs. The encoder reads from and writes to working memory. |
| **Knowledge Store** | All persisted facts with entity links and temporal metadata. Long-term memory. Append-only with supersession. Not built yet. |
| **Entity Resolution** | Links entity mentions in propositions to entities in the knowledge store. Post-encoder, converts propositions to facts. Not built yet. |
| **Working Memory Diff** | The output of one encoder run. `{added, archived, superseded, rewritten}`. Applied to working memory by the caller. |

## Pipeline Overview

```
Episodic Source → [1.Normalize] → [2.Segment] → [3.Cohere] → [4.Recohere] → [5.Filter] → [6.Decontext] → [7.Dedup] → WM Diff
                   SLM 210M        regex          SLM 110M     SLM 110M       SLM 44M      LLM 8B         SLM 22M
```

**Input**: Episodic source text + current working memory state
**Output**: Working memory diff `{added, archived, superseded, rewritten}`

---

## Stage 1: Normalize

**Question**: Is this text clean enough to segment?
**Operation**: Compute punctuation ratio (marks per word). If below threshold (AdaptationState: `punctuationRatioThreshold`), invoke SLM for punctuation restoration + truecasing. Then check for overlong sentences exceeding word limit (AdaptationState: `maxSentenceWords`, default 40). Split at coordinating conjunctions: `, and `, `, but `, `, so `, `, or ` when preceded by a subject-verb clause.

#### Input
```json
{
  "text": "so we decided to use objectbox because it supports all six platforms and the single writer model means we need queue coordination for concurrent writes"
}
```

#### Output
```json
{
  "text": "So we decided to use ObjectBox because it supports all six platforms. The single writer model means we need queue coordination for concurrent writes.",
  "punctuationNeeded": true,
  "latencyMs": 16
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Words per punctuation mark | word count / punctuation count in output | 8-20 | >30 (punctuation failed) or <3 (over-punctuated) |
| Longest sentence (words) | max word count across output sentences | 10-35 | >50 (splitting failed) |


#### Review Screen
Source text on top, normalized text on bottom. Each change (inserted punctuation, case change, split point) highlighted individually. Tab through changes one at a time: accept or reject each. Each decision = one training pair. Arrow keys to advance to next source. Instances with metrics outside healthy range surfaced first.

#### Implementation
**Model**: `1-800-BAD-CODE/punctuation_fullstop_truecase_english` (210M ONNX, SentencePiece 32k vocab).
**AdaptationState**: `punctuationRatioThreshold` (float), `maxSentenceWords` (int, default 40).

#### Training
**Fine-tuning**: Trigger: >5% correction rate across 50+ reviewed instances. Golden data: accumulated (source, corrected) pairs from review. Expected improvement: domain-specific truecasing (ObjectBox, DeBERTa, HNSW).

---

## Stage 2: Segment

**Question**: What are the atomic sentence units in this text?
**Operation**: Strip code blocks (fenced + indented), strip markdown formatting, split on sentence boundaries (`.?!`), filter fragments under minimum word count (AdaptationState: `minFragmentWords`, default 3).

#### Input
```json
{
  "text": "So we decided to use ObjectBox because it supports all six platforms. The single writer model means we need queue coordination for concurrent writes."
}
```

#### Output
```json
{
  "sentences": [
    {"id": "S1", "text": "So we decided to use ObjectBox because it supports all six platforms."},
    {"id": "S2", "text": "The single writer model means we need queue coordination for concurrent writes."}
  ],
  "latencyMs": 1
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Avg sentence length (words) | total words / sentence count | 8-25 | <4 (over-splitting) or >40 (under-splitting) |
| Sentence count | number of output sentences | 3-30 | <2 or >80 |


#### Review Screen
Source text with split boundaries marked as colored bars between sentences. Reviewer clicks a boundary to remove it, clicks between words to add one. Arrow keys to advance. Flag instances where avg sentence length is outside range.

#### Implementation
Pure regex. Deterministic. No model.
**AdaptationState**: `minFragmentWords` (int, default 3).

#### Training
No model. Rule updates only from review disagreements (e.g., abbreviation periods).

---

## Stage 3: Cohere

**Question**: Which adjacent sentences are part of the same thought?
**Operation**: Score each adjacent sentence pair for discourse continuity via pairwise SLM inference. Pairs scoring below boundary threshold (AdaptationState: `cohereBoundaryThreshold`, default 0.5) mark topic boundaries. Group consecutive same-topic sentences into concept spans. Resplit any span exceeding max sentence count (AdaptationState: `maxSpanSentences`, default 15) at weakest internal boundary below resplit threshold (AdaptationState: `resplitThreshold`, default 0.65).

#### Input
```json
{
  "sentences": [
    {"id": "S1", "text": "So we decided to use ObjectBox..."},
    {"id": "S2", "text": "The single writer model means..."},
    {"id": "S3", "text": "OK anyway what about the UI?"},
    {"id": "S4", "text": "The button placement feels wrong."}
  ]
}
```

#### Output
```json
{
  "spans": [
    {"spanId": "span_0", "sentenceIds": ["S1", "S2"]},
    {"spanId": "span_1", "sentenceIds": ["S3", "S4"]}
  ],
  "pairScores": [
    {"pair": ["S1", "S2"], "coherenceScore": 0.89, "boundary": false},
    {"pair": ["S2", "S3"], "coherenceScore": 0.31, "boundary": true},
    {"pair": ["S3", "S4"], "coherenceScore": 0.84, "boundary": false}
  ],
  "latencyMs": 9
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Words per span | span word count | 15-150 | <5 (over-fragmenting) or >300 (not splitting) |
| Sentences per span | sentence count in this span | 2-8 | 1 always (not grouping) or >15 (not splitting) |


#### Review Screen
First sentence on top, second sentence on bottom. Coherence score displayed between them. Current decision (boundary/continuation) pre-selected as tab. Reviewer switches tab to change. Left/right arrow keys to advance to next pair.

#### Implementation
**Model**: `bert-wiki-paragraphs` (110M ONNX, WordPiece tokenizer). Pairwise scoring, ~3ms/pair.
**AdaptationState**: `cohereBoundaryThreshold` (float, default 0.5), `resplitThreshold` (float, default 0.65), `maxSpanSentences` (int, default 15).

#### Training
**Fine-tuning**: Trigger: >10% correction rate across 50+ reviewed pairs. Golden data: (sentence_a, sentence_b, should_be_boundary) from review. Expected improvement: boundary F1 from ~85% to 92%+.

---

## Stage 4: Recohere

**Question**: Are there non-adjacent spans within this source that belong together?
**Operation**: Compute pairwise cosine similarity between all span embeddings. Merge pairs above merge threshold (AdaptationState: `recohereThreshold`). Handles divergent thinking where the speaker leaves a topic, discusses something else, then returns. Scope: within a single episodic source only. Cross-source knowledge accumulation is working memory's job.

**Not asking**: Whether to merge spans across different episodic sources.

#### Input
```json
{
  "spans": [
    {"spanId": "span_0", "sentenceIds": ["S1", "S2"], "text": "ObjectBox uses single-writer..."},
    {"spanId": "span_1", "sentenceIds": ["S3", "S4"], "text": "The button placement feels wrong..."},
    {"spanId": "span_2", "sentenceIds": ["S5", "S6"], "text": "Back to ObjectBox, the sync layer..."}
  ]
}
```

#### Output
```json
{
  "spans": [
    {"spanId": "span_0", "sentenceIds": ["S1", "S2", "S5", "S6"]},
    {"spanId": "span_1", "sentenceIds": ["S3", "S4"]}
  ],
  "merges": [{"merged": ["span_0", "span_2"], "similarity": 0.87}],
  "latencyMs": 15
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Merge count | merges in this source | 0-3 | >5 (cohere boundaries were poor) |
| Highest non-merged similarity | max similarity among pairs NOT merged | <threshold | near-threshold scores warrant review |


#### Review Screen
Two span texts side by side. Similarity score displayed between them. Pre-selected decision (merge/keep separate). Reviewer confirms or overrides. Arrow keys to advance. Only pairs near threshold surfaced for review.

#### Implementation
**Model**: Same `bert-wiki-paragraphs` (110M ONNX) used by cohere. Encode each span, compute pairwise cosine similarity.
O(n^2) on spans, not sentences. 10-15 spans per source = ~100 comparisons at ~3ms each = ~300ms.
**AdaptationState**: `recohereThreshold` (float).

#### Training
Shares model and training with cohere. No separate training needed.

---

## Stage 5: Filter

**Question**: Is this span anything, or is it conversational noise?
**Operation**: Compute heuristic features from span text. Run classification model on text + features. Score 0.0 (noise) to 1.0 (substantive). Compare against threshold (AdaptationState: `filterThreshold`, default 0.35). Deterministic fast-path: `wordCount < 3 AND NOT hasNamedEntity` skips without model call.

**Not asking**: Is this novel relative to working memory? (dedup). Is this a complete thought? (cohere/recohere). What type of knowledge? (decontext). Will this last? (working memory decay). Is this redundant? (dedup).

#### Input
```json
{
  "spanId": "span_3",
  "text": "ok sounds good let me think about that",
  "features": {
    "wordCount": 8,
    "sentenceCount": 1,
    "lexicalDensity": 0.0,
    "hasNamedEntity": false,
    "hasCausalMarker": false,
    "questionRatio": 0.0
  }
}
```

**Heuristic features** (computed deterministically, included as model input):

| Feature | Type | Computation | Signal |
|---------|------|-------------|--------|
| `wordCount` | int | whitespace split count | <5 with no entities = almost certainly noise |
| `sentenceCount` | int | sentence count in span | single-sentence spans more likely filler |
| `lexicalDensity` | float | content words / total words | "ok sure" = 0.0, technical text = 0.5-0.7 |
| `hasNamedEntity` | bool | capitalized multi-char tokens, code refs, technical terms | near-perfect substantiveness indicator |
| `hasCausalMarker` | bool | "because", "so that", "in order to", "therefore", "since" | explanations are inherently substantive |
| `questionRatio` | float | question sentences / total sentences | all-questions may not be decomposable alone |

#### Output
```json
{
  "spanId": "span_3",
  "score": 0.12,
  "decision": "skip",
  "latencyMs": 4
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Filter score | model output for this span | 0.0-1.0 | 0.3-0.5 (borderline, warrants review) |
| Skip rate | skipped / total spans | 5-20% | >40% (too aggressive) or 0% (not working) |


#### Evaluation Rubric (for human labeling, not runtime)
| Dimension | Question |
|-----------|----------|
| **Substantive** | Contains any claim, fact, decision, preference, or description? |
| **Specific** | Concrete enough to decompose into at least one proposition? |

Both yes = extract. Either no = skip. Frontier model applies rubric first. Human verifies disagreements and borderline cases.

#### Review Screen
Span text displayed. Filter score and decision shown. Heuristic feature values alongside. Reviewer confirms extract/skip via tab toggle. Arrow keys to advance. Borderline scores (0.3-0.5) surfaced first.

#### Implementation
**Model**: DeBERTa-v3-small (44M) with binary classification head. Input = [CLS] embedding concatenated with heuristic feature vector.
**AdaptationState**: `filterThreshold` (float, default 0.35). ↑ decontext produces 0 propositions. ↓ user flags missing knowledge from skipped span.
**Latency**: ~3-5ms per span. Fast-path skips in <1ms.

#### Training
Follows generic SLM Training Process (see section above).
- **Bootstrap**: 200+ labeled spans (stratified). SetFit contrastive fine-tune (30 sec). Target: F1 90%+.
- **Active learning**: Borderline scores (0.3-0.5) routed to review. Expected: F1 90% to 95%+ after 500 corrections.
- **Labeler**: Claude Code applies rubric directly. No external LLM calls.

---

## Stage 6: Decontextualize

**Question**: What self-contained, atomic propositions does this span express?
**Operation**: Replace pronouns and references ("it", "this approach", "that thing") with concrete entity names from the entity list. Then decompose the span into 0-N atomic propositions. Assign scope (session/project/life) and type (learning/project/exploration). Coreference resolution is the primary job. Decomposition into atomic units is the secondary job.

**Not asking**: Whether to extract this span (filter decided). Whether this is redundant (dedup decides after). What entities are mentioned (entity resolution is post-encoder).

#### Input
```json
{
  "spanId": "span_0",
  "text": "So we decided to use it because it supports all six platforms. The single writer model means we need queue coordination.",
  "surroundingContext": "...previous and next span text...",
  "entityList": ["ObjectBox", "Flutter", "Everything Stack", "Supabase"]
}
```

#### Output
```json
{
  "spanId": "span_0",
  "propositions": [
    {
      "content": "The Everything Stack project uses ObjectBox for persistence because ObjectBox supports all six target platforms.",
      "scope": "project",
      "type": "project",
      "sourceIds": ["S1"]
    },
    {
      "content": "ObjectBox uses a single-writer model that requires queue coordination for concurrent write operations.",
      "scope": "project",
      "type": "learning",
      "sourceIds": ["S2"]
    }
  ],
  "latencyMs": 800
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Propositions from this span | proposition count | 1-8 | 0 (filter should have caught) or >15 (over-decomposing) |
| Input-to-output word ratio | span words / total proposition words | 2-6x | <1.5x (copying source) or >10x (losing information) |
| Avg proposition length (words) | total proposition words / proposition count | 10-25 | <5 (fragments) or >40 (not atomic) |


#### Evaluation Rubric (for human labeling)
| Dimension | Question |
|-----------|----------|
| **Self-contained** | Understandable without the source text? No dangling pronouns or references? |
| **Atomic** | Contains exactly one claim? Could not be split further? |
| **Faithful** | Accurately represents what the source said? No hallucinated details? |
| **Complete** | All extractable knowledge from the span captured across all propositions? |

Frontier model applies rubric first. Human verifies disagreements.

#### Review Screen
Source span text on top. Propositions listed below, each with scope/type tags. Reviewer can: confirm all, flag individual propositions (not self-contained, not atomic, not faithful), mark span as incomplete (missing knowledge). Arrow keys to advance to next span.

#### Implementation
**Model**: Groq LLM (8B). **Permanent LLM stage.** Generative rewriting requires 3B+ minimum (Choi et al. 2021). Sub-1B cannot do this.
**Input per span**: target span text + 2-3 surrounding sentences + entity list from working memory (~200 tokens total).
**Per-span, not batch**: keeps context small, enables future SLM transition to T5-3B.
**Also callable from dedup**: when bidirectional entailment detected, dedup routes the pair here for canonical rewrite.

#### Training
**Stays on LLM.** Prompt optimization only. Flagged propositions drive PromptImprovementLoop.
**Future SLM**: T5-3B fine-tuned. Requires ~1000 (span, propositions) pairs.

---

## Stage 7: Dedup

**Question**: Does this proposition duplicate, contradict, or refine anything already in working memory?
**Operation**: For each new proposition, run NLI cross-encoder against every working memory proposition. Classify each pair as: no match, entailment (merge), or contradiction (supersede). On merge: route both propositions to decontext for canonical rewrite. When working memory is empty, all propositions are added directly.

**Not asking**: Whether this is substantive (filter decided). What entities are mentioned (entity resolution is post-encoder). Whether this is "important": all propositions that reach dedup have passed filter and decontext.

#### Input
```json
{
  "propositions": [
    {"content": "ObjectBox uses a single-writer model requiring queue coordination.", "sourceIds": ["S2"]}
  ],
  "workingMemory": [
    {"uuid": "p_01", "content": "ObjectBox requires queue coordination for concurrent writes."},
    {"uuid": "p_02", "content": "Flutter supports six target platforms."}
  ]
}
```

#### Output
```json
{
  "diff": {
    "added": [],
    "superseded": [{"oldUuid": "p_01", "newUuid": "p_03", "reason": "bidirectional_entailment"}],
    "rewritten": [{"oldUuid": "p_01", "mergedInto": "p_03"}]
  },
  "comparisons": [
    {"new": "p_new", "existing": "p_01", "entailment": 0.91, "contradiction": 0.01, "decision": "merge"},
    {"new": "p_new", "existing": "p_02", "entailment": 0.08, "contradiction": 0.02, "decision": "no_match"}
  ],
  "latencyMs": 6
}
```

#### Metrics
| Metric | Formula | Healthy | Red Flag |
|--------|---------|---------|----------|
| Max entailment score | highest entailment score against any WM entry | 0.0-1.0 | near-threshold scores warrant review |
| Merge rate | (superseded + rewritten) / new propositions | 5-30% | 0% after source 3 (not working) or >60% (redundant extraction) |
| Contradiction rate | contradictions / total comparisons | 1-5% | >20% (decontext hallucinating or source self-contradicting) |


#### Evaluation Rubric (for human labeling)
| Dimension | Question |
|-----------|----------|
| **Match correctness** | Entailment/contradiction/no-match classification correct for this pair? |
| **Merge quality** | When merged, does the canonical rewrite preserve information from both? |
| **No false merges** | Are non-duplicate propositions correctly kept separate? |

Frontier model applies rubric first. Human verifies.

#### Review Screen
New proposition on left. Matched WM proposition on right. NLI scores (entailment, contradiction, neutral) displayed. Pre-selected decision shown. If merge: canonical rewrite displayed below. Reviewer confirms or overrides. Arrow keys to advance. Only pairs near threshold surfaced.

#### Implementation
**Model**: `nli-deberta-v3-xsmall` (22M). Cross-encoder: (proposition A, proposition B) → entailment/contradiction/neutral scores.
**Merge trigger**: bidirectional entailment > threshold → route to decontext for canonical rewrite.
**Contradiction trigger**: contradiction > threshold → supersede old with new.
**Inference**: N new propositions x M working memory entries x ~3ms each.
**AdaptationState**: `entailmentThreshold` (float), `contradictionThreshold` (float).

#### Training
**Fine-tuning**: Trigger: >10% correction rate across 50+ reviewed pairs. Golden data: (proposition_a, proposition_b, correct_decision) from review. Expected improvement: accuracy from ~80% to 90%+.

---

## Pipeline Ordering Rationale

The order is load-bearing. Each stage depends on the previous stage's output form:

| Stage | Requires from previous | Cannot move because |
|-------|----------------------|-------------------|
| Normalize | Raw text | Must clean before splitting |
| Segment | Clean punctuated text | Cannot split unpunctuated text reliably |
| Cohere | Sentence list | Needs atomic units to score adjacency |
| Recohere | Initial span list | Needs cohere boundaries before merging across gaps |
| Filter | Final spans | Must have coherent spans to score |
| Decontext | Filtered extract spans + WM entity list | Needs clean spans and entity context for pronoun resolution |
| Dedup | Atomic propositions + WM state | Cannot compare messy span text against clean WM propositions |

**Dedup cannot move before decontext** because dedup compares propositions (atomic, self-contained) against propositions. Before decontext, only messy multi-claim span text exists.

**Filter is an optimization, dedup is correctness.** Removing filter entirely works. It just wastes LLM calls on noise spans. Removing dedup breaks working memory with duplicates.

---

## Progressive Intelligence

```
Stage            | Phase 1 (now)        | SLM Target              | SLM day one? | Fine-tune trigger
-----------------|----------------------|-------------------------|--------------|------------------
Normalize        | PunctuationRunner    | Same (already SLM)      | Yes          | >5% truecasing corrections
Segment          | Regex                | Regex (already)         | N/A          | Rule updates only
Cohere           | CohereRunner         | Same (already SLM)      | Yes          | >10% boundary corrections
Recohere         | CohereRunner (reuse) | Same (shares w/ cohere) | Yes          | Shared with cohere
Filter           | PassthroughRunner    | DeBERTa-v3-small 44M   | No           | 200 labeled spans (bootstrap)
Decontextualize  | Groq LLM            | T5-3B minimum           | No           | ~1000 (span, props) pairs
Dedup            | NLI DeBERTa          | Same (already SLM)      | Yes          | >10% match corrections
```

Every SLM improves with your data. The trigger column shows when corrections justify a retrain.

**LLM call budget per source**: Filter (0-1, trending to 0 after SLM trained) + Decontext (1 per extract span, permanent) + Dedup rewrites (occasional, triggered by merges). Target: decontext calls only.

---

## SLM Training Process (Generic)

**No external LLM calls.** Claude Code applies each stage's evaluation rubric directly to create golden labels. No Groq, no frontier model API. The labeler is the development agent.

Every SLM-backed stage follows the same training loop. The stage defines two things: its **rubric** (what dimensions to evaluate) and its **golden data format** (input/output pairs from the pipeline). Everything else is generic.

### Training Loop

```
1. COLLECT — Gather stage input/output pairs from golden pipeline runs
2. LABEL  — Claude Code applies the stage's rubric to each pair (no external LLM)
3. BASELINE — Run pre-trained (zero-shot) SLM on the same inputs, measure accuracy against labels
4. TRAIN  — Fine-tune SLM on labeled data (SetFit contrastive / LoRA / full retrain)
5. EVALUATE — Run fine-tuned SLM on held-out split, measure accuracy improvement over baseline
6. SHIP or ITERATE — If improved: export ONNX, deploy. If not: analyze failures, relabel, retrain.
```

**Human enters at step 6**, reviewing only after Claude Code has confirmed improvement. The review UI surfaces borderline cases and disagreements, not the full dataset.

### Stage Contract for Training

Each trainable stage provides:

| Contract Item | What it defines | Example (Filter) |
|--------------|----------------|-------------------|
| **Rubric** | Evaluation dimensions with yes/no questions | Substantive? Specific? |
| **Decision rule** | How dimension answers map to labels | Both yes = extract, either no = skip |
| **Golden input** | What the SLM sees at inference time | Span text (+ optional heuristic features) |
| **Golden output** | The label the SLM should produce | "extract" or "skip" |
| **Metrics** | How to measure quality | Precision, recall, F1 per class |
| **Improvement threshold** | When fine-tuned model is ready | F1 > baseline + 5% |

### Label Format (All Stages)

```json
{
  "index": 0,
  "input": "the text or pair the SLM will classify",
  "label": "the correct classification",
  "dimensions": {"dim1": true, "dim2": false},
  "confidence": "high|borderline",
  "rationale": "brief reason for this label",
  "labeledBy": "claude-opus-4|human"
}
```

### Data Splits

| Split | Size | Purpose |
|-------|------|---------|
| Train | 70% | Fine-tuning data |
| Validation | 15% | Hyperparameter selection, early stopping |
| Test | 15% | Final accuracy measurement (never trained on) |

Stratified by label. Borderline-confidence examples weighted toward validation/test for harder evaluation.

### CPU Training Sizing (SetFit)

**Terminology:**
- **SetFit**: Sentence Transformer Fine-Tuning. Few-shot classifier. Fine-tunes a sentence transformer via contrastive learning, then trains a logistic regression head on embeddings. 8-64 examples per class. No prompts, no large LM.
- **Contrastive pair**: Two texts shown together. Same-class pairs pull embeddings closer. Different-class pairs push them apart.
- **num_iterations**: Pairs generated per training sample. Higher = more diversity = better embeddings, but linearly more compute.
- **batch_size**: Pairs per forward/backward pass. Larger = fewer steps, more memory. 16 is standard for CPU.
- **Step**: One forward + backward + weight update on one batch. Total steps = total pairs / batch_size.
- **Epoch**: One full pass through all pairs. SetFit uses 1 epoch. Pair generation already provides diversity.

**Sizing math:**

Pair count formula: `num_iterations * num_train_samples` per class.
DeBERTa-v3-small: ~24s/step on CPU (batch=16, no GPU).

| Train samples | num_iterations | Total pairs | Steps (batch=16) | Wall time (CPU) |
|---------------|---------------|-------------|-------------------|-----------------|
| 1450          | 20            | 58,000      | 3,625             | ~24 hours       |
| 128 (64/class)| 20            | 2,560       | 160               | ~64 min         |
| 128 (64/class)| 5             | 640         | 40                | ~16 min         |
| 32 (16/class) | 5             | 320         | 20                | **8 min (measured)** |

**16/class baseline results** (32 train, 1673 eval):

| Class | Precision | Recall | F1 |
|-------|-----------|--------|----|
| skip | 0.46 | 0.85 | 0.60 |
| extract | 0.97 | 0.83 | 0.89 |
| weighted avg | 0.89 | 0.83 | 0.85 |

- Skip precision low (0.46): over-predicting skip. Only 16 skip examples = not enough variety.
- Extract precision high (0.97): model learned real signal from just 32 examples.
- Fix: scale to 64/class for more skip variety.

SetFit is few-shot by design. Use **fixed train-per-class**, not percentage split:
- Start with 16/class (32 total) to validate the pipeline end-to-end (~8 min).
- Scale to 64/class once pipeline is confirmed working (~16 min).
- Remaining labels become the eval set. Large eval = reliable metrics.
- Start with `num_iterations=5`. Increase to 20 only if quality is insufficient.
- `batch_size=16` is the sweet spot. 32 gives marginal speedup, 8 is slower.
- Full labeled set is an evaluation asset first, training asset second.

### Per-Stage Training Details

| Stage | SLM | Training Method | Min Labels | Target Metric |
|-------|-----|----------------|------------|---------------|
| Normalize | PunctuationRunner 210M | N/A (pre-trained) | 50 corrections | Truecasing accuracy |
| Cohere | CohereRunner 110M | Fine-tune on boundary corrections | 50 pairs | Boundary F1 |
| Recohere | CohereRunner 110M (shared) | Shared with cohere | — | — |
| Filter | DeBERTa-v3-small 44M | SetFit contrastive | 200 spans | F1 90%+ |
| Dedup | NLI DeBERTa-v3-xsmall 22M | Fine-tune on match corrections | 50 pairs | Match accuracy |

---

## Encoder Scope Boundary

The encoder produces propositions and working memory diffs. **It does not**:
- Do entity resolution (post-encoder, converts propositions to facts)
- Write to the knowledge store (entity resolution does this)
- Determine long-term importance (working memory decay handles this)
- Resolve entities across episodic sources (entity resolution + knowledge store)

---

## Future Work (not in current build)

### Entity Resolution (post-encoder)
Runs after encoder updates working memory. Converts propositions to facts.
Three-stage: GLiNER NER (50M, entity mention detection) → HNSW blocking (candidate retrieval) → NLI cross-encoder (match confirmation).
The boundary where propositions become facts with entity links and temporal metadata.

### Knowledge Store
All persisted facts with entity links and temporal metadata. Append-only with supersession.

### Consolidation
Periodic background dedup of the knowledge store grouped by entity. Catches redundancies between propositions that were never co-resident in working memory.

### Global Coherence Across Episodes
Working memory naturally accumulates cross-episode knowledge. Recohere operates within a single episodic source. Cross-episode topic merging is a knowledge store concern, not an encoder concern.
