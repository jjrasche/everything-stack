"""Convert golden conversations to source-agnostic pipeline input.

Reads conversation files from golden/turns/conv_*.json.
Writes pipeline input to golden/sources/<uuid>.json.

Each output file has a sourceId and an array of text strings.
The pipeline never sees prompts, responses, speakers, or turns.

Usage:
    python prepare_sources.py              # Convert all
    python prepare_sources.py <uuid_prefix> # Convert one by prefix
"""

import json
import sys
from pathlib import Path

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden"
TURNS_DIR = GOLDEN_DIR / "turns"
SOURCES_DIR = GOLDEN_DIR / "sources"


def _load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def convert_conversation(conv_path: Path) -> dict:
    """Read a conversation file, return source-agnostic format."""
    conv = _load_json(conv_path)
    texts = []
    for turn in conv["turns"]:
        combined = turn["prompt"] + "\n\n" + turn["response"]
        texts.append(combined)
    return {
        "sourceId": conv["convUuid"],
        "texts": texts,
    }


def convert_all() -> list[Path]:
    """Convert all conversation files."""
    written = []
    for conv_path in sorted(TURNS_DIR.glob("conv_*.json")):
        source = convert_conversation(conv_path)
        output_path = SOURCES_DIR / f"{source['sourceId']}.json"
        _write_json(output_path, source)
        word_count = sum(len(t.split()) for t in source["texts"])
        print(f"  {conv_path.stem} -> {output_path.name} ({len(source['texts'])} texts, {word_count} words)")
        written.append(output_path)
    return written


def convert_one(uuid_prefix: str) -> Path:
    """Convert one conversation file by UUID prefix."""
    candidates = list(TURNS_DIR.glob(f"conv_{uuid_prefix}*.json"))
    if not candidates:
        raise FileNotFoundError(f"No file matching conv_{uuid_prefix}*.json in {TURNS_DIR}")
    if len(candidates) > 1:
        raise ValueError(f"Multiple matches: {[c.name for c in candidates]}")
    source = convert_conversation(candidates[0])
    output_path = SOURCES_DIR / f"{source['sourceId']}.json"
    _write_json(output_path, source)
    word_count = sum(len(t.split()) for t in source["texts"])
    print(f"  {candidates[0].stem} -> {output_path.name} ({len(source['texts'])} texts, {word_count} words)")
    return output_path


def main() -> None:
    if len(sys.argv) > 1:
        path = convert_one(sys.argv[1])
        print(f"\nWrote: {path}")
    else:
        written = convert_all()
        print(f"\nConverted {len(written)} sources to {SOURCES_DIR}")


if __name__ == "__main__":
    main()
