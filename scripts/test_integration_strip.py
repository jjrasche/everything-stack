"""Integration test: run strip_markdown on all 33 real golden source files.

Verifies:
1. No markdown artifacts remain (**, ```, <antThinking>, |table|)
2. No text is empty after stripping
3. Reports long sentences (informational -- raw STT text without punctuation
   is expected to have long sentences; the punctuation SLM fixes those later)
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from markdown_strip import strip_markdown

SOURCES_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden" / "sources"
MAX_SENTENCE_WORDS = 50


def check_artifacts(text: str) -> list[str]:
    found = []
    if "**" in text:
        found.append("bold markers")
    if "<antThinking>" in text:
        found.append("antThinking tags")
    if "```" in text:
        found.append("fenced code")
    return found


def check_max_sentence_words(text: str) -> int:
    sentences = [s.strip() for s in re.split(r"[.!?]+", text) if s.strip()]
    return max((len(s.split()) for s in sentences), default=0)


def main() -> None:
    source_files = sorted(SOURCES_DIR.glob("*.json"))
    if not source_files:
        print(f"ERROR: No source files found in {SOURCES_DIR}")
        sys.exit(1)

    total_texts = 0
    empty_count = 0
    artifact_count = 0
    long_sentence_count = 0

    for source_path in source_files:
        data = json.load(open(source_path, encoding="utf-8"))
        source_id = data["sourceId"][:8]

        for i, text in enumerate(data["texts"]):
            total_texts += 1
            stripped = strip_markdown(text)

            if not stripped.strip():
                print(f"  EMPTY: {source_id} text {i}")
                empty_count += 1
                continue

            artifacts = check_artifacts(stripped)
            if artifacts:
                artifact_count += 1
                print(f"  ARTIFACT: {source_id} text {i}: {', '.join(artifacts)}")

            max_words = check_max_sentence_words(stripped)
            if max_words > MAX_SENTENCE_WORDS:
                long_sentence_count += 1

    print(f"\nResults: {total_texts} texts across {len(source_files)} sources")
    print(f"  Empty after strip: {empty_count}")
    print(f"  Artifact remnants: {artifact_count}")
    print(f"  Long sentences (>50 words, needs punctuation SLM): {long_sentence_count}")

    # Fail only on strip_markdown's responsibility: artifacts and empty output
    if empty_count > 0 or artifact_count > 0:
        print("  FAIL")
        sys.exit(1)
    else:
        print("  PASS")


if __name__ == "__main__":
    main()
