#!/usr/bin/env python3
"""Tests for harness/lib/contract_hash.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_hash import hash_contract_text, hash_contract_file  # noqa: E402

BASE = """# Sprint 1 Contract

## Goal
move axis 2 (decision density).

## Done means
- [test] `test/harness/sprint_1_density.gd::test_two_strategies_diverge` passes
- [trace] events where ev=diagnostic_completed count >= 2

## Rubric coverage
Axis 2 (Decision Density): primary

## Status: NEGOTIATING
"""

BASE_AGREED = BASE.replace("## Status: NEGOTIATING", "## Status: AGREED")
BASE_EXTRA_WHITESPACE = BASE.replace("## Done means\n", "## Done means\n\n").replace("\n## Status:", "\n\n## Status:")
BASE_REORDERED_ITEMS = BASE.replace(
    "- [test] `test/harness/sprint_1_density.gd::test_two_strategies_diverge` passes\n"
    "- [trace] events where ev=diagnostic_completed count >= 2\n",
    "- [trace] events where ev=diagnostic_completed count >= 2\n"
    "- [test] `test/harness/sprint_1_density.gd::test_two_strategies_diverge` passes\n",
)
BASE_NEW_ITEM = BASE.replace(
    "- [trace] events where ev=diagnostic_completed count >= 2\n",
    "- [trace] events where ev=diagnostic_completed count >= 2\n"
    "- [judge] freeplay run names Elling explicitly\n",
)


class TestHashContract(unittest.TestCase):
    def test_status_difference_changes_hash(self) -> None:
        self.assertNotEqual(hash_contract_text(BASE), hash_contract_text(BASE_AGREED))

    def test_whitespace_only_change_same_hash(self) -> None:
        self.assertEqual(hash_contract_text(BASE), hash_contract_text(BASE_EXTRA_WHITESPACE))

    def test_item_reorder_changes_hash(self) -> None:
        # Item order is semantically meaningful (it's a checklist).
        self.assertNotEqual(hash_contract_text(BASE), hash_contract_text(BASE_REORDERED_ITEMS))

    def test_new_item_changes_hash(self) -> None:
        self.assertNotEqual(hash_contract_text(BASE), hash_contract_text(BASE_NEW_ITEM))

    def test_hash_is_hex_and_stable(self) -> None:
        h1 = hash_contract_text(BASE)
        h2 = hash_contract_text(BASE)
        self.assertEqual(h1, h2)
        self.assertRegex(h1, r"^[0-9a-f]{32,64}$")


class TestHashContractFile(unittest.TestCase):
    def test_round_trip(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
            fh.write(BASE)
            p = fh.name
        self.assertEqual(hash_contract_file(p), hash_contract_text(BASE))


if __name__ == "__main__":
    unittest.main()
