"""Analyze cohere output turns and select 25 for golden label review set."""

import json
import os
import glob
import sys

COHERE_DIR = "lib/training/extraction/golden/cohere_output"
SEGMENT_DIR = "lib/training/extraction/golden/segment_output"
OUTPUT_DIR = "lib/training/extraction/golden/labels/cohere"


def load_all_turns():
    """Load all turns from cohere + segment output, return enriched turn list."""
    all_turns = []

    for cohere_file in sorted(glob.glob(os.path.join(COHERE_DIR, "*.json"))):
        conv_uuid = os.path.basename(cohere_file).replace(".json", "")
        segment_file = os.path.join(SEGMENT_DIR, os.path.basename(cohere_file))

        with open(cohere_file, "r", encoding="utf-8") as f:
            cohere_data = json.load(f)
        with open(segment_file, "r", encoding="utf-8") as f:
            segment_data = json.load(f)

        conv_name = cohere_data.get("conversationName", "")

        # Build lookup: (turnIndex, speaker) -> sentences from segment output
        seg_lookup = {}
        for seg_turn in segment_data["turns"]:
            key = (seg_turn["turnIndex"], seg_turn["speaker"])
            seg_lookup[key] = seg_turn["sentences"]

        for turn in cohere_data["turns"]:
            turn_index = turn["turnIndex"]
            speaker = turn["speaker"]
            sentence_count = turn["sentenceCount"]
            span_count = turn["spanCount"]
            boundary_count = turn["boundaryCount"]
            pair_scores = turn["pairScores"]
            spans = turn["spans"]

            scores = [p["coherenceScore"] for p in pair_scores]

            if not scores:
                continue

            all_confident = all(s > 0.85 or s < 0.15 for s in scores)
            moderate_scores = [s for s in scores if 0.15 <= s <= 0.45]
            uncertain_scores = [s for s in scores if 0.35 <= s <= 0.65]
            is_under_split = span_count == 1 and sentence_count >= 10

            seg_key = (turn_index, speaker)
            sentences = seg_lookup.get(seg_key, [])

            all_turns.append({
                "convUuid": conv_uuid,
                "convName": conv_name,
                "turnIndex": turn_index,
                "speaker": speaker,
                "sentenceCount": sentence_count,
                "spanCount": span_count,
                "boundaryCount": boundary_count,
                "pairScores": pair_scores,
                "spans": spans,
                "sentences": sentences,
                "scores": scores,
                "allConfident": all_confident,
                "moderateCount": len(moderate_scores),
                "uncertainCount": len(uncertain_scores),
                "isUnderSplit": is_under_split,
            })

    return all_turns


def avg_sentence_length(turn):
    """Mean character count across sentences. Filters out table-fragment turns."""
    sents = turn["sentences"]
    if not sents:
        return 0
    return sum(len(s["text"]) for s in sents) / len(sents)


def has_prose(turn, min_avg_len=40):
    """True when sentences are real prose, not table cell fragments."""
    return avg_sentence_length(turn) >= min_avg_len


def category_count(selected, category):
    """Count how many turns already picked for a given category."""
    return sum(1 for cat, _ in selected if cat == category)


