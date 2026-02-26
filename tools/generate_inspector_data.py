"""Generate inspector_data.json for the encoder visual inspector.

Reads unified_runs/ + sources/ + evaluation/ and produces a single
JSON file that the HTML inspector loads client-side.

Usage:
    python generate_inspector_data.py
"""

import json
import os
from pathlib import Path

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden"
SOURCES_DIR = GOLDEN_DIR / "sources"
UNIFIED_DIR = GOLDEN_DIR / "unified_runs"
EVAL_DIR = GOLDEN_DIR / "evaluation"
OUTPUT_PATH = Path(__file__).resolve().parent / "inspector_data.json"


def load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_sentence_map(sentences: list[dict]) -> dict[str, str]:
    return {s["id"]: s["text"] for s in sentences}


def find_span_for_sentence(sentence_id: str, spans: list[dict]) -> str | None:
    for span in spans:
        if sentence_id in span.get("sentenceIds", []):
            return span["spanId"]
    return None


def build_filter_map(filter_data: dict) -> dict[str, dict]:
    result = {}
    decisions = filter_data.get("decisions", [])
    for d in decisions:
        result[d["spanId"]] = {
            "label": d["label"],
            "extractScore": d.get("extractScore", 0),
            "skipScore": d.get("skipScore", 0),
        }
    return result


def process_source(source_id: str) -> dict | None:
    source_path = SOURCES_DIR / f"{source_id}.json"
    source_dir = UNIFIED_DIR / source_id

    if not source_path.exists() or not source_dir.exists():
        return None

    source_data = load_json(source_path)
    source_texts = source_data["texts"]
    word_count = sum(len(t.split()) for t in source_texts)

    eval_path = EVAL_DIR / f"{source_id}_eval.json"
    evaluation = None
    eval_propositions = {}
    if eval_path.exists():
        eval_data = load_json(eval_path)
        evaluation = eval_data.get("evaluation", {})
        for ep in eval_data.get("propositions", []):
            eval_propositions[ep["content"]] = ep

    run_files = sorted(source_dir.glob("text_*.json"))
    texts = []
    cumulative_wm = []
    active_wm: list[dict] = []

    for run_file in run_files:
        run = load_json(run_file)
        text_index = run["textIndex"]

        sentences = run.get("segment", {}).get("output", {}).get("sentences", [])
        sentence_map = build_sentence_map(sentences)

        recohere_spans = run.get("recohere", {}).get("output", {}).get("spans", [])
        if not recohere_spans:
            recohere_spans = run.get("cohere", {}).get("output", {}).get("spans", [])

        filter_map = build_filter_map(run.get("filter", {}))

        spans_out = []
        for span in recohere_spans:
            span_id = span["spanId"]
            sent_ids = span.get("sentenceIds", [])
            span_text = " ".join(sentence_map.get(sid, "") for sid in sent_ids)
            filt = filter_map.get(span_id, {"label": "unknown", "extractScore": 0, "skipScore": 0})
            spans_out.append({
                "spanId": span_id,
                "sentenceIds": sent_ids,
                "text": span_text,
                "filterLabel": filt["label"],
                "extractScore": filt["extractScore"],
                "skipScore": filt["skipScore"],
            })

        propositions = run.get("decontext", {}).get("output", {}).get("propositions", [])

        wm_diff = run.get("workingMemoryDiff", {})
        added = wm_diff.get("added", [])
        superseded = wm_diff.get("superseded", [])
        merged = wm_diff.get("merged", [])

        superseded_contents = {s["content"] for s in superseded}
        merged_contents = {m["removed"] for m in merged}

        active_wm = [
            p for p in active_wm
            if p["content"] not in superseded_contents and p["content"] not in merged_contents
        ]

        for prop in added:
            eval_info = eval_propositions.get(prop["content"])
            active_wm.append({
                "content": prop["content"],
                "scope": prop.get("scope", "unknown"),
                "type": prop.get("type", "unknown"),
                "fromTextIndex": text_index,
                "evalScores": eval_info.get("scores") if eval_info else None,
                "evalVerdict": eval_info.get("verdict") if eval_info else None,
            })

        prop_to_span = {}
        for prop in propositions:
            source_ids = prop.get("sourceIds", [])
            matched_span = None
            for sid in source_ids:
                matched_span = find_span_for_sentence(sid, recohere_spans)
                if matched_span:
                    break
            if matched_span:
                prop_to_span[prop["content"]] = matched_span

        propositions_out = []
        for prop in propositions:
            eval_info = eval_propositions.get(prop["content"])
            propositions_out.append({
                "content": prop["content"],
                "scope": prop.get("scope", "unknown"),
                "type": prop.get("type", "unknown"),
                "sourceIds": prop.get("sourceIds", []),
                "linkedSpanId": prop_to_span.get(prop["content"]),
                "evalScores": eval_info.get("scores") if eval_info else None,
                "evalVerdict": eval_info.get("verdict") if eval_info else None,
            })

        added_out = []
        for prop in added:
            eval_info = eval_propositions.get(prop["content"])
            added_out.append({
                "content": prop["content"],
                "scope": prop.get("scope", "unknown"),
                "type": prop.get("type", "unknown"),
                "linkedSpanId": prop_to_span.get(prop["content"]),
                "evalScores": eval_info.get("scores") if eval_info else None,
                "evalVerdict": eval_info.get("verdict") if eval_info else None,
            })

        superseded_out = []
        for s in superseded:
            superseded_out.append({
                "content": s["content"],
                "supersededBy": s.get("supersededBy") or s.get("keptEquivalent", ""),
            })

        merged_out = []
        for m in merged:
            merged_out.append({
                "removed": m["removed"],
                "keptEquivalent": m.get("keptEquivalent", ""),
            })

        metrics = run.get("metrics", {})

        texts.append({
            "textIndex": text_index,
            "sourceText": source_texts[text_index] if text_index < len(source_texts) else "",
            "sentences": [{"id": s["id"], "text": s["text"]} for s in sentences],
            "spans": spans_out,
            "propositions": propositions_out,
            "wmDiff": {
                "added": added_out,
                "superseded": superseded_out,
                "merged": merged_out,
            },
            "metrics": metrics,
        })

        cumulative_wm.append([
            {"content": p["content"], "scope": p["scope"], "type": p["type"], "fromTextIndex": p["fromTextIndex"]}
            for p in active_wm
        ])

    return {
        "sourceId": source_id,
        "textCount": len(source_texts),
        "wordCount": word_count,
        "evaluation": evaluation,
        "texts": texts,
        "cumulativeWM": cumulative_wm,
    }


def main() -> None:
    source_ids = sorted(
        d.name for d in UNIFIED_DIR.iterdir() if d.is_dir()
    )
    print(f"Found {len(source_ids)} sources with unified runs")

    sources = {}
    for sid in source_ids:
        print(f"  Processing {sid[:8]}...", end=" ")
        result = process_source(sid)
        if result:
            sources[sid] = result
            print(f"{result['textCount']} texts, {len(result['texts'])} runs")
        else:
            print("SKIPPED (missing data)")

    output = {"sources": sources}
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    size_kb = OUTPUT_PATH.stat().st_size / 1024
    print(f"\nWrote {OUTPUT_PATH.name} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
