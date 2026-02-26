"""Pipeline-first golden data orchestrator.

Launches 7 sequential agents, one per pipeline stage, with heuristic gates
between each. Processes one source at a time through all stages.

Input: golden/sources/<uuid>.json  (sourceId + texts array)
Output: golden/<stage>_output/<uuid>.json per stage

Usage:
    python golden_pipeline.py <source_uuid_prefix>
    python golden_pipeline.py <uuid_prefix> --resume
    python golden_pipeline.py <uuid_prefix> --from-stage cohere

Flags:
    --resume       Skip stages whose output already exists and passes heuristics.
    --from-stage X Resume stages before X, regenerate X and all stages after.
                   Useful after manually editing a stage's output file.

Each agent receives:
- The prior agent's output JSON (its input data)
- The relevant stage section from PIPELINE_ARCHITECTURE.md
- The output schema to write

The orchestrator reads each agent's output file, runs heuristics, then
launches the next agent if healthy. Stops on red flags.
"""

import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from markdown_strip import strip_markdown

# --- Paths ---

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden"
SOURCES_DIR = GOLDEN_DIR / "sources"
ARCHITECTURE_DOC = GOLDEN_DIR / "PIPELINE_ARCHITECTURE.md"

OUTPUT_DIRS = {
    "normalize": GOLDEN_DIR / "normalize_output",
    "segment": GOLDEN_DIR / "segment_output",
    "cohere": GOLDEN_DIR / "cohere_output",
    "recohere": GOLDEN_DIR / "recohere_output",
    "filter": GOLDEN_DIR / "filter_output",
    "decontext": GOLDEN_DIR / "decontext_output",
    "dedup": GOLDEN_DIR / "dedup_output",
}

UNIFIED_RUNS_DIR = GOLDEN_DIR / "unified_runs"

STAGE_ORDER = ["normalize", "segment", "cohere", "recohere", "filter", "decontext", "dedup"]

# Approximate tokens-per-word ratio for English text
TOKENS_PER_WORD = 1.3
MAX_SOURCE_TOKENS = 6000


# --- Data loading ---

def _load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def find_source(uuid_prefix: str) -> Path:
    """Find source file by UUID prefix (e.g., 'abc12345')."""
    candidates = list(SOURCES_DIR.glob(f"{uuid_prefix}*.json"))
    if len(candidates) == 0:
        raise FileNotFoundError(f"No source file matching {uuid_prefix}*.json in {SOURCES_DIR}")
    if len(candidates) > 1:
        raise ValueError(f"Multiple matches for {uuid_prefix}: {[c.name for c in candidates]}")
    return candidates[0]


def estimate_source_tokens(source: dict) -> int:
    """Estimate token count from source texts."""
    total_words = sum(len(text.split()) for text in source["texts"])
    return int(total_words * TOKENS_PER_WORD)


def find_output_file(stage: str, source_id: str) -> Path:
    """Construct the expected output path for a stage."""
    return OUTPUT_DIRS[stage] / f"{source_id}.json"


def reconstruct_prior_wm(current_source_id: str) -> list[dict]:
    """Reconstruct working memory from unified run diffs of prior sources.

    Reads all unified_runs/ directories that sort before the current source.
    Replays workingMemoryDiff from each text file: accumulates added,
    removes superseded (matched by content).
    """
    if not UNIFIED_RUNS_DIR.exists():
        return []

    prior_source_dirs = sorted(
        d for d in UNIFIED_RUNS_DIR.iterdir()
        if d.is_dir() and d.name < current_source_id
    )

    propositions: list[dict] = []
    superseded_contents: set[str] = set()

    # First pass: collect all superseded content strings
    for source_dir in prior_source_dirs:
        for text_file in sorted(source_dir.glob("text_*.json")):
            data = _load_json(text_file)
            diff = data.get("workingMemoryDiff", {})
            for entry in diff.get("superseded", []):
                superseded_contents.add(entry["content"])

    # Second pass: collect added propositions, skip superseded
    for source_dir in prior_source_dirs:
        for text_file in sorted(source_dir.glob("text_*.json")):
            data = _load_json(text_file)
            diff = data.get("workingMemoryDiff", {})
            for prop in diff.get("added", []):
                if prop["content"] not in superseded_contents:
                    propositions.append(prop)

    return propositions


# --- Heuristic gate ---

def run_heuristic_gate(stage: str, source_id: str) -> dict:
    """Run golden_heuristics.py on a stage output, return summary dict."""
    from golden_heuristics import run_stage_check, _load_json as load_heuristic_json

    output_path = find_output_file(stage, source_id)
    if not output_path.exists():
        return {"pass": False, "error": f"Output file not found: {output_path}"}

    stage_data = load_heuristic_json(output_path)

    # Stages that need segment_data for word counting
    segment_data = None
    if stage in ("cohere", "decontext"):
        segment_path = find_output_file("segment", source_id)
        if segment_path.exists():
            segment_data = load_heuristic_json(segment_path)

    report = run_stage_check(stage, stage_data, segment_data)
    return report.summarize()