def select_turns(all_turns):
    """Select 25 turns across 5 difficulty categories."""
    selected = []
    used_keys = set()

    def make_key(t):
        return (t["convUuid"], t["turnIndex"], t["speaker"])

    def is_available(t):
        return make_key(t) not in used_keys

    def mark(t, category):
        used_keys.add(make_key(t))
        selected.append((category, t))

    def pick_diverse(pool, category, count=5):
        """Pick up to `count` turns from pool, one per conversation."""
        seen_convs = set()
        for t in pool:
            if not is_available(t):
                continue
            if t["convUuid"] in seen_convs:
                continue
            seen_convs.add(t["convUuid"])
            mark(t, category)
            if category_count(selected, category) >= count:
                break

    # --- CAT 1: Confidently correct ---
    # All pairs >0.85 or <0.15. Mix: 3 with boundaries + 2 without.
    # Require real prose (avg sentence >= 40 chars) and 5+ sentences.
    confident_with_bounds = [
        t for t in all_turns
        if t["allConfident"]
        and t["sentenceCount"] >= 5
        and t["boundaryCount"] > 0
        and has_prose(t)
    ]
    confident_with_bounds.sort(
        key=lambda t: (t["boundaryCount"], t["sentenceCount"]), reverse=True
    )
    pick_diverse(confident_with_bounds, "confident_correct", count=3)

    confident_no_bounds = [
        t for t in all_turns
        if t["allConfident"]
        and t["sentenceCount"] >= 8
        and t["boundaryCount"] == 0
        and has_prose(t)
    ]
    confident_no_bounds.sort(key=lambda t: t["sentenceCount"], reverse=True)
    pick_diverse(confident_no_bounds, "confident_correct", count=5)

    # --- CAT 2: Moderate confidence ---
    # Has scores in 0.15-0.45 range. Require 4+ sentences for meaningful review.
    moderate = [
        t for t in all_turns
        if t["moderateCount"] > 0
        and t["sentenceCount"] >= 4
        and has_prose(t)
    ]
    moderate.sort(
        key=lambda t: (
            t["moderateCount"] / max(len(t["scores"]), 1),
            t["moderateCount"],
        ),
        reverse=True,
    )
    pick_diverse(moderate, "moderate_confidence", count=5)

    # --- CAT 3: Hard/uncertain ---
    # Scores in 0.35-0.65. Require 4+ sentences.
    uncertain = [
        t for t in all_turns
        if t["uncertainCount"] > 0
        and t["sentenceCount"] >= 4
        and has_prose(t)
    ]
    uncertain.sort(
        key=lambda t: (
            t["uncertainCount"] / max(len(t["scores"]), 1),
            t["uncertainCount"],
        ),
        reverse=True,
    )
    pick_diverse(uncertain, "hard_uncertain", count=5)

    # --- CAT 4: Under-split ---
    # Single span, 10+ sentences. Require real prose.
    under_split = [
        t for t in all_turns
        if t["isUnderSplit"]
        and has_prose(t)
    ]
    under_split.sort(key=lambda t: t["sentenceCount"], reverse=True)
    pick_diverse(under_split, "under_split", count=5)

    # --- CAT 5: Most spans ---
    # Highest span count. No sentence-count minimum (more spans = more content).
    most_spans = sorted(
        [t for t in all_turns if has_prose(t)],
        key=lambda t: t["spanCount"],
        reverse=True,
    )
    pick_diverse(most_spans, "most_spans", count=5)

    return selected


def build_review_entry(category, turn_data):
    """Build a single review_set.json entry from a selected turn."""
    model_decisions = []
    for pair_score in turn_data["pairScores"]:
        model_decisions.append({
            "pair": pair_score["pair"],
            "score": pair_score["coherenceScore"],
            "boundary": pair_score["boundary"],
        })

    model_spans = []
    for span in turn_data["spans"]:
        model_spans.append({
            "spanId": span["spanId"],
            "sentenceIds": span["sentenceIds"],
        })

    return {
        "convUuid": turn_data["convUuid"],
        "convName": turn_data["convName"],
        "turnIndex": turn_data["turnIndex"],
        "speaker": turn_data["speaker"],
        "selectionCategory": category,
        "sentences": turn_data["sentences"],
        "modelDecisions": model_decisions,
        "modelSpans": model_spans,
        "humanBoundaries": None,
    }


def main():
    print("Loading all turns...")
    all_turns = load_all_turns()
    print(f"Total turns: {len(all_turns)}")

    print("\nSelecting 25 turns...")
    selected = select_turns(all_turns)

    # Print selection summary
    categories = {}
    for cat, t in selected:
        categories.setdefault(cat, []).append(t)

    for cat_name, turns in categories.items():
        print(f"\n{cat_name} ({len(turns)} turns):")
        for t in turns:
            scores = t["scores"]
            print(
                f"  {t['convUuid'][:8]} t{t['turnIndex']} {t['speaker']} "
                f"sents={t['sentenceCount']} spans={t['spanCount']} "
                f"scores={min(scores):.3f}-{max(scores):.3f}"
            )

    # Build output
    review_set = []
    for cat, t in selected:
        entry = build_review_entry(cat, t)
        review_set.append(entry)

    # Write output
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    output_path = os.path.join(OUTPUT_DIR, "review_set.json")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(review_set, f, indent=2, ensure_ascii=False)

    print(f"\nWrote {len(review_set)} entries to {output_path}")

    # Summary stats
    conv_counts = {}
    for cat, t in selected:
        short = t["convUuid"][:8]
        conv_counts[short] = conv_counts.get(short, 0) + 1

    print(f"Unique conversations: {len(conv_counts)}")
    for c, n in sorted(conv_counts.items(), key=lambda x: x[1], reverse=True):
        if n > 1:
            print(f"  {c}: {n} turns")

    # Verify all entries have sentences
    missing = [e for e in review_set if not e["sentences"]]
    if missing:
        print(f"\nWARNING: {len(missing)} entries missing sentences!")
        for e in missing:
            print(f"  {e['convUuid'][:8]} t{e['turnIndex']} {e['speaker']}")


if __name__ == "__main__":
    main()
