#!/usr/bin/env python3
"""Compute composite rubric score + verdict from verifier outputs.

Weights and floors are pinned to docs/rubric/rubric.md.
"""
from __future__ import annotations
import json
from dataclasses import dataclass, field
from pathlib import Path


AXIS_WEIGHTS: dict[str, int] = {
    "thematic-coherence":      5,
    "decision-density":        5,
    "earned-discovery":        4,
    "forgiveness-with-stakes": 4,
    "texture-voice":           3,
    "sim-legibility":          3,
    "loop-closure":            4,
}
AXIS_FLOORS: dict[str, int] = {
    "thematic-coherence":      2,
    "decision-density":        2,
    "earned-discovery":        2,
    "forgiveness-with-stakes": 1,
    "texture-voice":           1,
    "sim-legibility":          1,
    "loop-closure":            2,
}
PASS_TOTAL = 65.0
PIVOT_TOTAL = 50.0


@dataclass
class Verdict:
    verdict: str               # "PASS" | "PIVOT" | "REJECT"
    total: float
    max_total: float
    per_axis: dict[str, dict]
    floor_violations: list[str]
    test_pass: bool
    trace_pass: bool
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "verdict": self.verdict,
            "total": self.total,
            "max_total": self.max_total,
            "per_axis": self.per_axis,
            "floor_violations": self.floor_violations,
            "test_pass": self.test_pass,
            "trace_pass": self.trace_pass,
            "notes": self.notes,
        }

    def write(self, path: Path) -> None:
        path.write_text(json.dumps(self.to_dict(), indent=2))


def compute_verdict(
    judgments: list[dict],
    test_results: dict,
    trace_findings: dict,
) -> Verdict:
    per_axis: dict[str, dict] = {}
    total = 0.0
    floor_violations: list[str] = []

    judgments_by_axis = {j["axis"]: j for j in judgments}
    for axis_slug, weight in AXIS_WEIGHTS.items():
        if axis_slug not in judgments_by_axis:
            raise ValueError(f"missing judgment for axis {axis_slug}")
        j = judgments_by_axis[axis_slug]
        axis_score = float(j["axis_score"])
        weighted = axis_score * weight
        total += weighted
        per_axis[axis_slug] = {
            "axis_score": axis_score,
            "weight": weight,
            "weighted": weighted,
            "floor": AXIS_FLOORS[axis_slug],
            "below_floor": axis_score < AXIS_FLOORS[axis_slug],
        }
        if axis_score < AXIS_FLOORS[axis_slug]:
            floor_violations.append(axis_slug)

    max_total = sum(w * 3 for w in AXIS_WEIGHTS.values())  # 84
    test_pass = bool(test_results.get("all_pass", False))
    trace_pass = bool(trace_findings.get("all_pass", False))
    notes: list[str] = []

    if floor_violations:
        verdict = "REJECT"
        notes.append(f"floor violations on: {', '.join(floor_violations)}")
    elif not test_pass:
        notes.append("[test] verifier reported at least one failing item")
        verdict = "REJECT" if total < PIVOT_TOTAL else "PIVOT"
    elif not trace_pass:
        notes.append("[trace] verifier reported at least one failing rule")
        verdict = "REJECT" if total < PIVOT_TOTAL else "PIVOT"
    elif total >= PASS_TOTAL:
        verdict = "PASS"
    elif total >= PIVOT_TOTAL:
        verdict = "PIVOT"
    else:
        verdict = "REJECT"

    return Verdict(
        verdict=verdict,
        total=round(total, 2),
        max_total=float(max_total),
        per_axis=per_axis,
        floor_violations=floor_violations,
        test_pass=test_pass,
        trace_pass=trace_pass,
        notes=notes,
    )


def load_inputs(sprint_dir: Path) -> tuple[list[dict], dict, dict]:
    judgments = json.loads((sprint_dir / "judgments.json").read_text())
    test_results = json.loads((sprint_dir / "test_results.json").read_text())
    trace_findings = json.loads((sprint_dir / "trace_findings.json").read_text())
    return judgments["items"], test_results, trace_findings


def main(sprint_dir: Path) -> int:
    judgments, test_results, trace_findings = load_inputs(sprint_dir)
    v = compute_verdict(judgments, test_results, trace_findings)
    v.write(sprint_dir / "verdict.json")
    print(f"[score] verdict={v.verdict} total={v.total}/{v.max_total} → {sprint_dir/'verdict.json'}")
    return 0
