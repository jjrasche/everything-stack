"""End-to-end pipeline evaluation.

Scores every proposition in a source's final working memory on 6 dimensions:
  grounded, atomic, bare_assertive, non_redundant, durable, self_contained

Phase 1: Deterministic checks (atomic, bare_assertive, self_contained) run in Python.
Phase 2: LLM evaluation (grounded, non_redundant, durable) via Claude agent.
Phase 3: Aggregate metrics and write evaluation JSON.

Usage:
    python evaluate_pipeline.py <source_uuid_prefix>

Output:
    golden/evaluation/<source_id>_eval.json
"""

import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "lib" / "training" / "extraction" / "golden"
SOURCES_DIR = GOLDEN_DIR / "sources"
UNIFIED_RUNS_DIR = GOLDEN_DIR / "unified_runs"
EVALUATION_DIR = GOLDEN_DIR / "evaluation"


# --- Data loading ---

def _load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def find_source(uuid_prefix: str) -> Path:
    candidates = list(SOURCES_DIR.glob(f"{uuid_prefix}*.json"))
    if len(candidates) == 0:
        raise FileNotFoundError(f"No source matching {uuid_prefix}*.json")
    if len(candidates) > 1:
        raise ValueError(f"Multiple matches for {uuid_prefix}: {[c.name for c in candidates]}")
    return candidates[0]


def find_unified_runs(source_id: str) -> list[Path]:
    source_dir = UNIFIED_RUNS_DIR / source_id
    if not source_dir.exists():
        raise FileNotFoundError(f"No unified runs at {source_dir}")
    return sorted(source_dir.glob("text_*.json"))


# --- Reconstruct final working memory ---

def reconstruct_working_memory(run_files: list[Path]) -> list[dict]:
    """Replay WM diffs to produce final proposition list with IDs."""
    propositions: list[dict] = []
    superseded_contents: set[str] = set()

    # Collect superseded first
    for run_file in run_files:
        data = _load_json(run_file)
        diff = data.get("workingMemoryDiff", {})
        for entry in diff.get("superseded", []):
            superseded_contents.add(entry["content"])

    # Collect added, skip superseded
    prop_id = 0
    for run_file in run_files:
        data = _load_json(run_file)
        text_index = data["textIndex"]
        diff = data.get("workingMemoryDiff", {})
        for prop in diff.get("added", []):
            if prop["content"] not in superseded_contents:
                propositions.append({
                    "id": f"p_{prop_id}",
                    "content": prop["content"],
                    "scope": prop.get("scope", "unknown"),
                    "type": prop.get("type", "unknown"),
                    "textIndex": text_index,
                })
                prop_id += 1

    return propositions


# --- Phase 1: Deterministic checks ---

# Conjunctions that join independent clauses (atomic check)
_COMPOUND_CONJUNCTIONS = re.compile(
    r",\s+(?:and|but|while|whereas|although)\s+",
    re.IGNORECASE,
)

# Attribution phrases (bare assertive check)
_ATTRIBUTION_PHRASES = re.compile(
    r"\b(?:the user|the assistant|the speaker|the author|"
    r"they (?:said|mentioned|noted|decided|wanted|preferred|believed)|"
    r"(?:user|speaker) (?:wants|prefers|believes|thinks|said|noted))\b",
    re.IGNORECASE,
)

# Dangling references (self-contained check)
_DANGLING_REFERENCES = re.compile(
    r"\b(?:the above|mentioned above|as discussed|the approach|"
    r"this (?:approach|method|system|idea|concept)(?!\s+(?:is|was|uses|has|can|will|should|requires|involves|aims|enables|ensures|maintains|maximizes|builds|includes)))\b",
    re.IGNORECASE,
)

# Unresolved pronouns at sentence start
_LEADING_PRONOUN = re.compile(
    r"^(?:It|This|That|These|Those|They)\s+(?:is|are|was|were|should|can|will|has|have)\b",
)


def check_atomic(proposition: dict) -> dict:
    """Check if proposition contains exactly one claim."""
    content = proposition["content"]

    # Multiple independent clauses joined by conjunction
    has_compound = bool(_COMPOUND_CONJUNCTIONS.search(content))

    # Multiple sentences
    sentence_count = len([s for s in re.split(r"[.!?]+", content) if s.strip()])
    has_multiple_sentences = sentence_count > 1

    passed = not has_compound and not has_multiple_sentences
    reason = None
    if has_compound:
        reason = "compound_conjunction"
    elif has_multiple_sentences:
        reason = "multiple_sentences"

    return {"passed": passed, "reason": reason}


