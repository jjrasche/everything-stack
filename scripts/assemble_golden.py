"""Assemble per-stage golden data files into unified output format.

Reads stage output files (normalize through dedup) for a source,
merges them into one JSON file per text position, computes heuristics
and metrics, and writes the unified files.

Usage:
    python assemble_golden.py <source_uuid_prefix>

The per-stage intermediate files remain untouched. The unified files are
the deliverables; intermediates are working artifacts.
"""

import json
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# --- Paths ---

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden"
SOURCES_DIR = GOLDEN_DIR / "sources"
UNIFIED_DIR = GOLDEN_DIR / "unified_runs"

STAGE_DIRS = {
    "normalize": GOLDEN_DIR / "normalize_output",
    "segment": GOLDEN_DIR / "segment_output",
    "cohere": GOLDEN_DIR / "cohere_output",
    "recohere": GOLDEN_DIR / "recohere_output",
    "filter": GOLDEN_DIR / "filter_output",
    "decontext": GOLDEN_DIR / "decontext_output",
    "dedup": GOLDEN_DIR / "dedup_output",
}


# --- Data loading ---

def _load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def find_source(uuid_prefix: str) -> Path:
    """Find source file by UUID prefix."""
    candidates = list(SOURCES_DIR.glob(f"{uuid_prefix}*.json"))
    if len(candidates) == 0:
        raise FileNotFoundError(f"No source file matching {uuid_prefix}*.json in {SOURCES_DIR}")
    if len(candidates) > 1:
        raise ValueError(f"Multiple matches for {uuid_prefix}: {[c.name for c in candidates]}")
    return candidates[0]


def find_stage_file(stage: str, source_id: str) -> Path:
    """Construct the expected stage output path."""
    return STAGE_DIRS[stage] / f"{source_id}.json"


# --- Heuristic computation (inline, per-text-position) ---

_EPISTEMIC_PATTERN = re.compile(
    r"\b(the\s+user|the\s+speaker|the\s+assistant|the\s+person)\b",
    re.IGNORECASE,
)


def _count_words(text: str) -> int:
    return len(text.split())


def _count_punctuation(text: str) -> int:
    return sum(1 for ch in text if ch in ".,:;!?")


