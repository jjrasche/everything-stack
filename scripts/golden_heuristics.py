"""Per-stage heuristic computation for golden data pipeline.

Reads stage output JSON, returns per-metric results with pass/fail status.
Each metric is per-instance (per text, per span, per proposition) unless
explicitly marked as aggregate.

Red flag = hard stop. Healthy range = informational.
"""

import json
import re
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


class Severity(Enum):
    HEALTHY = "healthy"
    WARNING = "warning"
    RED_FLAG = "red_flag"


@dataclass
class MetricResult:
    name: str
    value: float
    severity: Severity
    healthy_range: str
    red_flag_range: str
    context: str

    def is_red_flag(self) -> bool:
        return self.severity == Severity.RED_FLAG


@dataclass
class StageReport:
    stage: str
    source_id: str
    metrics: list[MetricResult] = field(default_factory=list)
    bug_checks: list[MetricResult] = field(default_factory=list)

    def has_red_flags(self) -> bool:
        return any(m.is_red_flag() for m in self.metrics)

    def has_bug_failures(self) -> bool:
        return any(m.is_red_flag() for m in self.bug_checks)

    def should_stop(self) -> bool:
        return self.has_red_flags() or self.has_bug_failures()

    def summarize(self) -> dict[str, Any]:
        red_flags = [m for m in self.metrics if m.is_red_flag()]
        bugs = [m for m in self.bug_checks if m.is_red_flag()]
        warnings = [m for m in self.metrics if m.severity == Severity.WARNING]
        return {
            "stage": self.stage,
            "sourceId": self.source_id,
            "pass": not self.should_stop(),
            "redFlagCount": len(red_flags),
            "bugFailureCount": len(bugs),
            "warningCount": len(warnings),
            "redFlags": [
                {"name": m.name, "value": m.value, "context": m.context}
                for m in red_flags
            ],
            "bugFailures": [
                {"name": m.name, "value": m.value, "context": m.context}
                for m in bugs
            ],
            "warnings": [
                {"name": m.name, "value": m.value, "context": m.context}
                for m in warnings
            ],
        }


# --- Shared helpers ---

def _count_words(text: str) -> int:
    return len(text.split())


def _count_punctuation(text: str) -> int:
    return sum(1 for ch in text if ch in ".,:;!?")


def _classify(
    value: float,
    healthy_low: float,
    healthy_high: float,
    red_low: float | None,
    red_high: float | None,
) -> Severity:
    if red_low is not None and value < red_low:
        return Severity.RED_FLAG
    if red_high is not None and value > red_high:
        return Severity.RED_FLAG
    if healthy_low <= value <= healthy_high:
        return Severity.HEALTHY
    return Severity.WARNING


def _text_label(index: int) -> str:
    return f"text {index}"


# --- Stage 1: Normalize ---

def check_normalize(data: dict) -> StageReport:
    report = StageReport(stage="normalize", source_id=data.get("sourceId", ""))

    for i, result in enumerate(data.get("results", [])):
        output_text = result["output"]["text"]
        label = _text_label(i)
        word_count = _count_words(output_text)

        if word_count == 0:
            report.metrics.append(MetricResult(
                name="empty_text", value=0, severity=Severity.RED_FLAG,
                healthy_range="word_count > 0", red_flag_range="word_count == 0",
                context=label,
            ))
            continue

        punct_count = _count_punctuation(output_text)
        punct_ratio = punct_count / word_count
        report.metrics.append(MetricResult(
            name="punctuation_ratio", value=round(punct_ratio, 4),
            severity=_classify(punct_ratio, 0.05, 0.125, 0.04, 0.33),
            healthy_range="0.05-0.125", red_flag_range="< 0.04 or > 0.33",
            context=label,
        ))

        sentences = [s.strip() for s in re.split(r"[.!?]+", output_text) if s.strip()]
        max_sentence_words = max((_count_words(s) for s in sentences), default=0)
        report.metrics.append(MetricResult(
            name="max_sentence_words", value=max_sentence_words,
            severity=_classify(max_sentence_words, 10, 35, None, 50),
            healthy_range="10-35", red_flag_range="> 50",
            context=label,
        ))

    return report