# --- Stage output strippers (minimal data for downstream agents) ---

def _strip_normalize_for_segment(normalize_data: dict) -> list[dict]:
    """Extract only the fields the segment agent needs: array index + output text."""
    return [
        {"text": result["output"]["text"]}
        for result in normalize_data["results"]
    ]


def _strip_segment_for_cohere(segment_data: dict) -> list[dict]:
    """Extract only the fields the cohere agent needs: sentences per text."""
    return [
        {
            "sentences": [
                {"id": s["id"], "text": s["text"]}
                for s in result["output"]["sentences"]
            ],
        }
        for result in segment_data["results"]
    ]


def _strip_cohere_for_recohere(cohere_data: dict) -> list[dict]:
    """Extract only the fields the recohere agent needs: spans per text."""
    return [
        {"spans": result["output"]["spans"]}
        for result in cohere_data["results"]
    ]


def _strip_recohere_for_filter(recohere_data: dict, segment_data: dict) -> list[dict]:
    """Resolve span text for the filter agent: spans with resolved text per text."""
    sentence_lookup = _build_sentence_lookup(segment_data)

    stripped = []
    for i, result in enumerate(recohere_data["results"]):
        sentences = sentence_lookup.get(i, {})
        spans_with_text = []
        for span in result["output"]["spans"]:
            span_text = " ".join(sentences.get(sid, "") for sid in span["sentenceIds"])
            spans_with_text.append({
                "spanId": span["spanId"],
                "sentenceIds": span["sentenceIds"],
                "text": span_text,
            })
        stripped.append({"spans": spans_with_text})
    return stripped


def _build_sentence_lookup(segment_data: dict) -> dict[int, dict[str, str]]:
    """Build {arrayIndex: {sentenceId: text}} from segment output."""
    lookup: dict[int, dict[str, str]] = {}
    for i, result in enumerate(segment_data["results"]):
        lookup[i] = {
            s["id"]: s["text"]
            for s in result["output"]["sentences"]
        }
    return lookup


# --- Agent prompts ---

def _read_architecture_doc() -> str:
    with open(ARCHITECTURE_DOC, encoding="utf-8") as f:
        return f.read()


# Map pipeline stage names to PIPELINE_ARCHITECTURE.md section headers
_STAGE_SECTIONS = {
    "normalize": "Stage 1: Normalize",
    "segment": "Stage 2: Segment",
    "cohere": "Stage 3: Cohere",
    "recohere": "Stage 4: Recohere",
    "filter": "Stage 5: Filter",
    "decontext": "Stage 6: Decontextualize",
    "dedup": "Stage 7: Dedup",
}


def extract_stage_section(architecture: str, stage: str) -> str:
    """Extract one stage's section from PIPELINE_ARCHITECTURE.md."""
    header = _STAGE_SECTIONS[stage]
    start_marker = f"## {header}"
    start_idx = architecture.find(start_marker)
    if start_idx == -1:
        return f"[Section '{header}' not found in architecture doc]"

    # Find the next ## header after this one
    next_header_idx = architecture.find("\n## ", start_idx + len(start_marker))
    if next_header_idx == -1:
        return architecture[start_idx:]
    return architecture[start_idx:next_header_idx]


def build_normalize_prompt(source: dict, architecture: str) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("normalize", source_id)
    rubric = extract_stage_section(architecture, "normalize")

    # Pre-strip markdown deterministically. Agent receives clean prose.
    stripped_texts = [strip_markdown(text) for text in source["texts"]]
    texts_json = json.dumps(stripped_texts, indent=2, ensure_ascii=False)

    return f"""You are a golden data generation agent for Stage 1: Normalize of the encoder pipeline.

## Task
Read the pre-cleaned source texts below and produce normalized text for each one.
Markdown formatting, code blocks, tables, and XML tags have already been stripped.
Your job: punctuation, truecasing, sentence splitting, and STT artifact cleanup.
Write the output JSON file to: {output_path}

## Rubric
- Compute punctuation ratio (marks per word). If low, add punctuation and truecasing.
- Check for overlong sentences exceeding 40 words. Split at coordinating conjunctions.
- Clean up STT artifacts, filler words.
- Normalize each text independently.

{rubric}

## Source Texts (markdown already stripped)
Source ID: {source_id}
Text count: {len(source["texts"])}
Texts:
{texts_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "stage": "normalize",
  "generator": "claude-code",
  "generatedAt": "<ISO timestamp>",
  "results": [
    {{
      "input": {{"text": "<raw text>"}},
      "output": {{"text": "<normalized text>", "punctuationNeeded": true/false, "latencyMs": 0}}
    }}
    // ... one entry per source text, same order
  ]
}}

results[0] = processing of texts[0], results[1] = processing of texts[1], etc.
punctuationNeeded = true if the input required punctuation/casing changes.

Write the output file now. Do not ask for confirmation."""


