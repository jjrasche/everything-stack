# Stage-by-Stage Encoder Golden Data Plan

## Goal
For each of the 7 encoder stages: run on golden data, evaluate quality, train SLM where applicable. No stage proceeds until the previous stage's output is validated.

Full per-stage architecture: `lib/training/extraction/golden/PIPELINE_ARCHITECTURE.md`

## Corpus
33 golden conversations, 465 turns, in `lib/training/extraction/golden/turns/`.

---

## The 7 Stages

| # | Stage | Model | Golden Data | Status |
|---|-------|-------|-------------|--------|
| 1 | Normalize | PunctuationRunner 210M ONNX | `golden/normalize_output/` (33 files) | **DONE** |
| 2 | Segment | Pure regex | `golden/segment_output/` (33 files) | **DONE** |
| 3 | Cohere | CohereRunner 110M ONNX | `golden/cohere_output/` (33 files, 1705 spans) | **DONE** |
| 4 | Recohere | CohereRunner (same 110M) | none | **NOT BUILT** |
| 5 | Filter | DeBERTa-v3-small 44M | none (old classify data is broken) | **NOT BUILT** |
| 6 | Decontext | Groq LLM 8B (permanent) | `golden/decontext_output/` (33 files, 8997 props) | **DATA EXISTS, NOT REVIEWED** |
| 7 | Dedup | NLI DeBERTa 22M | none | **NOT BUILT** |

---

## SLM Training Infrastructure

Training happens in Python. The Dart app does inference only.

```
Python script (PyTorch + SetFit/transformers)
  → fine-tune on labeled pairs
  → export ONNX + quantize INT8
  → app loads updated model via ModelLoader
```

**What exists**: `scripts/export_*.py` for punctuation, coherence, NLI models. These download pre-trained weights and export ONNX. No fine-tuning scripts exist yet.

**What needs to be built per trainable stage**:
1. `scripts/train_<stage>.py`: loads labeled JSON, fine-tunes, exports ONNX
2. Label format: stage-specific JSON in `golden/labels/<stage>/`
3. Trigger: correction rate threshold from human review (see PIPELINE_ARCHITECTURE.md per-stage training section)

| Stage | Training method | Input | Time | Trigger |
|-------|----------------|-------|------|---------|
| Normalize | Full fine-tune 210M | (source, corrected) text pairs | ~5 min GPU | >5% correction rate over 50+ instances |
| Cohere | Full fine-tune 110M | (sent_a, sent_b, boundary) triples | ~5 min GPU | >10% correction rate over 50+ pairs |
| Recohere | Shares model with cohere | same | same | same |
| Filter | SetFit 44M | (span_text, features, extract/skip) | ~30 sec CPU | 200 labeled spans (bootstrap) |
| Dedup | Full fine-tune 22M | (prop_a, prop_b, decision) triples | ~2 min GPU | >10% correction rate over 50+ pairs |

Decontext stays on LLM. Prompt improvement only (PromptImprovementLoop).

---

## Claude Code Batch Evaluation

Claude Code reads cohere output JSON and applies the filter rubric (substantive? specific?) directly. No Groq call needed for labeling.

**Tested batch sizes**: 15, 20, and 50 spans on real golden data. All three produced consistent labels. Quality bottleneck is span complexity (word count), not span count. At avg 125 words/span, 50 spans per pass is comfortable.

**Process**:
1. Read `golden/cohere_output/*.json`, resolve span text from `golden/segment_output/`
2. For each span: apply rubric, write label with rationale and confidence
3. Write labels to `golden/labels/filter/<uuid>.json`
4. Flag borderline spans (confidence: "borderline") for human review
5. Present borderline spans in review screen for human correction

**Label format**:
```json
{
  "spanId": "span_3",
  "text": "ok sounds good let me think about that",
  "label": "skip",
  "rubric": { "substantive": false, "specific": false },
  "rationale": "Conversational filler. No claim, fact, or decision.",
  "confidence": "high"
}
```

**Estimated distribution** (from 50-span test): ~80% high-confidence (clear extract or clear skip), ~20% borderline (requires human review).

---

## Execution Order

### Stage 1: Normalize -- DONE
- PunctuationRunner, SentencePieceTokenizer, ModelLoader, OnnxSessionPool
- NormalizeStage with optional PunctuationRunner injection
- Output: `golden/normalize_output/` (33 files)

### Stage 2: Segment -- DONE
- Code block stripping, markdown stripping, sentence splitting, fragment filtering
- Output: `golden/segment_output/` (33 files)