# --- Stage 2: Segment ---

def check_segment(data: dict) -> StageReport:
    report = StageReport(stage="segment", source_id=data.get("sourceId", ""))

    for i, result in enumerate(data.get("results", [])):
        sentences = result["output"]["sentences"]
        label = _text_label(i)

        if not sentences:
            report.metrics.append(MetricResult(
                name="empty_sentences", value=0, severity=Severity.RED_FLAG,
                healthy_range="sentence_count > 0", red_flag_range="sentence_count == 0",
                context=label,
            ))
            continue

        total_words = sum(_count_words(s["text"]) for s in sentences)
        avg = total_words / len(sentences)
        report.metrics.append(MetricResult(
            name="avg_sentence_words", value=round(avg, 1),
            severity=_classify(avg, 8, 25, 4, 40),
            healthy_range="8-25", red_flag_range="< 4 or > 40",
            context=label,
        ))

    return report


# --- Stage 3: Cohere ---

def _resolve_span_text(span: dict, sentences_by_id: dict[str, str]) -> str:
    return " ".join(
        sentences_by_id.get(sid, "")
        for sid in span["sentenceIds"]
    )


def check_cohere(data: dict, segment_data: dict) -> StageReport:
    report = StageReport(stage="cohere", source_id=data.get("sourceId", ""))
    sentence_lookup = _build_sentence_lookup(segment_data)

    for i, result in enumerate(data.get("results", [])):
        spans = result["output"]["spans"]
        label = _text_label(i)

        if not spans:
            report.metrics.append(MetricResult(
                name="empty_spans", value=0, severity=Severity.RED_FLAG,
                healthy_range="span_count > 0", red_flag_range="span_count == 0",
                context=label,
            ))
            continue

        sentences_by_id = sentence_lookup.get(i, {})
        word_counts = []
        sentence_counts = []

        for span in spans:
            sentence_counts.append(len(span["sentenceIds"]))
            span_text = _resolve_span_text(span, sentences_by_id)
            word_counts.append(_count_words(span_text))

        avg_words = sum(word_counts) / len(word_counts)
        avg_sentences = sum(sentence_counts) / len(sentence_counts)

        report.metrics.append(MetricResult(
            name="avg_span_words", value=round(avg_words, 1),
            severity=_classify(avg_words, 15, 150, 5, 300),
            healthy_range="15-150", red_flag_range="< 5 or > 300",
            context=label,
        ))
        report.metrics.append(MetricResult(
            name="avg_span_sentences", value=round(avg_sentences, 1),
            severity=_classify(avg_sentences, 2, 8, 1, 15),
            healthy_range="2-8", red_flag_range="all 1-sentence spans or > 15",
            context=label,
        ))

    return report


# --- Stage 4: Recohere ---

def check_recohere(data: dict) -> StageReport:
    report = StageReport(stage="recohere", source_id=data.get("sourceId", ""))

    total_input_spans = 0
    total_merges = 0

    for result in data.get("results", []):
        total_input_spans += len(result["input"]["spans"])
        total_merges += len(result["output"].get("merges", []))

    if total_input_spans > 0:
        merge_rate = total_merges / total_input_spans
        report.metrics.append(MetricResult(
            name="merge_rate", value=round(merge_rate, 4),
            severity=_classify(merge_rate, 0.0, 0.20, None, 0.40),
            healthy_range="0-20%", red_flag_range="> 40%",
            context="aggregate",
        ))

    return report


# --- Stage 5: Filter ---

def check_filter(data: dict) -> StageReport:
    report = StageReport(stage="filter", source_id=data.get("sourceId", ""))

    total_spans = data.get("totalSpans", 0)
    total_skip = data.get("totalSkip", 0)

    if total_spans > 0:
        skip_rate = total_skip / total_spans
        report.metrics.append(MetricResult(
            name="skip_rate", value=round(skip_rate, 4),
            severity=_classify(skip_rate, 0.05, 0.50, None, 0.80),
            healthy_range="5-50%", red_flag_range="> 80%",
            context=f"aggregate ({total_skip}/{total_spans} spans skipped)",
        ))

    return report