def build_segment_prompt(source: dict, normalize_data: dict, architecture: str) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("segment", source_id)
    rubric = extract_stage_section(architecture, "segment")

    stripped = _strip_normalize_for_segment(normalize_data)
    normalize_json = json.dumps(stripped, indent=2, ensure_ascii=False)

    return f"""You are a golden data generation agent for Stage 2: Segment of the encoder pipeline.

## Task
Read the normalized text from Stage 1 output below and segment each text into sentences.
Write the output JSON file to: {output_path}

## Rubric
- Strip code blocks (fenced + indented), strip markdown formatting.
- Split on sentence boundaries (.?!).
- Filter fragments under 3 words.
- Each sentence gets an ID: S1, S2, S3, etc. (resets for each text).

{rubric}

## Normalized Texts
{normalize_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "stage": "segment",
  "generator": "claude-code",
  "generatedAt": "<ISO timestamp>",
  "results": [
    {{
      "input": {{"text": "<normalized text from stage 1>"}},
      "output": {{
        "sentences": [
          {{"id": "S1", "text": "First sentence."}},
          {{"id": "S2", "text": "Second sentence."}}
        ],
        "droppedFragments": ["fragment under 3 words"],
        "latencyMs": 0
      }}
    }}
    // ... one entry per text, same order
  ]
}}

Write the output file now. Do not ask for confirmation."""


def build_cohere_prompt(source: dict, segment_data: dict, architecture: str) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("cohere", source_id)
    rubric = extract_stage_section(architecture, "cohere")

    stripped = _strip_segment_for_cohere(segment_data)
    segment_json = json.dumps(stripped, indent=2, ensure_ascii=False)

    return f"""You are a golden data generation agent for Stage 3: Cohere of the encoder pipeline.

## Task
Read the segmented sentences from Stage 2 output below and group them into concept spans.
Write the output JSON file to: {output_path}

## Rules
- Group adjacent sentences that discuss the SAME concept/topic into spans.
- HARD LIMIT: Maximum 5 sentences per span. If a topic runs longer than 5 sentences, split at the weakest internal boundary.
- Spans cannot cross text boundaries.
- Give each span an ID: span_0, span_1, etc. (resets for each text).
- Each span lists the sentence IDs it contains.

## Splitting Guidance
When a long passage covers a broad topic (e.g. "system features"), split by sub-topic:
- BAD: One span with 8 sentences covering trip tiers + credit mechanics + access controls + special circumstances
- GOOD: span_0 (trip tiers, 3 sentences), span_1 (credit mechanics, 2 sentences), span_2 (access controls + special circumstances, 3 sentences)

When sentences shift from one aspect to another (costs -> labor, design -> metrics, proposal -> follow-up questions), that is a span boundary even if the broad topic is the same.

{rubric}

## Segmented Sentences (per text)
{segment_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "stage": "cohere",
  "generator": "claude-code",
  "generatedAt": "<ISO timestamp>",
  "results": [
    {{
      "input": {{"sentences": [{{"id": "S1", "text": "..."}}, ...]}},
      "output": {{
        "spans": [
          {{"spanId": "span_0", "sentenceIds": ["S1", "S2", "S3"]}},
          {{"spanId": "span_1", "sentenceIds": ["S4", "S5"]}}
        ],
        "latencyMs": 0
      }}
    }}
    // ... one entry per text, same order
  ]
}}

Write the output file now. Do not ask for confirmation."""


def build_recohere_prompt(source: dict, cohere_data: dict, architecture: str) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("recohere", source_id)
    rubric = extract_stage_section(architecture, "recohere")

    stripped = _strip_cohere_for_recohere(cohere_data)
    cohere_json = json.dumps(stripped, indent=2, ensure_ascii=False)

    return f"""You are a golden data generation agent for Stage 4: Recohere of the encoder pipeline.

## Task
Read the concept spans from Stage 3 output below. Merge adjacent spans within the same text
that discuss the same concept and should have been grouped together. Most spans will pass through unchanged.
Write the output JSON file to: {output_path}

## Rubric
- Merge adjacent spans within the same text only if they discuss the same concept.
- Healthy merge rate: 0-20%. Red flag: > 40%.
- Record any merges in the "merges" array.

{rubric}

## Concept Spans (per text)
{cohere_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "stage": "recohere",
  "generator": "claude-code",
  "generatedAt": "<ISO timestamp>",
  "results": [
    {{
      "input": {{
        "spans": [{{"spanId": "span_0", "sentenceIds": ["S1", "S2"]}}]
      }},
      "output": {{
        "spans": [{{"spanId": "span_0", "sentenceIds": ["S1", "S2"]}}],
        "merges": [],
        "latencyMs": 0
      }}
    }}
    // ... one entry per text, same order
  ]
}}

If merges occurred, record them as:
"merges": [{{"from": ["span_0", "span_1"], "to": "span_0", "reason": "same concept"}}]

Write the output file now. Do not ask for confirmation."""


