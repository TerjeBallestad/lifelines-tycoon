#!/usr/bin/env python3
"""Tests for harness/lib/pre_grade_calibration.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from pre_grade_calibration import (  # noqa: E402
    DriftReport,
    compare_scorecards,
    parse_scorecard_md,
    CalibrationError,
)


CANONICAL = """# Baseline Scorecard

| Axis | Score |
|------|-------|
| 1 | 2 |
| 2 | 2 |
| 3 | 1 |
| 4 | 1 |
| 5 | 1 |
| 6 | 1 |
| 7 | 2 |
"""

DRIFTED_OK = CANONICAL.replace("| 4 | 1 |", "| 4 | 2 |")        # +1 on axis 4 — within tolerance
DRIFTED_BAD = CANONICAL.replace("| 2 | 2 |", "| 2 | 0 |")       # −2 on axis 2 — out of tolerance
SYCOPHANTIC = """# Baseline Scorecard\n\n| Axis | Score |\n|------|-------|\n| 1 | 3 |\n| 2 | 3 |\n| 3 | 3 |\n| 4 | 3 |\n| 5 | 3 |\n| 6 | 3 |\n| 7 | 3 |\n"""


class TestParseScorecard(unittest.TestCase):
    def test_parses_all_seven_axes(self) -> None:
        s = parse_scorecard_md(CANONICAL)
        self.assertEqual(set(s.keys()), {1, 2, 3, 4, 5, 6, 7})
        self.assertEqual(s[1], 2)
        self.assertEqual(s[7], 2)

    def test_missing_axis_raises(self) -> None:
        bad = CANONICAL.replace("| 4 | 1 |\n", "")
        with self.assertRaises(CalibrationError):
            parse_scorecard_md(bad)


class TestCompare(unittest.TestCase):
    def test_within_tolerance_no_drift(self) -> None:
        r = compare_scorecards(CANONICAL, DRIFTED_OK, tolerance=1)
        self.assertIsInstance(r, DriftReport)
        self.assertFalse(r.exceeds_tolerance)
        self.assertEqual(len(r.deltas), 7)

    def test_out_of_tolerance(self) -> None:
        r = compare_scorecards(CANONICAL, DRIFTED_BAD, tolerance=1)
        self.assertTrue(r.exceeds_tolerance)
        self.assertIn(2, [d.axis for d in r.violating_deltas()])

    def test_all_threes_is_sycophancy(self) -> None:
        r = compare_scorecards(CANONICAL, SYCOPHANTIC, tolerance=1)
        # Several axes shifted by more than tolerance — guard catches this.
        self.assertTrue(r.exceeds_tolerance)
        self.assertGreaterEqual(len(r.violating_deltas()), 4)


if __name__ == "__main__":
    unittest.main()