def compute_entry_heuristics(entry: dict) -> dict[str, Any]:
    """Compute per-stage heuristics for one assembled text entry."""
    heuristics: dict[str, Any] = {}

    # --- Normalize ---
    norm_output = entry.get("normalize", {}).get("output", {})
    norm_text = norm_output.get("text", "")
    word_count = _count_words(norm_text)
    if word_count > 0:
        punct_count = _count_punctuation(norm_text)
        punct_ratio = round(punct_count / word_count, 4)
        sentences_by_period = [s.strip() for s in norm_text.split(".") if s.strip()]
        max_sentence_words = max((_count_words(s) for s in sentences_by_period), default=0)
        heuristics["normalize"] = {
            "punctuation_ratio": punct_ratio,
            "max_sentence_words": max_sentence_words,
        }

    # --- Segment ---
    seg_output = entry.get("segment", {}).get("output", {})
    seg_sentences = seg_output.get("sentences", [])
    if seg_sentences:
        total_words = sum(_count_words(s["text"]) for s in seg_sentences)
        avg_sentence_words = round(total_words / len(seg_sentences), 1)
        heuristics["segment"] = {
            "sentence_count": len(seg_sentences),
            "avg_sentence_words": avg_sentence_words,
        }

    # --- Cohere ---
    cohere_spans = entry.get("cohere", {}).get("output", {}).get("spans", [])
    if cohere_spans and seg_sentences:
        sentences_by_id = {s["id"]: s["text"] for s in seg_sentences}
        span_word_counts = []
        span_sentence_counts = []
        for span in cohere_spans:
            span_sentence_counts.append(len(span["sentenceIds"]))
            span_text = " ".join(sentences_by_id.get(sid, "") for sid in span["sentenceIds"])
            span_word_counts.append(_count_words(span_text))
        avg_span_words = round(sum(span_word_counts) / len(span_word_counts), 1)
        avg_span_sentences = round(sum(span_sentence_counts) / len(span_sentence_counts), 1)
        heuristics["cohere"] = {
            "span_count": len(cohere_spans),
            "avg_span_words": avg_span_words,
            "avg_span_sentences": avg_span_sentences,
        }

    # --- Recohere ---
    recohere_output = entry.get("recohere", {}).get("output", {})
    recohere_merges = recohere_output.get("merges", [])
    recohere_spans = recohere_output.get("spans", [])
    input_span_count = len(cohere_spans) if cohere_spans else 0
    if input_span_count > 0:
        merge_rate = round(len(recohere_merges) / input_span_count, 4)
        heuristics["recohere"] = {
            "input_spans": input_span_count,
            "output_spans": len(recohere_spans),
            "merge_count": len(recohere_merges),
            "merge_rate": merge_rate,
        }

    # --- Filter ---
    filter_decisions = entry.get("filter", {}).get("decisions", [])
    if filter_decisions:
        extract_count = sum(1 for d in filter_decisions if d["label"] == "extract")
        skip_count = len(filter_decisions) - extract_count
        skip_rate = round(skip_count / len(filter_decisions), 4)
        heuristics["filter"] = {
            "total_spans": len(filter_decisions),
            "extract_count": extract_count,
            "skip_count": skip_count,
            "skip_rate": skip_rate,
        }

    # --- Decontext ---
    decontext_output = entry.get("decontext", {}).get("output", {})
    propositions = decontext_output.get("propositions", [])
    extract_span_count = decontext_output.get("extractSpanCount", 0)
    if propositions and extract_span_count > 0:
        props_per_span = round(len(propositions) / extract_span_count, 2)
        prop_word_counts = [_count_words(p["content"]) for p in propositions]
        avg_prop_words = round(sum(prop_word_counts) / len(prop_word_counts), 1)

        compound_count = sum(
            1 for p in propositions
            if p["content"].count(",") >= 3
            or len(re.findall(r"\band\b", p["content"], re.IGNORECASE)) >= 2
            or ";" in p["content"]
        )
        compound_rate = round(compound_count / len(propositions), 4)

        epistemic_count = sum(
            1 for p in propositions
            if _EPISTEMIC_PATTERN.search(p["content"])
        )
        epistemic_rate = round(epistemic_count / len(propositions), 4)

        heuristics["decontext"] = {
            "proposition_count": len(propositions),
            "extract_span_count": extract_span_count,
            "props_per_span": props_per_span,
            "avg_prop_words": avg_prop_words,
            "compound_rate": compound_rate,
            "epistemic_rate": epistemic_rate,
            "epistemic_violations": epistemic_count,
        }

    return heuristics


def compute_entry_metrics(entry: dict) -> dict[str, Any]:
    """Compute aggregate quality metrics for one assembled text entry."""
    metrics: dict[str, Any] = {}

    # Source size
    source_text = entry.get("source", {}).get("text", "")
    metrics["source_words"] = _count_words(source_text)

    # Final proposition count (after dedup removals)
    decontext_props = entry.get("decontext", {}).get("output", {}).get("propositions", [])
    dedup = entry.get("dedup", {})
    removed_indices = _compute_removed_indices(dedup)
    surviving_count = len(decontext_props) - len(removed_indices)
    metrics["total_propositions"] = len(decontext_props)
    metrics["surviving_propositions"] = surviving_count
    metrics["removed_by_dedup"] = len(removed_indices)

    # Compression ratio: source words / surviving propositions
    if surviving_count > 0:
        metrics["compression_ratio"] = round(metrics["source_words"] / surviving_count, 1)

    # Pipeline efficiency
    seg_sentences = entry.get("segment", {}).get("output", {}).get("sentences", [])
    filter_decisions = entry.get("filter", {}).get("decisions", [])
    extract_count = sum(1 for d in filter_decisions if d["label"] == "extract") if filter_decisions else 0
    metrics["sentence_count"] = len(seg_sentences)
    metrics["span_count_after_cohere"] = len(entry.get("cohere", {}).get("output", {}).get("spans", []))
    metrics["span_count_after_recohere"] = len(entry.get("recohere", {}).get("output", {}).get("spans", []))
    metrics["extract_span_count"] = extract_count

    return metrics


def _compute_removed_indices(dedup: dict) -> set[int]:
    """Compute set of proposition indices removed by dedup."""
    removed = set()
    for pair in dedup.get("pairs", []):
        if pair["decision"] == "bidirectional_entailment":
            removed.add(max(pair["indexA"], pair["indexB"]))
    for resolution in dedup.get("resolutions", []):
        removed.add(resolution["supersededIndex"])
    return removed