def build_filter_prompt(
    source: dict,
    recohere_data: dict,
    segment_data: dict,
    architecture: str,
) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("filter", source_id)
    rubric = extract_stage_section(architecture, "filter")

    stripped = _strip_recohere_for_filter(recohere_data, segment_data)
    filter_input_json = json.dumps(stripped, indent=2, ensure_ascii=False)

    return f"""You are a golden data generation agent for Stage 5: Filter of the encoder pipeline.

## Task
Read the recohere spans below. Each span includes its resolved text. For each span, decide whether to
extract (contains knowledge worth remembering) or skip (ephemeral, trivial, generic).
Write the output JSON file to: {output_path}

## Rules
- Each span gets a binary label: "extract" or "skip".
- Extract = contains durable knowledge, decisions, designs, constraints, preferences, specific metrics.
- Skip = ephemeral, trivial, generic, pleasantries, meta-text, discourse scaffolding.
- SKIP these patterns: "Would you like to explore...", "Let me know if...", "We could also look at...",
  "Here are some options...", follow-up question lists, offers of further exploration.
  These are dialogue management, not knowledge.
- Healthy skip rate: 5-50%. Red flag: > 80%.

{rubric}

## Spans With Text (per text)
{filter_input_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "stage": "filter",
  "model": "golden-manual",
  "totalSpans": <total span count>,
  "totalExtract": <extract count>,
  "totalSkip": <skip count>,
  "extractRate": "<percentage as string>",
  "results": [
    {{
      "spanCount": 2,
      "extractCount": 1,
      "skipCount": 1,
      "decisions": [
        {{
          "spanId": "span_0",
          "label": "extract",
          "extractScore": 0.5,
          "skipScore": 0.5,
          "model": "golden-manual",
          "latencyMs": 0
        }}
      ]
    }}
    // ... one entry per text, same order
  ]
}}

Write the output file now. Do not ask for confirmation."""


def build_decontext_prompt(
    source: dict,
    filter_data: dict,
    segment_data: dict,
    recohere_data: dict,
    architecture: str,
) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("decontext", source_id)
    rubric = extract_stage_section(architecture, "decontext")

    # Build the decontext input: for each text, include extract spans with resolved text
    sentence_lookup = _build_sentence_lookup(segment_data)

    # Build extract span set from filter decisions
    extract_spans: set[tuple[int, str]] = set()
    for i, result in enumerate(filter_data["results"]):
        for decision in result["decisions"]:
            if decision["label"] == "extract":
                extract_spans.add((i, decision["spanId"]))

    # Build input with resolved span text
    decontext_input = []
    for i, result in enumerate(recohere_data["results"]):
        sentences = sentence_lookup.get(i, {})
        spans_with_text = []
        for span in result["output"]["spans"]:
            if (i, span["spanId"]) in extract_spans:
                span_text = " ".join(sentences.get(sid, "") for sid in span["sentenceIds"])
                spans_with_text.append({
                    "spanId": span["spanId"],
                    "sentenceIds": span["sentenceIds"],
                    "text": span_text,
                })

        if spans_with_text:
            decontext_input.append({"spans": spans_with_text})
        else:
            decontext_input.append({"spans": []})

    decontext_input_json = json.dumps(decontext_input, indent=2, ensure_ascii=False)

    return f"""You are a golden data generation agent for Stage 6: Decontextualize of the encoder pipeline.

## Task
Read the extract spans below (spans that passed the filter). For each span, produce
self-contained propositions that capture the knowledge in bare assertive form.
Write the output JSON file to: {output_path}

## Rubric
Read the "Stage 6: Decontextualize" section from PIPELINE_ARCHITECTURE.md below for the operation rules:

CRITICAL RULES:
1. **Bare assertive form**: Every proposition must be a standalone knowledge claim.
   Test: "It is known that [proposition]" must read naturally.
   NEVER use "The user", "The speaker", "The assistant", "The person" -- zero epistemic framing.
2. **Atomic**: ONE fact per proposition. This is the most important rule.
   If a span contains multiple facts, produce multiple propositions.
   VIOLATIONS to avoid:
   - BAD: "Labor requirements include 12,000 hours for core operations, 5,500 hours for revenue activities, mix of skill levels, and training emphasis."
     GOOD: Four separate propositions: "Core fleet operations require 12,000 labor hours annually." / "Revenue-generating activities require 5,500 labor hours annually." / "Fleet operations require a mix of skill levels." / "Fleet training emphasizes skill development."
   - BAD: "Special circumstances exist for medical necessity, family emergencies, educational opportunities, and community service."
     GOOD: One proposition: "Special circumstances provisions cover medical necessity, family emergencies, educational opportunities, and community service." (This IS one fact: the existence of a policy with its scope.)
   - BAD: "The system uses a 1:18 ratio and costs $63.75/month per person."
     GOOD: Two propositions: "The proposed vehicle-to-user ratio is 1:18." / "The estimated per-capita cost is $63.75 per month."
   The test: can you remove any clause without losing a DIFFERENT fact? If yes, split.
3. **Self-contained**: Each proposition must be understandable without the source context.
   Replace pronouns with referents. Include necessary context.
   Include specific numbers, distances, costs -- do not generalize away details.
   - BAD: "A ridesharing obligation exists."
     GOOD: "Vehicle users must provide ridesharing for passengers within 10 miles of their destination."
4. **Grounded**: Every proposition must trace to specific source sentences.
5. **Props per span**: Target 1-8 propositions per span. More for dense spans, fewer for thin ones.
6. **Capture all facts**: Every distinct constraint, metric, cost, design decision, and preference
   in the source must appear as a proposition. If the source says "$63.75/month" or "non-EV" or
   "10 miles" -- that specific detail must appear in a proposition. Do not summarize away specifics.
7. **Track evolution**: If the text revises a design (e.g. 15,000 sq ft facility revised to
   6-bay service facility), produce propositions for BOTH the original and the revision. Mark the
   revision with type "correction".

## Extract Spans (with resolved text, per text)
{decontext_input_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "stage": "decontext",
  "generator": "claude-code",
  "generatedAt": "<ISO timestamp>",
  "results": [
    {{
      "input": {{
        "spans": [
          {{
            "spanId": "span_0",
            "sentenceIds": ["S1", "S2"],
            "text": "resolved span text..."
          }}
        ]
      }},
      "output": {{
        "extractSpanCount": 1,
        "propositions": [
          {{
            "content": "A community transportation system is being designed for a 1,000-person permaculture-based micro-society.",
            "scope": "project",
            "type": "exploration",
            "sourceIds": ["S1", "S2"]
          }}
        ],
        "latencyMs": 0
      }}
    }}
    // ... one entry per text, same order. Empty spans = empty propositions.
  ]
}}

scope values: session, project, life
type values: decision, design, constraint, preference, exploration, domain, hypothesis, correction

{rubric}

Write the output file now. Do not ask for confirmation."""