### Stage 3: Cohere -- DONE
- CohereRunner (bert-wiki-paragraphs ONNX, WordPiece tokenizer, pairwise scoring)
- Two-loop resplit: resplitThreshold=0.65, maxSpanSentences=15
- Output: `golden/cohere_output/` (33 files, 1705 spans)
- Review UI: `tools/cohere_review.html`
- **Remaining**: Human-label ~100 boundary pairs, compute F1

### Stage 4: Recohere -- NEXT
1. Build RecoherStage: encode spans via CohereRunner, pairwise cosine similarity
2. Merge pairs above recohereThreshold (AdaptationState)
3. Run on 33 conversations -> `golden/recohere_output/`
4. Expect 0-3 merges per source

### Stage 5: Filter -- NEXT (replaces old "Classify")
Old classify data (commit 6001bb7) is broken: `firstWhere` bug (57.5% wrong speaker text), empty working memory, collapsed confidence.

**Minimum viable data**: 200 stratified spans (60 short + 60 medium + 80 long). SetFit needs 8-16 examples per class minimum, but 200 gives robust generalization. Expect ~40 skip examples from 200 spans (20% skip rate).

1. Claude Code labels 200 stratified spans directly (no Groq needed), 50 per pass
2. Write labels to `golden/labels/filter/`
3. Human reviews borderline labels (~40 spans) via review screen (`tools/filter_review.html`)
4. `scripts/train_filter.py`: SetFit fine-tune DeBERTa-v3-small on corrected labels (~30 sec CPU)
5. `scripts/export_filter_model.py`: export ONNX + INT8 quantize
6. Build FilterRunner + FilterStage with optional injection
7. Run SLM on all 1705 spans, compare against labels. Target: F1 90%+.
8. If <90%: label another 200 spans, retrain. Active learning on borderline scores.

### Stage 6: Decontext -- DATA EXISTS
Existing: `golden/decontext_output/` (33 files, 8997 propositions from 1422 extract spans)
Generated from broken classify output, but extract spans are valid (83.4% were extract).

1. Verify decontext output is usable despite upstream classify bug
2. Claude Code batch-evaluates propositions on 4 dimensions (self-contained, atomic, faithful, complete)
3. Human reviews flagged propositions
4. Iterate prompt via PromptImprovementLoop until dimension targets met

### Stage 7: Dedup -- AFTER FILTER + DECONTEXT
1. Build DedupRunner: NLI DeBERTa-v3-xsmall (22M) pairwise cross-encoder
2. DedupStage accepts optional DedupRunner (same injection pattern)
3. Run zero-shot on proposition pairs with cumulative working memory
4. Output: `golden/dedup_output/` (33 files)
5. Claude Code batch-evaluates pairs (match correctness, merge quality, no false merges)
6. Human reviews borderline pairs
7. Evaluate accuracy. Target: 90%+. Fine-tune if <85%.

### End-to-end
1. Run full 7-stage encoder on all 33 conversations -> `golden/encoder_output/`
2. Compare final propositions against per-stage golden labels
3. Identify worst-performing stage, iterate

---

## Key Files

### Infrastructure
- `lib/services/slm/model_loader.dart`
- `lib/services/slm/onnx_session_pool.dart`
- `lib/services/slm/session_pool.dart`

### Runners
- `lib/services/slm/runners/punctuation_runner.dart` (normalize)
- `lib/services/slm/runners/cohere_runner.dart` (cohere + recohere)
- `lib/services/slm/runners/filter_runner.dart` (filter, not built)
- `lib/services/slm/runners/dedup_runner.dart` (dedup, not built)

### Tokenizers
- `lib/services/slm/tokenizers/sentencepiece_tokenizer.dart`
- `lib/services/slm/tokenizers/wordpiece_tokenizer.dart`

### Stages
- `lib/services/memory/stages/normalize_stage.dart`
- `lib/services/memory/stages/segment_stage.dart`
- `lib/services/memory/stages/cohere_stage.dart`
- `lib/services/memory/stages/recohere_stage.dart` (not built)
- `lib/services/memory/stages/filter_stage.dart` (not built, replaces classify_stage.dart)
- `lib/services/memory/stages/decontextualize_stage.dart`
- `lib/services/memory/stages/dedup_stage.dart`

### Golden Data Scripts
- `test/scripts/run_normalize_segment_test.dart`
- `test/scripts/run_cohere_golden.dart` (inferred)
- `test/scripts/run_classify_golden.dart` (broken, to be replaced by filter)
- `test/scripts/run_decontext_golden.dart`
- `test/scripts/run_dedup_golden.dart`
- `test/scripts/run_encoder_test.dart` (full pipeline)

### Export Scripts
- `scripts/export_punctuation_model.py`
- `scripts/export_coherence_model.py`
- `scripts/export_nli_model.py`
