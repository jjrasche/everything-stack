# Cohere Stage Golden Labels

Human-labeled topic boundary decisions for evaluating the cohere stage's discourse segmentation model (`bert-wiki-paragraphs`, threshold 0.5).

## What This Is

`review_set.json` contains 25 turns selected from 33 golden conversations to cover the full difficulty spectrum:

| Category | Count | Description |
|---|---|---|
| `confident_correct` | 5 | All pair scores above 0.85 or below 0.15. Includes turns with and without boundaries. |
| `moderate_confidence` | 5 | Scores in the 0.15-0.45 range. Model leans toward boundary but not strongly. |
| `hard_uncertain` | 5 | Scores cluster near 0.5 (0.35-0.65). Model is genuinely unsure. |
| `under_split` | 5 | Single span with 10+ sentences. Model saw no boundaries -- is that correct? |
| `most_spans` | 5 | Highest span counts (5-20 spans). Model found many boundaries -- are they real? |

Each entry contains the full sentence text, the model's pairwise coherence scores, the model's span groupings, and a `humanBoundaries` field (initially null) for the reviewer to fill in.

## How to Review

1. Read the sentences in order (S1, S2, S3, ...) as continuous text.
2. For each adjacent pair (S1-S2, S2-S3, ...), decide: **does the speaker shift to a different topic here?**
3. Fill in `humanBoundaries` as a list of sentence pairs where you placed a boundary:

```json
"humanBoundaries": [
  {"pair": ["S3", "S4"], "boundary": true, "reason": "shifts from architecture to testing"},
  {"pair": ["S7", "S8"], "boundary": true, "reason": "moves from current system to future plans"}
]
```

Only list pairs where `boundary` is `true`. Pairs not listed are implicitly `false` (same topic continues).

## What "Boundary" Means

A boundary marks where the speaker shifts **what they are talking about** -- the topic or subject matter changes.

**IS a boundary:**
- Switching from discussing database design to talking about deployment
- Moving from a technical explanation to asking the user a question about a different aspect
- Transitioning from one recipe/procedure to a different one

**IS NOT a boundary:**
- Adding another fact about the same subject (e.g., two sentences about the same database table)
- Providing an example that illustrates the preceding point
- Continuing a train of thought with a different sentence structure
- Listing items that belong to the same category

The key question: "Could these two sentences appear in the same paragraph of a well-written document?" If yes, no boundary.

## Evaluation Metrics

After labeling, we compute precision, recall, and F1 at the **pair level**:

- **Precision**: Of the pairs where the model placed a boundary, what fraction did the human agree with?
- **Recall**: Of the pairs where the human placed a boundary, what fraction did the model also find?
- **F1**: Harmonic mean of precision and recall.

Target: 90%+ F1. If below 85%, the model needs fine-tuning on the labeled pairs.

We also compute:
- **Over-splitting rate**: Model boundaries that the human rejected (false positives).
- **Under-splitting rate**: Human boundaries that the model missed (false negatives).
- **Per-category breakdown**: F1 for each of the 5 selection categories, to identify where the model struggles.

## File Structure

```json
[
  {
    "convUuid": "...",
    "convName": "...",
    "turnIndex": 0,
    "speaker": "user",
    "selectionCategory": "confident_correct",
    "sentences": [{"id": "S1", "text": "..."}, ...],
    "modelDecisions": [{"pair": ["S1","S2"], "score": 0.93, "boundary": false}, ...],
    "modelSpans": [{"spanId": "span_0", "sentenceIds": ["S1","S2","S3"]}, ...],
    "humanBoundaries": null
  }
]
```

## Source Data

- Segment output: `lib/training/extraction/golden/segment_output/` (sentence splitting)
- Cohere output: `lib/training/extraction/golden/cohere_output/` (model decisions)
- Selection script: `scripts/analyze_cohere_turns.py` (how the 25 turns were chosen)
