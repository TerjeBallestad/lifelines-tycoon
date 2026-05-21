#!/usr/bin/env python3
"""Tests for harness/lib/contract_template.py."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_template import (  # noqa: E402
    seed_contract_text,
    SEED_MARKER,
    contains_seed_marker,
)
from contract_schema import parse_contract  # noqa: E402


SAMPLE_GOAL = """# Sprint 1 — Decision density

Make day-1 decisions diverge across optimizer vs neglect strategies.

Touch surface: features/economy/*, features/case_file/*.
"""


class TestSeedContract(unittest.TestCase):
    def test_seed_parses_under_contract_schema(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        # The template must satisfy contract_schema (≥50% test/trace).
        c = parse_contract(text)
        self.assertEqual(c.status, "NEGOTIATING")
        # At least one [test] and one [trace] item present.
        kinds = {i.kind for i in c.items}
        self.assertIn("test", kinds)
        self.assertIn("trace", kinds)

    def test_seed_contains_marker(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        self.assertTrue(contains_seed_marker(text))
        self.assertIn(SEED_MARKER, text)

    def test_seed_embeds_goal_title_line(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        # The first non-blank line of the goal should be referenced in the contract header.
        self.assertIn("Decision density", text)

    def test_seed_references_rubric_path(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        self.assertIn("docs/rubric/rubric.md", text)


class TestSeedMarkerCheck(unittest.TestCase):
    def test_replaced_seed_no_marker(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        text = text.replace(SEED_MARKER, "concrete-replacement")
        self.assertFalse(contains_seed_marker(text))


if __name__ == "__main__":
    unittest.main()