def check_bare_assertive(proposition: dict) -> dict:
    """Check if proposition is a standalone claim without attribution."""
    content = proposition["content"]
    has_attribution = bool(_ATTRIBUTION_PHRASES.search(content))

    passed = not has_attribution
    reason = "attribution_phrase" if has_attribution else None
    return {"passed": passed, "reason": reason}


def check_self_contained(proposition: dict) -> dict:
    """Check if proposition is understandable without source context."""
    content = proposition["content"]

    has_dangling = bool(_DANGLING_REFERENCES.search(content))
    has_leading_pronoun = bool(_LEADING_PRONOUN.search(content))

    passed = not has_dangling and not has_leading_pronoun
    reason = None
    if has_dangling:
        reason = "dangling_reference"
    elif has_leading_pronoun:
        reason = "leading_pronoun"

    return {"passed": passed, "reason": reason}


def run_deterministic_checks(propositions: list[dict]) -> list[dict]:
    """Run all deterministic checks on every proposition."""
    scored = []
    for prop in propositions:
        scored.append({
            **prop,
            "deterministicScores": {
                "atomic": check_atomic(prop),
                "bareAssertive": check_bare_assertive(prop),
                "selfContained": check_self_contained(prop),
            },
        })
    return scored


# --- Phase 2: LLM evaluation ---

@dataclass
class AgentResult:
    success: bool
    stdout: str
    stderr: str
    elapsed_seconds: float
    error: str | None


