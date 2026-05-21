#!/usr/bin/env python3
"""Tests for harness/lib/render_critique.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from render_critique import render_critique  # noqa: E402


VERDICT = {
    "verdict": "REJECT",
    "total": 42.5,
    "max_total": 84.0,
    "per_axis": {
        "thematic-coherence":      {"axis_score": 2.5, "weight": 5, "weighted": 12.5, "floor": 2, "below_floor": False},
        "decision-density":        {"axis_score": 1.0, "weight": 5, "weighted": 5.0,  "floor": 2, "below_floor": True},
        "earned-discovery":        {"axis_score": 2.0, "weight": 4, "weighted": 8.0,  "floor": 2, "below_floor": False},
        "forgiveness-with-stakes": {"axis_score": 2.0, "weight": 4, "weighted": 8.0,  "floor": 1, "below_floor": False},
        "texture-voice":           {"axis_score": 2.0, "weight": 3, "weighted": 6.0,  "floor": 1, "below_floor": False},
        "sim-legibility":          {"axis_score": 1.0, "weight": 3, "weighted": 3.0,  "floor": 1, "below_floor": False},
        "loop-closure":            {"axis_score": 0.0, "weight": 4, "weighted": 0.0,  "floor": 2, "below_floor": True},
    },
    "floor_violations": ["decision-density", "loop-closure"],
    "test_pass": True,
    "trace_pass": False,
    "notes": ["[trace] verifier reported at least one failing rule"],
}

JUDGMENTS = {"items": [
    {"axis": "decision-density", "sub_scores": [1, 1, 1, 1], "axis_score": 1.0,
     "citations": [{"sub_criterion": 2, "citation": "every strategy converged on diag path", "anchor": "negative/06-decision-dominant-strategy"}],
     "harsh_check": "no cross-strategy variance"},
]}
TESTS = {"all_pass": True, "items": []}
TRACES = {"all_pass": False, "items": [
    {"index": 0, "kind": "trace", "body": "in any strategy: events where ev=action_failed count >= 1",
     "observed": 0, "threshold": 1, "comparator": ">=", "per_trace": {"eager_diagnostician_seed1": 0}, "failing_traces": [], "pass": False},
]}


class TestRenderCritique(unittest.TestCase):
    def test_renders_verdict_line(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="run-x sprint 1")
        self.assertIn("**Verdict: REJECT**", md)
        self.assertIn("42.5 / 84", md)

    def test_lists_floor_violations(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="x")
        self.assertIn("decision-density", md)
        self.assertIn("loop-closure", md)

    def test_includes_harsh_check_quotes(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="x")
        self.assertIn("no cross-strategy variance", md)

    def test_includes_failing_trace_rule(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="x")
        self.assertIn("action_failed", md)


if __name__ == "__main__":
    unittest.main()