def build_dedup_prompt(
    source: dict,
    decontext_data: dict,
    architecture: str,
    prior_wm: list[dict] | None = None,
) -> str:
    source_id = source["sourceId"]
    output_path = find_output_file("dedup", source_id)
    rubric = extract_stage_section(architecture, "dedup")

    # Collect new propositions from this source
    new_propositions = []
    for i, result in enumerate(decontext_data["results"]):
        for prop in result["output"].get("propositions", []):
            new_propositions.append({
                "index": len(new_propositions),
                "content": prop["content"],
                "textIndex": i,
                "source": "new",
            })

    # Include prior WM propositions for cross-source dedup
    wm_propositions = []
    if prior_wm:
        for idx, prop in enumerate(prior_wm):
            wm_propositions.append({
                "index": len(new_propositions) + idx,
                "content": prop["content"],
                "source": "prior_wm",
            })

    all_propositions = new_propositions + wm_propositions
    props_json = json.dumps(all_propositions, indent=2, ensure_ascii=False)

    wm_section = ""
    if wm_propositions:
        wm_section = f"""
## Cross-Source Working Memory
There are {len(wm_propositions)} propositions from prior sources (marked source: "prior_wm").
Compare new propositions against these as well. If a new proposition duplicates or
contradicts a prior WM proposition, label the pair accordingly.
"""

    return f"""You are a golden data generation agent for Stage 7: Dedup of the encoder pipeline.

## Task
Read all propositions below (new from this source + prior working memory).
Identify duplicate and near-duplicate pairs. For each candidate pair, classify as
bidirectional_entailment, forward_entailment, contradiction, or no_match.
Write the output JSON file to: {output_path}

## Rules
- **Exhaustive comparison**: You MUST compare every proposition against every other proposition.
  With N propositions there are N*(N-1)/2 pairs. Label ALL of them. Do not skip pairs.
  This is golden training data -- incomplete coverage means the SLM learns to miss duplicates.
- bidirectional_entailment: Both propositions say the same thing. One is redundant.
- forward_entailment: A entails B but not vice versa (A is more general, B more specific).
- contradiction: A and B conflict (e.g. proposed then rejected, original then revised).
  For each contradiction, determine which proposition is SUPERSEDED (the earlier/rejected one)
  and which is the SUPERSEDING correction. The superseded prop is archived from working memory.
- no_match: Different facts despite any surface similarity.
- Healthy merge rate: 5-30%. Red flag: > 60%.
{wm_section}
## Common Missed Patterns
- "X labor is done by the community" + "The fleet is maintained through community efforts" = forward_entailment (specific labor type entailed by general maintenance)
- Proposition from text 0 proposing a design + Proposition from text 3 rejecting it = contradiction
- Same fact restated across texts = bidirectional_entailment

## All Propositions
{props_json}

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "{source_id}",
  "totalPropositions": {len(all_propositions)},
  "newPropositions": {len(new_propositions)},
  "priorWmPropositions": {len(wm_propositions)},
  "candidatePairsLabeled": <number of ALL pairs evaluated>,
  "stage": "dedup",
  "model": "golden-manual",
  "summary": {{
    "entailment": <count>,
    "contradiction": <count>,
    "noMatch": <count>
  }},
  "pairs": [
    {{
      "indexA": 0,
      "indexB": 5,
      "contentA": "proposition A text",
      "contentB": "proposition B text",
      "textIndexA": 0,
      "textIndexB": 1,
      "decision": "bidirectional_entailment",
      "entailmentScore": 1.0,
      "contradictionScore": 0.0
    }}
  ],
  "resolutions": [
    {{
      "supersededIndex": 0,
      "supersededBy": 5,
      "reason": "Design proposed in text 0 was explicitly rejected in text 3"
    }}
  ]
}}

The "resolutions" array must contain one entry for EACH contradiction pair.
supersededIndex = the proposition that is obsolete/rejected (archive it).
supersededBy = the proposition that replaces or rejects it (keep it).
When one rejection proposition supersedes multiple proposals, create a resolution entry for EACH superseded prop.

Include ALL N*(N-1)/2 pairs. Do not filter by Jaccard or any other threshold.

{rubric}

Write the output file now. Do not ask for confirmation."""