def compute_wm_diff(entry: dict) -> dict[str, Any]:
    """Compute the working memory diff from dedup results."""
    decontext_props = entry.get("decontext", {}).get("output", {}).get("propositions", [])
    dedup = entry.get("dedup", {})
    removed_indices = _compute_removed_indices(dedup)

    added = []
    superseded = []
    merged = []

    for i, prop in enumerate(decontext_props):
        if i in removed_indices:
            is_superseded = any(
                r["supersededIndex"] == i
                for r in dedup.get("resolutions", [])
            )
            if is_superseded:
                resolution = next(
                    r for r in dedup["resolutions"]
                    if r["supersededIndex"] == i
                )
                superseded.append({
                    "content": prop["content"],
                    "supersededBy": decontext_props[resolution["supersededBy"]]["content"]
                    if resolution["supersededBy"] < len(decontext_props) else "unknown",
                    "reason": resolution.get("reason", ""),
                })
            else:
                kept_index = _find_kept_duplicate(i, dedup)
                merged.append({
                    "removed": prop["content"],
                    "keptEquivalent": decontext_props[kept_index]["content"]
                    if kept_index is not None and kept_index < len(decontext_props)
                    else "unknown",
                })
        else:
            added.append({
                "content": prop["content"],
                "scope": prop.get("scope", ""),
                "type": prop.get("type", ""),
            })

    return {
        "added": added,
        "superseded": superseded,
        "merged": merged,
    }


def _find_kept_duplicate(removed_index: int, dedup: dict) -> int | None:
    """Find the kept proposition index for a bidirectional entailment removal."""
    for pair in dedup.get("pairs", []):
        if pair["decision"] == "bidirectional_entailment":
            higher = max(pair["indexA"], pair["indexB"])
            if higher == removed_index:
                return min(pair["indexA"], pair["indexB"])
    return None


# --- Text entry assembly ---

def assemble_entry(
    text_index: int,
    source_text: str,
    stage_data: dict[str, dict],
    dedup_data: dict,
    source_id: str,
) -> dict:
    """Assemble one text position from per-stage results. Direct passthrough."""
    estimated_tokens = int(_count_words(source_text) * 1.3)

    entry = {
        "entryId": str(uuid.uuid4()),
        "sourceId": source_id,
        "textIndex": text_index,
        "generator": "claude-code",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": {
            "text": source_text,
            "estimatedTokens": estimated_tokens,
        },
    }

    # Direct passthrough: position N in results -> entry N
    for stage_name in ("normalize", "segment", "cohere", "recohere", "filter", "decontext"):
        results = stage_data.get(stage_name, {}).get("results", [])
        if text_index < len(results):
            result = results[text_index]
            entry[stage_name] = {
                "input": result.get("input", {}),
                "output": result.get("output", {}),
            }
            # Filter stage stores decisions at top level of result
            if stage_name == "filter" and "decisions" in result:
                entry[stage_name] = {"decisions": result["decisions"]}
        else:
            entry[stage_name] = {}

    # Dedup: extract pairs relevant to this text position
    entry["dedup"] = _extract_text_dedup(text_index, dedup_data)

    # Working memory diff
    entry["workingMemoryDiff"] = compute_wm_diff(entry)

    # Heuristics and metrics
    entry["heuristics"] = compute_entry_heuristics(entry)
    entry["metrics"] = compute_entry_metrics(entry)

    return entry


def _extract_text_dedup(text_index: int, dedup_data: dict) -> dict:
    """Extract dedup pairs relevant to a specific text index.

    Pairs have textIndexA/textIndexB fields. Include pairs where at least
    one proposition comes from this text position.
    """
    all_pairs = dedup_data.get("pairs", [])
    all_resolutions = dedup_data.get("resolutions", [])

    text_pairs = [
        p for p in all_pairs
        if p.get("textIndexA") == text_index or p.get("textIndexB") == text_index
    ]

    # Proposition indices belonging to this text
    text_prop_indices = set()
    for p in all_pairs:
        if p.get("textIndexA") == text_index:
            text_prop_indices.add(p["indexA"])
        if p.get("textIndexB") == text_index:
            text_prop_indices.add(p["indexB"])

    text_resolutions = [
        r for r in all_resolutions
        if r["supersededIndex"] in text_prop_indices
        or r["supersededBy"] in text_prop_indices
    ]

    entailment_count = sum(
        1 for p in text_pairs
        if p["decision"] in ("bidirectional_entailment", "forward_entailment")
    )
    contradiction_count = sum(
        1 for p in text_pairs
        if p["decision"] == "contradiction"
    )

    return {
        "totalPropositions": len(text_prop_indices),
        "pairs": text_pairs,
        "resolutions": text_resolutions,
        "summary": {
            "entailment": entailment_count,
            "contradiction": contradiction_count,
            "noMatch": len(text_pairs) - entailment_count - contradiction_count,
        },
    }


