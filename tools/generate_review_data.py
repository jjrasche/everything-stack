"""Generate data for pipeline_review.html from unified runs.

Reads unified_runs/ and produces review_data.json with:
- Raw source text + normalize diffs
- Span regions with filter decisions and propositions
- Entailment matrix for Stage 7 view

Usage:
    python generate_review_data.py
    python generate_review_data.py <uuid_prefix>
"""

import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden"
SOURCES_DIR = GOLDEN_DIR / "sources"
UNIFIED_DIR = GOLDEN_DIR / "unified_runs"
OUTPUT_PATH = Path(__file__).resolve().parent / "review_data.json"


def load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def compute_normalize_diffs(raw: str, normalized: str) -> list[dict]:
    """Compute character-level diffs between raw and normalized text."""
    diffs = []
    matcher = SequenceMatcher(None, raw, normalized)

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'delete':
            diffs.append({
                'start': i1,
                'end': i2,
                'type': 'removed',
                'text': raw[i1:i2]
            })
        elif tag == 'replace':
            diffs.append({
                'start': i1,
                'end': i2,
                'type': 'replaced',
                'oldText': raw[i1:i2],
                'newText': normalized[j1:j2]
            })
        elif tag == 'insert':
            diffs.append({
                'start': i1,
                'end': i1,
                'type': 'inserted',
                'text': normalized[j1:j2]
            })

    return diffs


def build_sentence_map(segment_output: dict) -> dict[str, str]:
    """Build sentence ID -> text mapping from segment output."""
    sentences = segment_output.get('sentences', [])
    return {s['id']: s['text'] for s in sentences}


def compute_span_char_ranges(spans: list[dict], sentence_map: dict[str, str], text: str) -> list[dict]:
    """Compute character start/end positions for each span."""
    result = []
    char_pos = 0

    # Build sentence -> char position mapping
    sentence_positions = {}
    for sid, stext in sentence_map.items():
        idx = text.find(stext, char_pos)
        if idx >= 0:
            sentence_positions[sid] = (idx, idx + len(stext))
            char_pos = idx + len(stext)

    # Compute span ranges from sentence ranges
    for span in spans:
        sentence_ids = span.get('sentenceIds', [])
        if not sentence_ids:
            continue

        start = min(sentence_positions.get(sid, (0, 0))[0] for sid in sentence_ids if sid in sentence_positions)
        end = max(sentence_positions.get(sid, (0, 0))[1] for sid in sentence_ids if sid in sentence_positions)

        result.append({
            'spanId': span.get('spanId', ''),
            'sentenceIds': sentence_ids,
            'startChar': start,
            'endChar': end,
        })

    return result


def transform_unified_run(source_id: str, unified_texts: list[dict], source_data: dict) -> dict:
    """Transform unified run files into review data format."""
    texts = []
    all_propositions = []
    prop_id_counter = 0

    for unified in unified_texts:
        text_index = unified.get('textIndex', 0)

        # Raw and normalized text
        raw_text = unified.get('source', {}).get('text', '')
        norm_output = unified.get('normalize', {}).get('output', {})
        normalized_text = norm_output.get('text', raw_text)

        # Compute normalize diffs
        norm_diffs = compute_normalize_diffs(raw_text, normalized_text)

        # Get segment data for sentence mapping
        segment_output = unified.get('segment', {}).get('output', {})
        sentence_map = build_sentence_map(segment_output)

        # Get spans from recohere (or cohere if no recohere)
        recohere_output = unified.get('recohere', {}).get('output', {})
        cohere_output = unified.get('cohere', {}).get('output', {})
        spans_raw = recohere_output.get('spans', cohere_output.get('spans', []))

        # Compute character ranges for spans
        span_ranges = compute_span_char_ranges(spans_raw, sentence_map, raw_text)

        # Get filter decisions
        filter_data = unified.get('filter', {})
        filter_decisions = filter_data.get('decisions', [])
        decision_map = {d['spanId']: d for d in filter_decisions}

        # Get propositions from decontext
        decontext_output = unified.get('decontext', {}).get('output', {})
        propositions_raw = decontext_output.get('propositions', [])

        # Build spans with all data
        spans = []
        for span_range in span_ranges:
            span_id = span_range['spanId']
            decision = decision_map.get(span_id, {})

            # Find propositions that came from this span's sentences
            span_sentence_ids = set(span_range['sentenceIds'])
            span_props = []
            for prop in propositions_raw:
                prop_sources = set(prop.get('sourceIds', []))
                if prop_sources & span_sentence_ids:
                    span_props.append({
                        'content': prop.get('content', ''),
                        'scope': prop.get('scope', 'unknown'),
                        'type': prop.get('type', 'unknown'),
                    })

            spans.append({
                'spanId': span_id,
                'sentenceIds': span_range['sentenceIds'],
                'startChar': span_range['startChar'],
                'endChar': span_range['endChar'],
                'filterLabel': decision.get('label', 'extract'),
                'extractScore': decision.get('extractScore', 0.5),
                'propositions': span_props,
            })

        # Collect all propositions for this source
        for prop in propositions_raw:
            all_propositions.append({
                'id': f'p_{prop_id_counter}',
                'content': prop.get('content', ''),
                'scope': prop.get('scope', 'unknown'),
                'type': prop.get('type', 'unknown'),
                'textIndex': text_index,
                'sourceIds': prop.get('sourceIds', []),
            })
            prop_id_counter += 1

        texts.append({
            'textIndex': text_index,
            'rawText': raw_text,
            'normalizedText': normalized_text,
            'normalizeDiffs': norm_diffs,
            'spans': spans,
        })

    # Build entailment matrix from dedup data
    entailment_matrix = []
    if unified_texts:
        # Collect all dedup pairs across texts
        for unified in unified_texts:
            dedup = unified.get('dedup', {})
            for pair in dedup.get('pairs', []):
                entailment_matrix.append({
                    'idxA': pair.get('indexA', 0),
                    'idxB': pair.get('indexB', 0),
                    'label': pair.get('decision', 'neutral'),
                    'entailScore': pair.get('entailmentScore', 0),
                    'contradictScore': pair.get('contradictionScore', 0),
                })

    # Build clusters by grouping propositions with similar entailment patterns
    clusters = cluster_propositions(all_propositions, entailment_matrix)

    return {
        'sourceId': source_id,
        'name': source_data.get('name', source_id[:8]),
        'textCount': len(texts),
        'texts': texts,
        'propositions': all_propositions,
        'entailmentMatrix': entailment_matrix,
        'clusters': clusters,
    }