# --- Stage 6: Decontextualize ---

_EPISTEMIC_PATTERN = re.compile(
    r"\b(the\s+user|the\s+speaker|the\s+assistant|the\s+person)\b",
    re.IGNORECASE,
)

_COMPOUND_INDICATORS = re.compile(
    r"(;\s|,\s.*,\s.*,\s|\band\b.*\band\b)",
)


def check_decontext(data: dict, segment_data: dict) -> StageReport:
    report = StageReport(stage="decontext", source_id=data.get("sourceId", ""))
    sentence_lookup = _build_sentence_lookup(segment_data)

    for i, result in enumerate(data.get("results", [])):
        label = _text_label(i)
        propositions = result["output"].get("propositions", [])
        extract_span_count = result["output"].get("extractSpanCount", 0)

        if extract_span_count == 0:
            continue

        props_per_span = len(propositions) / extract_span_count
        report.metrics.append(MetricResult(
            name="props_per_span", value=round(props_per_span, 2),
            severity=_classify(props_per_span, 1, 8, 0, 15),
            healthy_range="1-8", red_flag_range="0 or > 15",
            context=label,
        ))

        if not propositions:
            continue

        prop_word_counts = [_count_words(p["content"]) for p in propositions]
        avg_prop_words = sum(prop_word_counts) / len(prop_word_counts)
        report.metrics.append(MetricResult(
            name="avg_prop_words", value=round(avg_prop_words, 1),
            severity=_classify(avg_prop_words, 10, 25, 5, 40),
            healthy_range="10-25", red_flag_range="< 5 or > 40",
            context=label,
        ))

        compound_count = sum(
            1 for p in propositions
            if p["content"].count(",") >= 3
            or len(re.findall(r"\band\b", p["content"], re.IGNORECASE)) >= 2
            or ";" in p["content"]
        )
        compound_rate = compound_count / len(propositions)
        report.metrics.append(MetricResult(
            name="compound_rate", value=round(compound_rate, 4),
            severity=_classify(compound_rate, 0.0, 0.10, None, 0.20),
            healthy_range="< 10%", red_flag_range="> 20%",
            context=label,
        ))

        # Compression ratio using segment sentence text
        sentences_by_id = sentence_lookup.get(i, {})
        input_spans = result.get("input", {}).get("spans", [])
        total_span_words = sum(
            _count_words(_resolve_span_text(span, sentences_by_id))
            for span in input_spans
        )
        if total_span_words > 0:
            compression = total_span_words / len(propositions)
            report.metrics.append(MetricResult(
                name="compression_ratio", value=round(compression, 2),
                severity=_classify(compression, 8.0, 30.0, 4.0, 50.0),
                healthy_range="8-30x", red_flag_range="< 4x or > 50x",
                context=label,
            ))

        # Bug check: epistemic framing must be 0%
        epistemic_count = sum(
            1 for p in propositions
            if _EPISTEMIC_PATTERN.search(p["content"])
        )
        epistemic_rate = epistemic_count / len(propositions)
        report.bug_checks.append(MetricResult(
            name="epistemic_rate", value=round(epistemic_rate, 4),
            severity=Severity.RED_FLAG if epistemic_count > 0 else Severity.HEALTHY,
            healthy_range="0%", red_flag_range="> 0%",
            context=f"{label} ({epistemic_count} violations)",
        ))

    return report


# --- Stage 7: Dedup ---