def launch_agent(prompt: str, timeout_seconds: int = 600) -> AgentResult:
    start_time = time.time()
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    try:
        proc = subprocess.run(
            ["claude", "--print", "--dangerously-skip-permissions", "-p", "-"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            cwd=str(GOLDEN_DIR),
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
            success=False, stdout="", stderr="",
            elapsed_seconds=elapsed,
            error=f"timeout after {timeout_seconds}s",
        )


def build_llm_evaluation_prompt(
    source_texts: list[str],
    propositions: list[dict],
    output_path: Path,
) -> str:
    prop_list = json.dumps(
        [{"id": p["id"], "content": p["content"], "scope": p["scope"],
          "type": p["type"], "textIndex": p["textIndex"]}
         for p in propositions],
        indent=2, ensure_ascii=False,
    )
    texts_json = json.dumps(source_texts, indent=2, ensure_ascii=False)

    return f"""You are an evaluation agent for the encoder pipeline.

## Task
Score every proposition in the working memory on 3 dimensions that require judgment.
Write the results as JSON to: {output_path}

## Source Texts
{texts_json}

## Working Memory Propositions
{prop_list}

## Dimensions to Evaluate

### 1. Grounded
Is this proposition supported by the source texts?
- Search the source texts for evidence.
- If the claim is clearly stated or directly implied by the source, mark true.
- If the claim is inferred beyond what the source says, or fabricated, mark false.
- Note: propositions may paraphrase the source. Paraphrasing is grounded. Hallucination is not.

### 2. Non-redundant
Is this the only proposition expressing this idea in working memory?
- Compare against ALL other propositions in the list.
- If another proposition says the same thing in different words, mark false.
- Record the ID of the duplicate (the other proposition).
- If multiple duplicates exist, record the one with the lowest ID.

### 3. Durable
Will this knowledge matter beyond this immediate session?
- Design decisions, constraints, requirements, domain knowledge = durable (true).
- Ephemeral scheduling, in-progress status, "let me think about this" = not durable (false).
- Questions and offers to help ("Would you like to explore...") = not durable (false).
- Specific metrics and costs that define the system = durable (true).

## Output Schema
Write a JSON file with this structure:
{{
  "sourceId": "<source_id>",
  "scores": [
    {{
      "id": "p_0",
      "grounded": true,
      "nonRedundant": true,
      "durable": true,
      "duplicateOf": null,
      "groundedReason": null,
      "durableReason": null
    }}
  ]
}}

Rules:
- One entry per proposition, same order as input.
- "duplicateOf" is the ID string (e.g., "p_12") or null.
- "groundedReason" is a short explanation only when grounded=false.
- "durableReason" is a short explanation only when durable=false.
- Do not skip any proposition.

Write the output file now."""


# --- Phase 3: Merge and compute metrics ---

def merge_scores(
    deterministic_scored: list[dict],
    llm_scores: list[dict],
) -> list[dict]:
    """Merge deterministic and LLM scores into final per-proposition results."""
    llm_by_id = {s["id"]: s for s in llm_scores}

    merged = []
    for prop in deterministic_scored:
        prop_id = prop["id"]
        llm = llm_by_id.get(prop_id, {})
        det = prop["deterministicScores"]

        scores = {
            "grounded": llm.get("grounded", True),
            "atomic": det["atomic"]["passed"],
            "bareAssertive": det["bareAssertive"]["passed"],
            "nonRedundant": llm.get("nonRedundant", True),
            "durable": llm.get("durable", True),
            "selfContained": det["selfContained"]["passed"],
        }

        all_pass = all(scores.values())

        merged.append({
            "id": prop_id,
            "content": prop["content"],
            "scope": prop["scope"],
            "type": prop["type"],
            "textIndex": prop["textIndex"],
            "scores": scores,
            "duplicateOf": llm.get("duplicateOf"),
            "reasons": {
                "atomic": det["atomic"]["reason"],
                "bareAssertive": det["bareAssertive"]["reason"],
                "selfContained": det["selfContained"]["reason"],
                "grounded": llm.get("groundedReason"),
                "durable": llm.get("durableReason"),
            },
            "verdict": "pass" if all_pass else "fail",
        })

    return merged


def compute_aggregate_metrics(
    merged: list[dict],
    source_word_count: int,
) -> dict:
    """Compute precision, redundancy rate, durability rate, etc."""
    total = len(merged)
    if total == 0:
        return {}

    passing = sum(1 for p in merged if p["verdict"] == "pass")
    failing_grounded = sum(1 for p in merged if not p["scores"]["grounded"])
    failing_atomic = sum(1 for p in merged if not p["scores"]["atomic"])
    failing_bare = sum(1 for p in merged if not p["scores"]["bareAssertive"])
    failing_redundant = sum(1 for p in merged if not p["scores"]["nonRedundant"])
    failing_durable = sum(1 for p in merged if not p["scores"]["durable"])
    failing_self = sum(1 for p in merged if not p["scores"]["selfContained"])

    return {
        "wmSize": total,
        "precision": round(passing / total, 4),
        "groundednessRate": round((total - failing_grounded) / total, 4),
        "atomicRate": round((total - failing_atomic) / total, 4),
        "bareAssertiveRate": round((total - failing_bare) / total, 4),
        "nonRedundantRate": round((total - failing_redundant) / total, 4),
        "durabilityRate": round((total - failing_durable) / total, 4),
        "selfContainedRate": round((total - failing_self) / total, 4),
        "compressionRatio": round(source_word_count / total, 1),
        "failureCounts": {
            "grounded": failing_grounded,
            "atomic": failing_atomic,
            "bareAssertive": failing_bare,
            "nonRedundant": failing_redundant,
            "durable": failing_durable,
            "selfContained": failing_self,
        },
        "stageFailureCounts": {
            "decontext": failing_grounded + failing_atomic + failing_bare + failing_self,
            "dedup": failing_redundant,
            "filter": failing_durable,
        },
    }


def attribute_failures(merged: list[dict]) -> dict:
    """Map each failure dimension to responsible stage."""
    attribution = {
        "decontext": [],
        "dedup": [],
        "filter": [],
    }

    for prop in merged:
        if prop["verdict"] == "fail":
            scores = prop["scores"]
            if not scores["grounded"]:
                attribution["decontext"].append({"id": prop["id"], "failure": "not_grounded"})
            if not scores["atomic"]:
                attribution["decontext"].append({"id": prop["id"], "failure": "not_atomic"})
            if not scores["bareAssertive"]:
                attribution["decontext"].append({"id": prop["id"], "failure": "not_bare_assertive"})
            if not scores["selfContained"]:
                attribution["decontext"].append({"id": prop["id"], "failure": "not_self_contained"})
            if not scores["nonRedundant"]:
                attribution["dedup"].append({
                    "id": prop["id"],
                    "failure": "redundant",
                    "duplicateOf": prop.get("duplicateOf"),
                })
            if not scores["durable"]:
                attribution["filter"].append({"id": prop["id"], "failure": "not_durable"})

    return attribution


# --- Main ---

def evaluate_source(uuid_prefix: str) -> None:
    source_path = find_source(uuid_prefix)
    source = _load_json(source_path)
    source_id = source["sourceId"]
    source_texts = source["texts"]
    source_word_count = sum(len(t.split()) for t in source_texts)

    print(f"Source: {source_id}")
    print(f"Texts: {len(source_texts)}, Words: {source_word_count}")

    # Reconstruct WM
    run_files = find_unified_runs(source_id)
    propositions = reconstruct_working_memory(run_files)
    print(f"WM propositions: {len(propositions)}")

    # Phase 1: Deterministic
    print("\nPhase 1: Deterministic checks...")
    deterministic_scored = run_deterministic_checks(propositions)

    det_failures = {
        "atomic": sum(1 for p in deterministic_scored if not p["deterministicScores"]["atomic"]["passed"]),
        "bareAssertive": sum(1 for p in deterministic_scored if not p["deterministicScores"]["bareAssertive"]["passed"]),
        "selfContained": sum(1 for p in deterministic_scored if not p["deterministicScores"]["selfContained"]["passed"]),
    }
    print(f"  Failures: atomic={det_failures['atomic']}, "
          f"bareAssertive={det_failures['bareAssertive']}, "
          f"selfContained={det_failures['selfContained']}")

    # Phase 2: LLM evaluation
    print("\nPhase 2: LLM evaluation (grounded, non_redundant, durable)...")
    llm_output_path = EVALUATION_DIR / f"{source_id}_llm_scores.json"
    prompt = build_llm_evaluation_prompt(source_texts, propositions, llm_output_path)

    EVALUATION_DIR.mkdir(parents=True, exist_ok=True)
    print(f"  Prompt: {len(prompt)} chars")

    agent_result = launch_agent(prompt, timeout_seconds=600)
    print(f"  Agent completed in {agent_result.elapsed_seconds:.1f}s")

    if not agent_result.success:
        print(f"  ERROR: {agent_result.error}")
        print(f"  stderr: {agent_result.stderr[:500]}")
        sys.exit(1)

    if not llm_output_path.exists():
        print(f"  ERROR: Agent did not write output to {llm_output_path}")
        sys.exit(1)

    llm_data = _load_json(llm_output_path)
    llm_scores = llm_data.get("scores", [])
    print(f"  LLM scored {len(llm_scores)} propositions")

    if len(llm_scores) != len(propositions):
        print(f"  WARNING: LLM scored {len(llm_scores)} but WM has {len(propositions)}")

    # Phase 3: Merge and compute
    print("\nPhase 3: Merging scores and computing metrics...")
    merged = merge_scores(deterministic_scored, llm_scores)
    metrics = compute_aggregate_metrics(merged, source_word_count)
    attribution = attribute_failures(merged)

    eval_output = {
        "sourceId": source_id,
        "sourceWordCount": source_word_count,
        "textCount": len(source_texts),
        "evaluation": metrics,
        "propositions": merged,
        "failureAttribution": attribution,
        "recallGaps": [],
    }

    eval_path = EVALUATION_DIR / f"{source_id}_eval.json"
    _write_json(eval_path, eval_output)

    # Clean up intermediate LLM scores file
    if llm_output_path.exists():
        llm_output_path.unlink()

    print(f"\nEvaluation written to: {eval_path.name}")

    # Print summary
    print(f"\n{'='*60}")
    print(f"EVALUATION SUMMARY")
    print(f"{'='*60}")
    print(f"WM size:            {metrics['wmSize']}")
    print(f"Precision:          {metrics['precision']:.1%}")
    print(f"Groundedness:       {metrics['groundednessRate']:.1%}")
    print(f"Atomic rate:        {metrics['atomicRate']:.1%}")
    print(f"Bare assertive:     {metrics['bareAssertiveRate']:.1%}")
    print(f"Non-redundant:      {metrics['nonRedundantRate']:.1%}")
    print(f"Durability:         {metrics['durabilityRate']:.1%}")
    print(f"Self-contained:     {metrics['selfContainedRate']:.1%}")
    print(f"Compression:        {metrics['compressionRatio']} words/prop")
    print(f"\nFailure attribution:")
    for stage, failures in attribution.items():
        if failures:
            print(f"  {stage}: {len(failures)} failures")
            for failure in failures[:5]:
                print(f"    {failure['id']}: {failure['failure']}")
            if len(failures) > 5:
                print(f"    ... and {len(failures) - 5} more")

    # Healthy range checks
    print(f"\n{'='*60}")
    print(f"HEALTH CHECK")
    print(f"{'='*60}")
    checks = [
        ("Precision", metrics["precision"], 0.85, 0.70, True),
        ("Redundancy", 1 - metrics["nonRedundantRate"], 0.10, 0.15, False),
        ("Durability", metrics["durabilityRate"], 0.70, 0.50, True),
        ("Bare assertive", metrics["bareAssertiveRate"], 0.95, 0.80, True),
        ("Compression", metrics["compressionRatio"], 200, 500, False),
    ]
    for name, value, healthy_threshold, red_threshold, higher_is_better in checks:
        if higher_is_better:
            status = "HEALTHY" if value >= healthy_threshold else ("RED FLAG" if value < red_threshold else "WARNING")
        else:
            status = "HEALTHY" if value <= healthy_threshold else ("RED FLAG" if value > red_threshold else "WARNING")
        indicator = "OK" if status == "HEALTHY" else ("!!" if status == "RED FLAG" else "??")
        if isinstance(value, float) and value <= 1.0:
            print(f"  [{indicator}] {name}: {value:.1%} ({status})")
        else:
            print(f"  [{indicator}] {name}: {value} ({status})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python evaluate_pipeline.py <source_uuid_prefix>")
        sys.exit(1)
    evaluate_source(sys.argv[1])
