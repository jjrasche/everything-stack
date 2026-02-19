# Stage-by-Stage Encoder Golden Data Plan

## Goal
For each of the 6 encoder stages: create golden data, evaluate quality, optimize or hand off to SLM. No stage proceeds until the previous stage's output is validated.

## Corpus
33 golden conversations, 465 turns, in `lib/training/extraction/golden/turns/`.

---

## The 6 Stages

| Stage | Input | Output | On-device SLM | LLM 8B role | Training | Status |
|-------|-------|--------|---------------|-------------|----------|--------|
| **1. Normalize** | raw turn text | punctuated text | PunctuationRunner (210M ONNX). Zero-shot. | None | None needed | **DONE** |
| **2. Segment** | punctuated text | `List<Sentence>` (S1, S2...) | None. Pure regex. | None | N/A | **DONE** |
| **3. Cohere** | sentence list | `List<ConceptSpan>` (grouped sentences) | CohereRunner: bert-wiki-paragraphs (110M). Zero-shot. Two-loop resplit (0.65 threshold, 15 max). | None | Fine-tune on ~300 human-labeled pairs if zero-shot < 85% | **DONE** |
| **4. Classify** | concept spans + working memory | labeled spans (extract/skip) | ClassifyRunner: SetFit (22M). Needs training data. | **Temporary**: generates candidate labels. Human corrects ~100 spans. LLM removed after SetFit trained. | Train SetFit on 100 human-corrected labels (30 sec on CPU) | **DONE** |
| **5. Decontextualize** | extract-labeled span + context | `List<Proposition>` (content, scope, type) | None. **Permanent LLM.** Generative rewriting needs 3B+ minimum. | **Long-term**: decomposes spans into self-contained propositions. Stays on 8B cloud indefinitely. | Golden data drives prompt improvement only. | **DONE** |
| **6. Dedup** | new propositions + working memory | `WorkingMemoryDiff` (added, superseded, rewritten) | DedupRunner: NLI DeBERTa (22M). Zero-shot ~78-82%. Best SLM candidate. | None. Constructor accepts optional ChatClient as temporary fallback only. | Fine-tune on ~100 human-labeled pairs if zero-shot < 85% | **NEXT** |

### How LLM 8B is used per stage:
- **Normalize, Segment, Cohere, Dedup**: NO LLM. On-device SLM or regex.
- **Classify**: LLM generates candidate labels temporarily. Human corrects them. SetFit trains on corrections. LLM removed.
- **Decontextualize**: LLM permanently. Generative task too complex for small models. Golden data improves the prompt.

### Stage details:

**1. Normalize**: Detects punctuation ratio. If low (STT input), calls PunctuationRunner ONNX model. Splits overlong sentences at conjunctions. Assistant turns pass through unchanged.

**2. Segment**: Strips code blocks (fenced + indented), linearizes markdown tables, strips markdown formatting, splits on `.?!`, filters <3 word fragments. Pure regex, deterministic.

**3. Cohere**: Scores adjacent sentence pairs for topic continuity via bert-wiki-paragraphs ONNX. Groups consecutive same-topic sentences into ConceptSpans. Two-loop: first pass at 0.5 threshold for topic boundaries, then recursive resplit at 0.65 on spans exceeding 15 sentences. All spans capped at 15.

**4. Classify**: Binary: extract (durable knowledge) vs skip (ephemeral/trivial). Sequential, feeds previous decisions as context.

**5. Decontextualize**: Decomposes each extract span into 0-N self-contained propositions. Replaces pronouns. Assigns scope (session/project/life) and type (learning/project/exploration). Prompt must allow multiple propositions per span (not "exactly one").

**6. Dedup**: Pairwise NLI comparison against working memory. Entailment = merge. Contradiction = supersede. Constructor accepts optional `DedupRunner` (SLM) or optional `ChatClient` (LLM fallback).

---

## Compounding Error Analysis

Critical path is cohere -> classify -> decontextualize (3 stages). Normalize/segment are deterministic. Dedup is corrective.

| Per-stage accuracy | Critical path (3 stages) | Notes |
|-------------------|-------------------------|-------|
| 85% | 61% | Unacceptable |
| 90% | 73% | Minimum viable |
| 95% | 86% | Target |

---

## Execution Order

### Stage 1: Normalize -- DONE
1. SLM infrastructure: PunctuationRunner, SentencePieceTokenizer, ModelLoader, OnnxSessionPool
2. NormalizeStage with optional PunctuationRunner injection
3. Run on all 33 conversations -> `golden/normalize_output/`

### Stage 2: Segment -- DONE
4. Code block stripping, table linearization, markdown stripping, sentence splitting, fragment filtering
5. Run on all 33 conversations -> `golden/segment_output/`

