#!/usr/bin/env python3
"""Tests for harness/lib/calibrate_anchors.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import ClaudeSession  # noqa: E402
from calibrate_anchors import (  # noqa: E402
    CalibrationResult,
    run_calibration,
    canonical_score_from_anchor,
)


POS_ANCHOR = """---
axis: thematic-coherence
polarity: positive
sub_criteria_targeted: [1, 2]
source: disco elysium
score_if_anchor: 3
canonical_score: 3
---

# Disco Elysium bureaucracy

Body here.
"""

NEG_ANCHOR = """---
axis: thematic-coherence
polarity: negative
sub_criteria_targeted: [1, 4]
source: generic rpg
score_if_anchor: 0
canonical_score: 0
---

# XP bar leveling

Body here.
"""


class TestCanonicalScore(unittest.TestCase):
    def test_reads_canonical_score(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.md"
            p.write_text(POS_ANCHOR)
            self.assertEqual(canonical_score_from_anchor(p), 3)


class TestRunCalibrationShim(unittest.TestCase):
    def test_pass_when_within_one_point(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            pos = tdp / "pos.md"; pos.write_text(POS_ANCHOR)
            neg = tdp / "neg.md"; neg.write_text(NEG_ANCHOR)
            canned = {"shim-session": [
                json.dumps({"score": 3, "rationale": "matches positive anchor"}),
                json.dumps({"score": 1, "rationale": "matches negative anchor"}),
            ]}
            session = ClaudeSession.shim(canned, session_id="shim-session")
            result = run_calibration(
                anchor_paths=[pos, neg],
                session=session,
                model="claude-opus-4-7",
            )
            self.assertTrue(result.passed)
            self.assertEqual(len(result.per_anchor), 2)
            self.assertTrue(all(a["drift"] <= 1 for a in result.per_anchor))

    def test_fail_when_drift_above_one(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            pos = tdp / "pos.md"; pos.write_text(POS_ANCHOR)
            canned = {"shim-session": [
                json.dumps({"score": 0, "rationale": "wildly miscalibrated"}),
            ]}
            session = ClaudeSession.shim(canned, session_id="shim-session")
            result = run_calibration(
                anchor_paths=[pos],
                session=session,
                model="claude-opus-4-7",
            )
            self.assertFalse(result.passed)
            self.assertEqual(result.per_anchor[0]["drift"], 3)


if __name__ == "__main__":
    unittest.main()