# --- Main assembly ---

def assemble_source(uuid_prefix: str) -> list[dict]:
    """Assemble all text entries for a source."""
    source_path = find_source(uuid_prefix)
    source = _load_json(source_path)
    source_id = source["sourceId"]
    texts = source["texts"]

    print(f"Assembling source: {source_id}")
    print(f"Text count: {len(texts)}")

    # Load all stage files
    stage_data = {}
    for stage_name in STAGE_DIRS:
        stage_path = find_stage_file(stage_name, source_id)
        if not stage_path.exists():
            print(f"  WARNING: Missing {stage_name} output: {stage_path.name}")
            stage_data[stage_name] = {}
            continue
        stage_data[stage_name] = _load_json(stage_path)
        print(f"  Loaded {stage_name}: {stage_path.name}")

    dedup_data = stage_data.get("dedup", {})

    # Assemble each text entry
    entries = []
    for text_index, source_text in enumerate(texts):
        entry = assemble_entry(
            text_index=text_index,
            source_text=source_text,
            stage_data=stage_data,
            dedup_data=dedup_data,
            source_id=source_id,
        )
        entries.append(entry)

    return entries


def write_entries(entries: list[dict], source_id: str) -> list[Path]:
    """Write assembled entries to the unified_runs directory."""
    output_dir = UNIFIED_DIR / source_id
    output_dir.mkdir(parents=True, exist_ok=True)

    written_paths = []
    for entry in entries:
        text_index = entry["textIndex"]
        output_path = output_dir / f"text_{text_index:03d}.json"
        _write_json(output_path, entry)
        written_paths.append(output_path)

    return written_paths


def print_summary(entries: list[dict]) -> None:
    """Print a summary of the assembled entries."""
    print(f"\n{'='*60}")
    print(f"ASSEMBLY SUMMARY")
    print(f"{'='*60}")
    print(f"Entries assembled: {len(entries)}")

    total_props = 0
    total_surviving = 0
    total_source_words = 0
    red_flag_count = 0

    for entry in entries:
        idx = entry["textIndex"]
        m = entry.get("metrics", {})
        h = entry.get("heuristics", {})

        props = m.get("total_propositions", 0)
        surviving = m.get("surviving_propositions", 0)
        source_words = m.get("source_words", 0)
        total_props += props
        total_surviving += surviving
        total_source_words += source_words

        # Check for heuristic red flags
        entry_flags = []
        decontext_h = h.get("decontext", {})
        if decontext_h.get("epistemic_violations", 0) > 0:
            entry_flags.append(f"epistemic:{decontext_h['epistemic_violations']}")

        flag_str = f" [{', '.join(entry_flags)}]" if entry_flags else ""
        print(f"  Text {idx}: {source_words} words -> {props} props -> {surviving} surviving{flag_str}")
        red_flag_count += len(entry_flags)

    print(f"\nTotals:")
    print(f"  Source words: {total_source_words}")
    print(f"  Propositions: {total_props}")
    print(f"  Surviving after dedup: {total_surviving}")
    if total_surviving > 0:
        print(f"  Overall compression: {round(total_source_words / total_surviving, 1)} words/prop")
    if red_flag_count > 0:
        print(f"\n  WARNING: {red_flag_count} red flags detected -- review heuristics in entry files")
    else:
        print(f"\n  OK: No red flags")


# --- CLI ---

def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python assemble_golden.py <uuid_prefix>")
        sys.exit(1)

    uuid_prefix = sys.argv[1]

    entries = assemble_source(uuid_prefix)
    source_id = entries[0]["sourceId"] if entries else "unknown"

    written = write_entries(entries, source_id)
    print(f"\nWrote {len(written)} entry files to:")
    for p in written:
        print(f"  {p}")

    print_summary(entries)


if __name__ == "__main__":
    main()