def build_review_prompt(source: dict, decontext_data: dict, dedup_data: dict) -> str:
    """Build prompt for the qualitative review agent."""
    source_id = source["sourceId"]

    # Build final working memory: all propositions minus duplicates
    all_propositions = []
    for result in decontext_data["results"]:
        for prop in result["output"].get("propositions", []):
            all_propositions.append(prop["content"])

    # Remove duplicates (bidirectional entailment: keep lower index)
    removed_indices = set()
    for pair in dedup_data.get("pairs", []):
        if pair["decision"] == "bidirectional_entailment":
            removed_indices.add(max(pair["indexA"], pair["indexB"]))

    # Remove superseded props (contradictions resolved by dedup)
    for resolution in dedup_data.get("resolutions", []):
        removed_indices.add(resolution["supersededIndex"])

    final_wm = [
        prop for i, prop in enumerate(all_propositions)
        if i not in removed_indices
    ]

    # Source text
    source_text = ""
    for i, text in enumerate(source["texts"]):
        source_text += f"\n--- Text {i} ---\n"
        source_text += text + "\n"

    wm_text = "\n".join(f"  {i+1}. {prop}" for i, prop in enumerate(final_wm))

    return f"""You are a qualitative review agent for the encoder pipeline golden data.

## Task
Compare the original source texts with the final working memory propositions.
Assess three dimensions: faithfulness, completeness, coherence.

## Source Texts
Source ID: {source_id}
{source_text}

## Final Working Memory ({len(final_wm)} propositions after dedup)
{wm_text}

## Assessment Criteria

### Faithfulness
Are all propositions grounded in the source? Flag any proposition that:
- Claims something not in the source
- Misrepresents what was said
- Over-generalizes or under-specifies

### Completeness
Does the working memory capture all important knowledge from the source?
- List any significant decisions, designs, constraints, or preferences that are MISSING
- Note if ephemeral/trivial content was correctly excluded

### Coherence
Do the propositions form a coherent knowledge base?
- Flag contradictions between propositions
- Flag redundancies that should have been caught by dedup
- Assess whether propositions are truly atomic (one fact each)

## Output
Write your assessment as a structured report. Be specific: cite proposition numbers
and source text numbers. Give an overall score for each dimension (1-5).

Print your assessment to stdout. Do not write a file."""


# --- Agent launcher ---

@dataclass
class AgentResult:
    success: bool
    stdout: str
    stderr: str
    elapsed_seconds: float
    error: str | None


def launch_agent(agent_prompt: str, working_dir: Path, timeout_seconds: int = 600) -> AgentResult:
    """Launch a claude CLI agent with the given prompt via stdin."""
    start_time = time.time()
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    try:
        proc = subprocess.run(
            ["claude", "--print", "--dangerously-skip-permissions", "-p", "-"],
            input=agent_prompt,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            cwd=str(working_dir),
            shell=(os.name == "nt"),
            encoding="utf-8",
            env=env,
        )
        elapsed = time.time() - start_time
        return AgentResult(
            success=proc.returncode == 0,
            stdout=proc.stdout,
            stderr=proc.stderr,
            elapsed_seconds=elapsed,
            error=None if proc.returncode == 0 else f"exit code {proc.returncode}",
        )
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start_time
        return AgentResult(
            success=False,
            stdout="",
            stderr="",
            elapsed_seconds=elapsed,
            error=f"timeout after {timeout_seconds}s",
        )



def print_gate_result(gate_result: dict) -> None:
    """Print heuristic gate results to stdout."""
    if gate_result.get("pass"):
        print(f"  PASS ({gate_result.get('warningCount', 0)} warnings)")
        return

    for rf in gate_result.get("redFlags", []):
        print(f"    [X] {rf['name']}: {rf['value']} -- {rf['context']}")
    for bf in gate_result.get("bugFailures", []):
        print(f"    [BUG] {bf['name']}: {bf['value']} -- {bf['context']}")