### Stage 3: Cohere -- DONE
6. Built CohereRunner (bert-wiki-paragraphs ONNX, WordPiece tokenizer, pairwise scoring)
7. CohereStage accepts optional CohereRunner injection
8. Two-loop resplit: resplitThreshold=0.65, maxSpanSentences=15
9. Run on all 33 conversations -> `golden/cohere_output/` (1705 spans, max 15 sentences)
10. Review UI built (`tools/cohere_review.html`), 25 turns selected for labeling
11. Verified 8B model decomposes 12-15 sentence spans into 5-6 propositions (no summarization)
12. **Remaining**: Human-label ~100 cohere boundary pairs, compute F1. Can do in parallel with Classify.

### Stage 4: Classify -- DONE
13. Run LLM classify on cohere output -> `golden/classify_output/` (1705 spans: 83.4% extract, 16.6% skip)
14. Human reviews/corrects 100 spans -> `golden/labels/classify/`
15. Train SetFit (22M) on labeled data. Evaluate. Target: 90%+ F1 on both classes.
16. Build ClassifyRunner, rewrite ClassifyStage with optional injection.

### Stage 5: Decontextualize -- DONE
17. Updated prompt: 0-N propositions with anti-summarization guidance
18. Run LLM decontext on classify-extract spans -> `golden/decontext_output/` (1202 extract spans -> 8997 propositions, 7.5 avg/span)
19. Human-rate 150 propositions on 6 dimensions -> `golden/labels/decontext/`
20. Iterate prompt until dimension targets met. No SLM transition.

### Stage 6: Dedup -- NEXT
21. Run LLM dedup on decontext propositions with cumulative working memory -> `golden/dedup_output/`
22. Integrate `nli-deberta-v3-xsmall` (22M) ONNX model via same runner pattern
23. Build DedupRunner: NLI pairwise (entailment/contradiction/neutral)
24. Rewrite DedupStage to accept optional DedupRunner
25. Run zero-shot on proposition pairs from encoder output
26. Human-label 100 pairs -> `golden/labels/dedup/`
27. Evaluate accuracy. Target: 90%+. Fine-tune if <85%.

### End-to-end evaluation
27. Run full encoder (all 6 stages, SLMs where available) on all 33 conversations -> `golden/encoder_output/`
28. Evaluate final propositions per conversation
29. Compare against per-stage golden labels to identify worst-performing stage
30. Iterate until end-to-end quality meets bar

---

## Evaluation Mechanism

Each stage follows the same pattern:
1. **Run stage** on all 33 conversations. Write output to `golden/<stage>_output/`.
2. **Claude Code analyzes** the output: distributions, outliers, obvious failures.
3. **Claude Code presents** items to the user for labeling. Turn-by-turn, user gives stream-of-consciousness feedback. Claude Code decomposes into structured labels with per-dimension rationale.
4. **Labels written** to `golden/labels/<stage>/` as JSON.
5. **Claude Code computes** precision/recall/F1 against human labels.
6. **If below target**: Claude Code fixes the prompt or model, re-runs, re-evaluates.

---

## Stage 1-2 Status: DONE

- SLM infrastructure built and tested (69 tests pass)
- Normalize output: `golden/normalize_output/` (33 files)
- Segment output: `golden/segment_output/` (33 files)
- Table linearization, decimal period handling, code block stripping

Key files:
- `lib/services/slm/runners/punctuation_runner.dart`
- `lib/services/slm/tokenizers/sentencepiece_tokenizer.dart`
- `lib/services/slm/model_loader.dart`
- `lib/services/slm/onnx_session_pool.dart`
- `lib/services/memory/stages/normalize_stage.dart`
- `lib/services/memory/stages/segment_stage.dart`

## Stage 3 Status: DONE

- CohereRunner: bert-wiki-paragraphs (110M ONNX, WordPiece tokenizer)
- Two-loop resplit: 1434 -> 1705 spans, max 15 sentences, all conversations processed
- Review UI: `tools/cohere_review.html` (~100 interesting pairs to label)
- Verified decomposition quality on 12-15 sentence spans (5-6 propositions, no summarization)

Key files:
- `lib/services/slm/runners/cohere_runner.dart`
- `lib/services/slm/tokenizers/wordpiece_tokenizer.dart`
- `lib/services/memory/stages/cohere_stage.dart` (resplitThreshold, maxSpanSentences)
- `test/services/memory/cohere_stage_test.dart` (6 resplit tests)
- `integration_test/cohere_slm_test.dart`

## Stage 4: Classify -- NEXT

**Task**: Run LLM classify on all cohere output spans to generate candidate extract/skip labels. Human corrects. Train SetFit.

### Steps:
1. Write classify golden data script: reads `golden/cohere_output/`, runs ClassifyStage on each span, writes `golden/classify_output/`
2. Analyze distribution: extract vs skip ratio, confidence distribution, skip reasons
3. Human reviews/corrects 100 spans -> `golden/labels/classify/`
4. Train SetFit on corrections. Evaluate F1. Target: 90%+.
5. Build ClassifyRunner, inject into ClassifyStage.

**Key constraint**: Must run as Flutter test (BaseEntity -> dart:ui dependency chain).