def cluster_propositions(propositions: list[dict], matrix: list[dict]) -> list[dict]:
    """Cluster propositions by similarity of entailment relationships."""
    if not propositions:
        return []

    # Build adjacency: which propositions have strong relationships
    strong_relations = {}
    for prop in propositions:
        strong_relations[prop['id']] = set()

    for rel in matrix:
        score = max(rel.get('entailScore', 0), rel.get('contradictScore', 0))
        if score > 0.5:
            id_a = f"p_{rel['idxA']}"
            id_b = f"p_{rel['idxB']}"
            if id_a in strong_relations:
                strong_relations[id_a].add(id_b)
            if id_b in strong_relations:
                strong_relations[id_b].add(id_a)

    # Simple clustering: group by scope + type, then by relationship pattern
    groups = {}
    for prop in propositions:
        key = f"{prop['scope']}_{prop['type']}"
        if key not in groups:
            groups[key] = []
        groups[key].append(prop['id'])

    clusters = []
    for key, prop_ids in groups.items():
        scope, ptype = key.split('_', 1)
        clusters.append({
            'id': f'cluster_{len(clusters)}',
            'name': f'{scope.title()} {ptype.title()}',
            'propIds': prop_ids,
        })

    # If no meaningful clusters, put all in one
    if len(clusters) == 1 and clusters[0]['name'] == 'Unknown Unknown':
        clusters[0]['name'] = 'All Propositions'

    return clusters


def generate_review_data(uuid_prefix: str | None = None) -> dict:
    """Generate review data for all sources or a specific one."""
    if not UNIFIED_DIR.exists():
        print(f"No unified runs at {UNIFIED_DIR}")
        return {'sources': {}}

    sources = {}

    # Find source directories
    source_dirs = sorted(UNIFIED_DIR.iterdir()) if UNIFIED_DIR.exists() else []

    if uuid_prefix:
        source_dirs = [d for d in source_dirs if d.name.startswith(uuid_prefix)]

    for source_dir in source_dirs:
        if not source_dir.is_dir():
            continue

        source_id = source_dir.name
        print(f"Processing {source_id}...")

        # Load source metadata
        source_file = SOURCES_DIR / f"{source_id}.json"
        source_data = load_json(source_file) if source_file.exists() else {}

        # Load unified text files
        unified_files = sorted(source_dir.glob("text_*.json"))
        unified_texts = [load_json(f) for f in unified_files]

        if not unified_texts:
            print(f"  No unified text files found")
            continue

        # Transform to review format
        sources[source_id] = transform_unified_run(source_id, unified_texts, source_data)
        print(f"  {len(unified_texts)} texts, {len(sources[source_id]['propositions'])} propositions")

    return {'sources': sources}


def main():
    uuid_prefix = sys.argv[1] if len(sys.argv) > 1 else None

    data = generate_review_data(uuid_prefix)

    if not data['sources']:
        print("No data generated. Make sure unified_runs/ has data.")
        return

    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"\nWrote {OUTPUT_PATH}")
    print(f"Sources: {len(data['sources'])}")


if __name__ == "__main__":
    main()