PROMPT_BUILDERS = {
    "normalize": lambda src, arch, **_: build_normalize_prompt(src, arch),
    "segment": lambda src, arch, **kw: build_segment_prompt(src, kw["normalize"], arch),
    "cohere": lambda src, arch, **kw: build_cohere_prompt(src, kw["segment"], arch),
    "recohere": lambda src, arch, **kw: build_recohere_prompt(src, kw["cohere"], arch),
    "filter": lambda src, arch, **kw: build_filter_prompt(src, kw["recohere"], kw["segment"], arch),
    "decontext": lambda src, arch, **kw: build_decontext_prompt(src, kw["filter"], kw["segment"], kw["recohere"], arch),
    "dedup": lambda src, arch, **kw: build_dedup_prompt(src, kw["decontext"], arch, kw.get("prior_wm")),
}


def compute_surviving_wm(decontext_data: dict, dedup_data: dict) -> list[dict]:
    """Compute surviving propositions after dedup removals."""
    all_propositions = []
    for result in decontext_data["results"]:
        for prop in result["output"].get("propositions", []):
            all_propositions.append(prop)

    # Indices removed by bidirectional entailment (keep lower index)
    removed_indices = set()
    for pair in dedup_data.get("pairs", []):
        if pair["decision"] == "bidirectional_entailment":
            removed_indices.add(max(pair["indexA"], pair["indexB"]))

    # Indices removed by contradiction resolution
    for resolution in dedup_data.get("resolutions", []):
        removed_indices.add(resolution["supersededIndex"])

    return [
        prop for i, prop in enumerate(all_propositions)
        if i not in removed_indices
    ]


@dataclass
class PipelineResult:
    source_id: str
    stages_completed: list[str]
    stopped_at: str | None
    stop_reason: str | None
    heuristic_summaries: dict[str, dict]
    review_output: str | None


