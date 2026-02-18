# Golden Data Extraction Instructions

## Purpose

Extract propositions from exported conversations to build a golden dataset. This dataset trains specialized models to replace frontier model calls over time.

## Architecture

The pipeline has 4 stages. Each is a separate, trainable component.

### Stage 0: Segmentation
Split each turn into numbered sentences. Every character of source text belongs to exactly one sentence. No gaps, no overlaps.

### Concept Grouping (between Stage 0 and Stage 1)
Group adjacent sentences that continue the same thought. Uses Next Sentence Prediction (NSP) discourse coherence, not embedding similarity. NSP directly answers "is this a continuation?" which handles cases like "I decided to use ObjectBox" + "Because it supports all six platforms" where embeddings diverge but the thought is continuous.

### Stage 1: Classification
Label every concept span as `extract` or `skip`. Skip labels include a reason: `ephemeral`, `trivial`, `generic`, `already_known`, `unresolved`. Full coverage: every sentence gets a label.

### Stage 2: Proposition Extraction
Convert each `extract` span into one or more self-contained propositions. Decontextualize: replace pronouns and references with named entities. One fact per proposition. No "Because" clause — provenance is stored as a relation to the source episode, not inline.

### Stage 3: Classification
Assign metadata to each proposition:
- `scope`: session | project | life
- `type`: learning | project | exploration

## What You Are

You are an extraction agent. You execute all 4 stages for one conversation, turn by turn. You maintain a running working memory of extracted propositions and use it for dedup.

## Input

- Source turns file: `turns/conv_XXXXXXXX.json`
- This instruction file
- Stage 1 prompt: `stage1_prompt.txt`
- Stage 2 prompt: `stage2_prompt.txt`
- Stage 3 prompt: `stage3_prompt.txt`

## Process

### For each turn (0 through N):

1. Read the source turn (user prompt + assistant response)
2. **Stage 0**: Split into numbered sentences. Output: `S1: "...", S2: "...", ...`
3. Read the current working memory
4. **Stage 1**: Classify every sentence. Group adjacent related sentences into concept spans where appropriate. Output: each span labeled `extract` or `skip(reason)`. Full coverage required — the union of all spans must equal the union of all sentences.
5. **Stage 2**: For each `extract` span, produce one or more propositions. Decontextualize. One fact per proposition. Drop duplicates of working memory entries.
6. **Stage 3**: Assign scope and type to each proposition.
7. Add new propositions to working memory.
8. Move to next turn.

### Self-Evaluate

After all turns, evaluate every proposition against:

| Dimension | Pass Condition |
|-----------|---------------|
| groundedness | Proposition is directly supported by its source sentences |
| atomicity | Proposition contains exactly ONE knowledge unit |
| selfContainment | Proposition is understandable without reading the source |
| salience | Proposition is resolved knowledge, not an open question or generic fact |
| entityClarity | All referenced entities are named, not pronoun references |
| scopeOverreach | Scope matches: session=this conversation, project=named project, life=identity-level |

Iterate until 100% pass rate.

### Present for Human Review

Output per turn:

```
## Turn N
**Source**: [first 100 chars of user prompt]...
**Working memory before**: [count] propositions

**Sentences**:
S1: "..." → extract
S2: "..." → skip(ephemeral)
S3: "..." → extract
S4: "..." → skip(generic)
...

**Concept Spans**:
[S1,S3]: "extracted concept description"
[S2]: skip(ephemeral)
[S4]: skip(generic)

**Propositions** (N new):
1. [proposition text] | scope: X | type: Y | source: S1,S3
```

Then output machine-readable JSON.

## Output Files

Write two files:
1. `extractions/conv_XXXXXXXX.json` — full extraction with propositions
2. `selection/conv_XXXXXXXX.json` — Stage 1 sentence-level classification

## Schema: per-turn-v2

```json
{
  "convUuid": "XXXXXXXX-...",
  "convName": "...",
  "turnCount": N,
  "propositionCount": N,
  "extractionModel": "claude-opus-4-...",
  "extractedAt": "ISO8601",
  "schema": "per-turn-v2",
  "extraction": [
    {
      "turnIndex": 0,
      "workingMemoryBefore": [],
      "sentences": [
        {"id": "S1", "text": "exact sentence from source", "speaker": "user"},
        {"id": "S2", "text": "exact sentence from source", "speaker": "assistant"}
      ],
      "spans": [
        {"sentenceIds": ["S1"], "label": "extract"},
        {"sentenceIds": ["S2", "S3"], "label": "skip", "reason": "ephemeral"},
        {"sentenceIds": ["S4"], "label": "extract"}
      ],
      "propositions": [
        {
          "text": "Self-contained proposition.",
          "sourceIds": ["S1"],
          "scope": "project",
          "type": "learning"
        }
      ]
    }
  ]
}
```

## Key Rules

- **Full coverage**: every sentence must appear in exactly one span. No gaps.
- **One fact per proposition**: two ideas = two propositions.
- **No "Because" clauses**: provenance is the `sourceIds` link, not inline reasoning.
- **Decontextualize**: no "it", "this approach", "the module". Name entities.
- **Sentence text must be verbatim** from the source. No paraphrasing.
- **Working memory dedup**: drop propositions that restate existing working memory entries.
- **Skip unresolved questions**: only extract decided/resolved knowledge.
- **Skip generic reference facts** anyone could look up.
- **Scope**: session = this conversation's work. project = named project. life = identity-level.

## Starting a New Conversation

```
Read: lib/training/extraction/golden/EXTRACTION_INSTRUCTIONS.md
Read: lib/training/extraction/golden/stage1_prompt.txt
Read: lib/training/extraction/golden/stage2_prompt.txt
Read: lib/training/extraction/golden/stage3_prompt.txt
Read: lib/training/extraction/golden/turns/conv_XXXXXXXX.json
Then execute the process above.
```
