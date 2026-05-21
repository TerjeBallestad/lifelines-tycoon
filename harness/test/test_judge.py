#!/usr/bin/env python3
"""Tests for harness/lib/judge.py."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import ClaudeSession  # noqa: E402
from judge import (  # noqa: E402
    AxisJudgment,
    parse_judgment,
    JudgeError,
    score_axis,
    AXIS_SLUGS,
)


GOOD_REPLY = json.dumps({
    "axis": "decision-density",
    "sub_scores": [2, 1, 2, 1],
    "axis_score": 1.5,
    "citations": [
        {"sub_criterion": 2, "citation": "every strategy converged to eager_diagnostician path", "anchor": "negative/06-decision-dominant-strategy"},
        {"sub_criterion": 4, "citation": "zero action_failed events across 12 traces", "anchor": "negative/10-decision-no-refusal"}
    ],
    "harsh_check": "no refusal events across the entire tournament — burn is unsurfaced"
})

BAD_NO_SCORES = json.dumps({
    "axis": "decision-density",
    "axis_score": 2.0,
    "citations": [],
    "harsh_check": "fine"
})

BAD_OUT_OF_RANGE = json.dumps({
    "axis": "decision-density",
    "sub_scores": [4, 0, 0, 0],
    "axis_score": 1.0,
    "citations": [],
    "harsh_check": "fine"
})

UNKNOWN_AXIS = GOOD_REPLY.replace("decision-density", "vibes-only")


class TestParseJudgment(unittest.TestCase):
    def test_parses_good(self) -> None:
        j = parse_judgment(GOOD_REPLY, expected_axis="decision-density")
        self.assertEqual(j.sub_scores, [2, 1, 2, 1])
        self.assertAlmostEqual(j.axis_score, 1.5, places=2)
        self.assertEqual(len(j.citations), 2)

    def test_rejects_missing_scores(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(BAD_NO_SCORES, expected_axis="decision-density")

    def test_rejects_out_of_range(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(BAD_OUT_OF_RANGE, expected_axis="decision-density")

    def test_rejects_unknown_axis(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(UNKNOWN_AXIS, expected_axis="decision-density")

    def test_rejects_axis_mismatch(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(GOOD_REPLY, expected_axis="thematic-coherence")


class TestScoreAxisShim(unittest.TestCase):
    def test_score_axis_via_shim(self) -> None:
        canned = {"shim-session": [GOOD_REPLY]}
        session = ClaudeSession.shim(canned, session_id="shim-session")
        j = score_axis(
            session=session,
            axis_slug="decision-density",
            axis_definition_md="# axis stub",
            positive_anchors=[("anchor_a", "body_a")],
            negative_anchors=[("anchor_b", "body_b")],
            trace_extract="{}",
            freeplay_extract=None,
            model="claude-opus-4-7",
        )
        self.assertEqual(j.axis, "decision-density")
        self.assertEqual(j.sub_scores, [2, 1, 2, 1])


class TestAxisSlugs(unittest.TestCase):
    def test_all_seven_present(self) -> None:
        self.assertEqual(len(AXIS_SLUGS), 7)
        self.assertIn("thematic-coherence", AXIS_SLUGS)
        self.assertIn("loop-closure", AXIS_SLUGS)


if __name__ == "__main__":
    unittest.main()