def run_pipeline(
    uuid_prefix: str,
    resume: bool = False,
    from_stage: str | None = None,
) -> PipelineResult:
    """Run the full pipeline for one source.

    If resume=True, skip stages whose output file already exists and passes heuristics.
    If from_stage is set, resume stages before it and regenerate from that stage onwards.
    """
    source_path = find_source(uuid_prefix)
    source = _load_json(source_path)
    source_id = source["sourceId"]

    # Check token budget
    estimated_tokens = estimate_source_tokens(source)
    print(f"\nSource ID: {source_id}")
    print(f"Text count: {len(source['texts'])}")
    print(f"Estimated tokens: {estimated_tokens}")

    if estimated_tokens > MAX_SOURCE_TOKENS:
        print(f"\nWARNING: Source exceeds {MAX_SOURCE_TOKENS} token budget ({estimated_tokens} estimated).")
        print("Consider splitting. Proceeding anyway for now.")

    architecture = _read_architecture_doc()

    # Validate from_stage
    if from_stage and from_stage not in STAGE_ORDER:
        print(f"ERROR: Unknown stage '{from_stage}'. Valid: {', '.join(STAGE_ORDER)}")
        sys.exit(1)

    # Determine which stages to force-regenerate
    regenerate_from_index = STAGE_ORDER.index(from_stage) if from_stage else len(STAGE_ORDER)

    # Reconstruct working memory from unified run diffs of prior sources
    prior_wm = reconstruct_prior_wm(source_id)
    if prior_wm:
        print(f"Prior WM: {len(prior_wm)} propositions from prior sources")
    else:
        print(f"Prior WM: empty (first source or no prior runs)")

    # Accumulated stage outputs for passing to subsequent agents
    stage_outputs: dict[str, dict] = {"prior_wm": prior_wm}
    result = PipelineResult(
        source_id=source_id,
        stages_completed=[],
        stopped_at=None,
        stop_reason=None,
        heuristic_summaries={},
        review_output=None,
    )

    for stage_index, stage in enumerate(STAGE_ORDER):
        print(f"\n{'='*60}")
        print(f"Stage: {stage}")
        print(f"{'='*60}")

        output_path = find_output_file(stage, source_id)
        force_regenerate = stage_index >= regenerate_from_index

        # Resume: skip stages with existing valid output (unless force-regenerating)
        can_resume = (resume or from_stage) and not force_regenerate
        if can_resume and output_path.exists() and output_path.stat().st_size > 10:
            print(f"  Resuming: loading existing output ({output_path.stat().st_size} bytes)")
            stage_outputs[stage] = _load_json(output_path)
            gate_result = run_heuristic_gate(stage, source_id)
            result.heuristic_summaries[stage] = gate_result
            print_gate_result(gate_result)
            if not gate_result.get("pass"):
                print(f"  Existing output fails heuristics, regenerating...")
            else:
                result.stages_completed.append(stage)
                continue

        # Delete stale output when force-regenerating
        if force_regenerate and output_path.exists():
            print(f"  Deleting stale output (upstream changed)")
            output_path.unlink()

        # Build prompt
        builder = PROMPT_BUILDERS[stage]
        built_prompt = builder(source, architecture, **stage_outputs)
        print(f"  Prompt: {len(built_prompt)} chars")

        # Launch agent
        print(f"  Launching agent...")
        agent_result = launch_agent(built_prompt, GOLDEN_DIR)
        print(f"  Completed in {agent_result.elapsed_seconds:.1f}s")

        if not agent_result.success:
            print(f"  Agent failed: {agent_result.error}")
            result.stopped_at = stage
            result.stop_reason = f"Agent failed: {agent_result.error}"
            return result

        # Verify output file exists
        if not output_path.exists():
            print(f"  ERROR: Output file not created by agent")
            result.stopped_at = stage
            result.stop_reason = f"Agent did not create output file: {output_path}"
            return result

        # Load output for next stage
        stage_outputs[stage] = _load_json(output_path)

        # Run heuristic gate
        print(f"  Running heuristics...")
        gate_result = run_heuristic_gate(stage, source_id)
        result.heuristic_summaries[stage] = gate_result
        print_gate_result(gate_result)

        if not gate_result.get("pass"):
            result.stopped_at = stage
            result.stop_reason = (
                f"Heuristic gate failed: "
                f"{gate_result.get('redFlagCount', 0)} red flags, "
                f"{gate_result.get('bugFailureCount', 0)} bug failures"
            )
            result.stages_completed.append(stage)
            return result

        result.stages_completed.append(stage)

    # All stages passed -- run qualitative review
    print(f"\n{'='*60}")
    print(f"Stage: qualitative_review")
    print(f"{'='*60}")

    review_built_prompt = build_review_prompt(
        source,
        stage_outputs["decontext"],
        stage_outputs["dedup"],
    )
    print(f"  Launching review agent...")
    review_agent = launch_agent(review_built_prompt, GOLDEN_DIR)
    if review_agent.success:
        result.review_output = review_agent.stdout
        print(f"  Review complete ({len(review_agent.stdout)} chars)")
    else:
        print(f"  Review agent failed: {review_agent.error}")
        result.review_output = f"FAILED: {review_agent.error}"

    # Report WM stats (actual WM is reconstructed from unified run diffs)
    surviving = compute_surviving_wm(
        stage_outputs["decontext"],
        stage_outputs["dedup"],
    )
    print(f"\n  WM: {len(prior_wm)} prior + {len(surviving)} new = {len(prior_wm) + len(surviving)} total")

    # Run assembly to produce unified output files
    print(f"\n{'='*60}")
    print(f"Stage: assembly")
    print(f"{'='*60}")
    assembly_result = subprocess.run(
        [sys.executable, str(Path(__file__).parent / "assemble_golden.py"), uuid_prefix],
        capture_output=True,
        text=True,
        cwd=str(Path(__file__).parent),
        encoding="utf-8",
    )
    if assembly_result.returncode == 0:
        print(assembly_result.stdout)
        delete_stage_outputs(source_id)
        remove_empty_stage_dirs()
    else:
        print(f"  Assembly failed: {assembly_result.stderr}")

    return result


def delete_stage_outputs(source_id: str) -> None:
    """Delete intermediate stage output files after successful assembly."""
    for output_dir in OUTPUT_DIRS.values():
        stage_file = output_dir / f"{source_id}.json"
        if stage_file.exists():
            stage_file.unlink()


def remove_empty_stage_dirs() -> None:
    """Remove stage output directories if empty."""
    for output_dir in OUTPUT_DIRS.values():
        if output_dir.exists() and not any(output_dir.iterdir()):
            output_dir.rmdir()


# --- Main ---

def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python golden_pipeline.py <uuid_prefix> [--resume] [--from-stage <stage>]")
        print("Example: python golden_pipeline.py <uuid_prefix> --from-stage cohere")
        print(f"Stages: {', '.join(STAGE_ORDER)}")
        sys.exit(1)

    uuid_prefix = sys.argv[1]
    resume = "--resume" in sys.argv

    from_stage = None
    if "--from-stage" in sys.argv:
        from_stage_idx = sys.argv.index("--from-stage")
        if from_stage_idx + 1 >= len(sys.argv):
            print("ERROR: --from-stage requires a stage name")
            sys.exit(1)
        from_stage = sys.argv[from_stage_idx + 1]

    result = run_pipeline(uuid_prefix, resume=resume, from_stage=from_stage)

    print(f"\n{'='*60}")
    print(f"PIPELINE SUMMARY")
    print(f"{'='*60}")
    print(f"Source: {result.source_id}")
    print(f"Stages completed: {', '.join(result.stages_completed)}")
    if result.stopped_at:
        print(f"Stopped at: {result.stopped_at}")
        print(f"Reason: {result.stop_reason}")
    else:
        print(f"All stages completed successfully!")



if __name__ == "__main__":
    main()
