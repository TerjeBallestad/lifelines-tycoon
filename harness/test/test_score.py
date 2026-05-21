#!/usr/bin/env python3
"""Tests for harness/lib/score.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from score import (  # noqa: E402
    AXIS_WEIGHTS,
    AXIS_FLOORS,
    compute_verdict,
    Verdict,
)


JUDGMENTS_ALL_3 = [{"axis": a, "sub_scores": [3, 3, 3, 3], "axis_score": 3.0, "citations": [], "harsh_check": ""} for a in AXIS_WEIGHTS.keys()]
JUDGMENTS_FLOORED = [
    {"axis": "thematic-coherence",    "sub_scores": [3, 3, 3, 3], "axis_score": 3.0, "citations": [], "harsh_check": ""},
    {"axis": "decision-density",      "sub_scores": [1, 1, 1, 1], "axis_score": 1.0, "citations": [], "harsh_check": ""},  # below floor (2)
    {"axis": "earned-discovery",      "sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "forgiveness-with-stakes","sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "texture-voice",         "sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "sim-legibility",        "sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "loop-closure",          "sub_scores": [3, 3, 3, 3], "axis_score": 3.0, "citations": [], "harsh_check": ""},
]


class TestComputeVerdict(unittest.TestCase):
    def test_perfect_passes(self) -> None:
        v = compute_verdict(
            judgments=JUDGMENTS_ALL_3,
            test_results={"all_pass": True, "items": []},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertEqual(v.verdict, "PASS")
        self.assertEqual(v.total, 84.0)

    def test_floor_violation_rejects(self) -> None:
        v = compute_verdict(
            judgments=JUDGMENTS_FLOORED,
            test_results={"all_pass": True, "items": []},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertEqual(v.verdict, "REJECT")
        self.assertIn("decision-density", v.floor_violations)

    def test_test_fail_blocks_pass(self) -> None:
        v = compute_verdict(
            judgments=JUDGMENTS_ALL_3,
            test_results={"all_pass": False, "items": [{"index": 0, "pass": False}]},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertIn(v.verdict, ("PIVOT", "REJECT"))

    def test_total_below_50_rejects(self) -> None:
        weak = [{"axis": a, "sub_scores": [1, 1, 1, 1], "axis_score": 1.0, "citations": [], "harsh_check": ""} for a in AXIS_WEIGHTS.keys()]
        v = compute_verdict(
            judgments=weak,
            test_results={"all_pass": True, "items": []},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertEqual(v.verdict, "REJECT")

    def test_writes_to_disk(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "verdict.json"
            v = compute_verdict(
                judgments=JUDGMENTS_ALL_3,
                test_results={"all_pass": True, "items": []},
                trace_findings={"all_pass": True, "items": []},
            )
            v.write(out)
            data = json.loads(out.read_text())
            self.assertEqual(data["verdict"], "PASS")
            self.assertEqual(data["total"], 84.0)


if __name__ == "__main__":
    unittest.main()
