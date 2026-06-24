#!/usr/bin/env python3
"""PLAN-001 Task 17 — unit tests for the blind-read gate SCORER + fresh-seed guard.

Tests the pure scoring/tally logic with SYNTHETIC inputs only — no Godot, no claude.
Covers:
  - score_named_problem: ground-truth keyword match (positive + negative), the
    unconfirmed-ground-truth clause, and empty-reader handling.
  - tally_verdict: the M-of-N count AND the HARD fresh-seed-must-pass circularity
    guard (a fresh-seed failure fails the gate even at 4/5).
  - derive_ground_truth / redact_for_reader plumbing on synthetic snapshots.

RUN:
    python3 -m unittest scripts.gate.test_gate_scoring
    # or, from scripts/gate/:  python3 -m unittest test_gate_scoring

## Verified red-green: 2026-06-24
Broke the scorer by making score_named_problem always return (True, "stub") —
test_wrong_problem_fails and test_empty_reader_fails then FAILED (a wrong/empty
named problem wrongly "passed"). Also broke tally_verdict's fresh-seed guard by
removing the `not fresh_failures` clause — test_fresh_seed_failure_fails_even_at_4of5
then FAILED. Restored both; all green. (See RED-GREEN NOTE blocks inline.)
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

# Import the gate module whether run as a package (scripts.gate.test_gate_scoring)
# or directly from inside scripts/gate/.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import blind_read_gate as gate  # noqa: E402


def gt_confirmed(colors=None) -> dict:
    """A CONFIRMED Blue-dominant ground truth (the real seeded shape)."""
    return gate.derive_ground_truth(colors or [0.0, 0.8, 0.0, 0.0, 0.4])


def gt_unconfirmed() -> dict:
    """A ground truth where reveal_hidden never surfaced colors (boot/schema drift)."""
    return gate.derive_ground_truth([])


class TestDeriveGroundTruth(unittest.TestCase):
    def test_blue_dominant_is_confirmed(self):
        gt = gate.derive_ground_truth([0.0, 0.8, 0.0, 0.0, 0.4])
        self.assertTrue(gt["ok"])
        self.assertEqual(gt["dominant_axis"], "blue")

    def test_non_blue_dominant_is_unconfirmed(self):
        # Red-dominant client: NOT the seeded withdrawal shape -> ground truth not ok.
        gt = gate.derive_ground_truth([0.0, 0.1, 0.0, 0.9, 0.2])
        self.assertFalse(gt["ok"])
        self.assertEqual(gt["dominant_axis"], "red")

    def test_missing_colors_is_unconfirmed(self):
        gt = gate.derive_ground_truth([])
        self.assertFalse(gt["ok"])


class TestScoreNamedProblem(unittest.TestCase):
    def test_telescope_answer_passes(self):
        passed, reason = gate.score_named_problem(
            "Telescope fixation and withdrawal from contact", gt_confirmed())
        self.assertTrue(passed, reason)

    def test_isolation_answer_passes(self):
        passed, _ = gate.score_named_problem("Social isolation", gt_confirmed())
        self.assertTrue(passed)

    def test_alone_phrasing_passes(self):
        passed, _ = gate.score_named_problem(
            "He spends his days alone, withdrawn", gt_confirmed())
        self.assertTrue(passed)

    # ---- RED-GREEN NOTE: this is the test that catches an always-true scorer ----
    def test_wrong_problem_fails(self):
        # A reader that names a DIFFERENT dominant problem with no ground-truth
        # keyword must FAIL. If the scorer were stubbed to always-pass, this fails.
        passed, reason = gate.score_named_problem(
            "Financial debt and unpaid rent", gt_confirmed())
        self.assertFalse(passed, reason)

    def test_empty_reader_fails(self):
        passed, _ = gate.score_named_problem("", gt_confirmed())
        self.assertFalse(passed)

    def test_unconfirmed_ground_truth_never_passes(self):
        # Even a perfect named answer must FAIL if ground truth was not confirmed
        # (reveal_hidden didn't surface the Blue-withdrawal shape) — this is the
        # plumbing-failure guard, not a lucky keyword.
        passed, reason = gate.score_named_problem(
            "telescope withdrawal isolation alone", gt_unconfirmed())
        self.assertFalse(passed, reason)
        self.assertIn("unconfirmed", reason.lower())

    def test_case_insensitive(self):
        passed, _ = gate.score_named_problem("TELESCOPE FIXATION", gt_confirmed())
        self.assertTrue(passed)


class TestTallyVerdict(unittest.TestCase):
    @staticmethod
    def _mk(seed: int, passed: bool) -> dict:
        return {"seed": seed, "passed": passed, "named": "x", "reason": "x", "n_derived": 1}

    def _per_seed(self, mapping: dict) -> dict:
        return {s: self._mk(s, p) for s, p in mapping.items()}

    def test_all_five_pass(self):
        v = gate.tally_verdict(self._per_seed(
            {101: True, 202: True, 303: True, 747: True, 919: True}))
        self.assertTrue(v["passed"])
        self.assertEqual(v["n_pass"], 5)

    def test_four_of_five_authoring_fail_passes_when_fresh_ok(self):
        # 4/5 with an AUTHORING seed failing — both fresh seeds pass -> gate PASSES.
        v = gate.tally_verdict(self._per_seed(
            {101: False, 202: True, 303: True, 747: True, 919: True}))
        self.assertTrue(v["passed"])
        self.assertEqual(v["n_pass"], 4)
        self.assertEqual(v["fresh_failures"], [])

    # ---- RED-GREEN NOTE: this is the test that catches a removed fresh-seed guard ----
    def test_fresh_seed_failure_fails_even_at_4of5(self):
        # 4/5 passers but a FRESH seed (747) failed -> the HARD guard fails the gate.
        v = gate.tally_verdict(self._per_seed(
            {101: True, 202: True, 303: True, 747: False, 919: True}))
        self.assertEqual(v["n_pass"], 4)               # meets M-of-N count
        self.assertFalse(v["passed"])                  # ...but guard fails it
        self.assertIn(747, v["fresh_failures"])

    def test_both_fresh_fail(self):
        v = gate.tally_verdict(self._per_seed(
            {101: True, 202: True, 303: True, 747: False, 919: False}))
        self.assertFalse(v["passed"])
        self.assertEqual(sorted(v["fresh_failures"]), [747, 919])

    def test_three_of_five_fails_count(self):
        v = gate.tally_verdict(self._per_seed(
            {101: False, 202: False, 303: True, 747: True, 919: True}))
        self.assertFalse(v["passed"])  # 3 < 4 required
        self.assertEqual(v["n_pass"], 3)

    def test_single_seed_smoke_requires_that_seed(self):
        # A one-seed run requires that single seed to pass (m_required clamps to N).
        v_pass = gate.tally_verdict(self._per_seed({202: True}))
        self.assertTrue(v_pass["passed"])
        v_fail = gate.tally_verdict(self._per_seed({202: False}))
        self.assertFalse(v_fail["passed"])

    def test_single_fresh_seed_smoke_must_pass(self):
        # A one-fresh-seed run: the fresh guard still applies.
        v = gate.tally_verdict(self._per_seed({747: False}))
        self.assertFalse(v["passed"])
        self.assertIn(747, v["fresh_failures"])


class TestRedaction(unittest.TestCase):
    def _snapshot(self) -> dict:
        return {
            "time": {"day": 14, "hour": 12.0},
            "client": {
                "id": "elling", "display_name": "Elling",
                "needs": {"social": 0.9}, "cognitive": {"clarity": 0.3},
                "overskudd": 0.4, "overskudd_ceiling": 0.6,
                "colors": [0.0, 0.8, 0.0, 0.0, 0.4],
                "skills": {},
            },
            "case_file": {
                "entries": [
                    {"id": "trace_telescope_hours", "title": "Long stretches at the telescope",
                     "tags": [], "provenance": "derived"},
                    {"id": "authored_consequence", "title": "Scheduled meal delivered",
                     "tags": [], "provenance": "authored"},
                ],
                "tags": {},
            },
        }

    def test_redaction_strips_raw_numbers_and_colors(self):
        red = gate.redact_for_reader(self._snapshot())
        client = red["client"]
        for k in ("needs", "cognitive", "overskudd", "overskudd_ceiling", "colors"):
            self.assertNotIn(k, client, f"{k} leaked into the reader view")

    def test_redaction_keeps_only_derived_entries(self):
        red = gate.redact_for_reader(self._snapshot())
        entries = red["case_file"]["entries"]
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["provenance"], "derived")

    def test_redaction_does_not_mutate_input(self):
        snap = self._snapshot()
        gate.redact_for_reader(snap)
        self.assertIn("needs", snap["client"])  # original untouched
        self.assertEqual(len(snap["case_file"]["entries"]), 2)

    def test_derived_titles_only(self):
        red = gate.redact_for_reader(self._snapshot())
        titles = gate.derived_titles(red)
        self.assertEqual(titles, ["Long stretches at the telescope"])


class TestPromptBuild(unittest.TestCase):
    def test_prompt_contains_derived_facts_not_raw_numbers(self):
        redacted = {
            "client": {"id": "elling", "display_name": "Elling", "skills": {}},
            "case_file": {"entries": [
                {"id": "t", "title": "Whole days pass without company",
                 "tags": [], "provenance": "derived"}]},
            "time": {"day": 14},
        }
        uncovered = [{"ev": "patterns_evaluated", "uncovered": {"act_use_telescope": 25}}]
        prompt = gate.build_prompt(redacted, uncovered, days=14)
        self.assertIn("Whole days pass without company", prompt)
        self.assertIn("single dominant problem", prompt.lower())
        # No raw needs numbers should appear.
        self.assertNotIn("0.9", prompt)

    # ---- RED-GREEN NOTE: this is the test that catches the SB-002 leak ----
    def test_prompt_does_NOT_leak_raw_uncovered_activity_channel(self):
        # SB-002: the raw `activity_id: count` uncovered channel handed the reader the
        # dominant activity in plain text (e.g. `act_use_telescope: 25`), letting it name
        # "telescope/isolation" from the raw count ALONE — bypassing the derived facts.
        # The reader prompt must contain NEITHER the activity id NOR its raw count.
        redacted = {
            "client": {"id": "elling", "display_name": "Elling", "skills": {}},
            "case_file": {"entries": [
                {"id": "t", "title": "Whole days pass without company",
                 "tags": [], "provenance": "derived"}]},
            "time": {"day": 14},
        }
        uncovered = [
            {"ev": "patterns_evaluated",
             "uncovered": {"act_use_telescope": 25, "act_read_book": 4}},
        ]
        prompt = gate.build_prompt(redacted, uncovered, days=14)
        # No activity id may appear.
        self.assertNotIn("act_use_telescope", prompt)
        self.assertNotIn("act_read_book", prompt)
        # No raw per-activity count (25 or 4) may appear in id:count form.
        self.assertNotIn("act_use_telescope: 25", prompt)
        self.assertNotIn("telescope", prompt.lower())
        # The only residual uncovered signal is the OPAQUE category count (2), which
        # cannot, alone, name the dominant problem.
        self.assertIn("2 decision categories", prompt)

    def test_prompt_opaque_uncovered_count_is_singular_when_one(self):
        redacted = {
            "client": {"id": "elling", "display_name": "Elling", "skills": {}},
            "case_file": {"entries": [
                {"id": "t", "title": "X", "tags": [], "provenance": "derived"}]},
            "time": {"day": 14},
        }
        uncovered = [{"ev": "patterns_evaluated", "uncovered": {"act_x": 3}}]
        prompt = gate.build_prompt(redacted, uncovered, days=14)
        self.assertIn("1 decision category ", prompt)
        self.assertNotIn("act_x", prompt)


if __name__ == "__main__":
    unittest.main()