def check_dedup(data: dict) -> StageReport:
    report = StageReport(stage="dedup", source_id=data.get("sourceId", ""))

    total_propositions = data.get("totalPropositions", 0)
    summary = data.get("summary", {})
    entailment_count = summary.get("entailment", 0)

    if total_propositions > 0:
        merge_rate = entailment_count / total_propositions
        report.metrics.append(MetricResult(
            name="merge_rate", value=round(merge_rate, 4),
            severity=_classify(merge_rate, 0.05, 0.30, 0.0, 0.60),
            healthy_range="5-30%",
            red_flag_range="0% (after text 3) or > 60%",
            context=f"aggregate ({entailment_count} entailments / {total_propositions} props)",
        ))

        net_after_dedup = total_propositions - entailment_count
        wm_growth_rate = net_after_dedup / total_propositions
        report.metrics.append(MetricResult(
            name="wm_growth_rate", value=round(wm_growth_rate, 4),
            severity=_classify(wm_growth_rate, 0.40, 0.90, None, 1.0),
            healthy_range="40-90%",
            red_flag_range="100% (no dedup happening)",
            context=f"aggregate ({net_after_dedup} net / {total_propositions} total)",
        ))

    return report


# --- Shared lookup builder ---

def _build_sentence_lookup(segment_data: dict) -> dict[int, dict[str, str]]:
    """Build {arrayIndex: {sentenceId: text}} from segment output."""
    lookup: dict[int, dict[str, str]] = {}
    for i, result in enumerate(segment_data.get("results", [])):
        lookup[i] = {
            s["id"]: s["text"]
            for s in result["output"]["sentences"]
        }
    return lookup


# --- Orchestrator entry point ---

def run_stage_check(
    stage: str,
    stage_data: dict,
    segment_data: dict | None = None,
) -> StageReport:
    match stage:
        case "normalize":
            return check_normalize(stage_data)
        case "segment":
            return check_segment(stage_data)
        case "cohere":
            if segment_data is None:
                raise ValueError("cohere check requires segment_data")
            return check_cohere(stage_data, segment_data)
        case "recohere":
            return check_recohere(stage_data)
        case "filter":
            return check_filter(stage_data)
        case "decontext":
            if segment_data is None:
                raise ValueError("decontext check requires segment_data")
            return check_decontext(stage_data, segment_data)
        case "dedup":
            return check_dedup(stage_data)
        case _:
            raise ValueError(f"Unknown stage: {stage}")


# --- CLI ---

def _load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _print_report(report: StageReport) -> None:
    summary = report.summarize()
    status = "PASS" if summary["pass"] else "FAIL"
    print(f"\n{'='*60}")
    print(f"Stage: {report.stage}  |  Status: {status}")
    print(f"Source: {report.source_id}")
    print(f"{'='*60}")

    if summary["bugFailures"]:
        print("\n  BUG FAILURES (hard stop):")
        for bug in summary["bugFailures"]:
            print(f"    [X] {bug['name']}: {bug['value']} -- {bug['context']}")

    if summary["redFlags"]:
        print("\n  RED FLAGS (hard stop):")
        for flag in summary["redFlags"]:
            print(f"    [X] {flag['name']}: {flag['value']} -- {flag['context']}")

    if summary["warnings"]:
        print("\n  WARNINGS:")
        for warn in summary["warnings"]:
            print(f"    [!] {warn['name']}: {warn['value']} -- {warn['context']}")

    healthy = len(report.metrics) - summary["redFlagCount"] - summary["warningCount"]
    print(f"\n  Healthy: {healthy}  |  Warnings: {summary['warningCount']}  |  Red flags: {summary['redFlagCount']}  |  Bug failures: {summary['bugFailureCount']}")


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: python golden_heuristics.py <stage> <stage_output.json> [segment_output.json]")
        print("Stages: normalize, segment, cohere, recohere, filter, decontext, dedup")
        sys.exit(1)

    stage = sys.argv[1]
    stage_data = _load_json(Path(sys.argv[2]))

    segment_data = None
    if len(sys.argv) > 3:
        segment_data = _load_json(Path(sys.argv[3]))

    report = run_stage_check(stage, stage_data, segment_data)
    _print_report(report)

    if report.should_stop():
        sys.exit(1)


if __name__ == "__main__":
    main()
