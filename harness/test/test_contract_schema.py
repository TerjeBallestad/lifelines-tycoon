#!/usr/bin/env python3
"""Tests for harness/lib/contract_schema.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_schema import (  # noqa: E402
    parse_contract,
    Contract,
    ContractItem,
    ContractSchemaError,
)


VALID = """# Sprint 1 Contract

## Done means
- [test] `test/harness/sprint_1_noop.gd::test_runs` passes
- [trace] events where ev=diagnostic_completed and id=diag_noop count >= 1
- [judge] freeplay run text mentions "Elling" specifically

## Rubric coverage
Axis 2 (Decision Density): primary
Axis 1 (Theme): touched

## Forbidden side-effects
- baseline axis 5 must hold

## Status: AGREED
"""

NEGOTIATING = VALID.replace("## Status: AGREED", "## Status: NEGOTIATING")
ONLY_JUDGE = """# Sprint X Contract

## Done means
- [judge] looks good

## Status: AGREED
"""


class TestParseContract(unittest.TestCase):
    def test_parses_agreed(self) -> None:
        c = parse_contract(VALID)
        self.assertEqual(c.status, "AGREED")
        self.assertEqual(len(c.items), 3)

    def test_item_types_extracted(self) -> None:
        c = parse_contract(VALID)
        kinds = [i.kind for i in c.items]
        self.assertEqual(sorted(kinds), ["judge", "test", "trace"])

    def test_trace_body_preserved(self) -> None:
        c = parse_contract(VALID)
        trace_items = [i for i in c.items if i.kind == "trace"]
        self.assertEqual(len(trace_items), 1)
        self.assertIn("diagnostic_completed", trace_items[0].body)

    def test_negotiating_status(self) -> None:
        c = parse_contract(NEGOTIATING)
        self.assertEqual(c.status, "NEGOTIATING")

    def test_no_status_line_rejected(self) -> None:
        with self.assertRaises(ContractSchemaError):
            parse_contract("# Sprint Y\n\n## Done means\n- [test] x\n")

    def test_pure_judge_contract_rejected(self) -> None:
        # Spec §6.2: contracts must have ≥50% test/trace items.
        with self.assertRaises(ContractSchemaError):
            parse_contract(ONLY_JUDGE)

    def test_unknown_item_kind_rejected(self) -> None:
        bad = "# X\n\n## Done means\n- [vibes] x\n\n## Status: AGREED\n"
        with self.assertRaises(ContractSchemaError):
            parse_contract(bad)

    def test_no_done_items_rejected(self) -> None:
        bad = "# X\n\n## Done means\n\n## Status: AGREED\n"
        with self.assertRaises(ContractSchemaError):
            parse_contract(bad)


class TestParseContractFile(unittest.TestCase):
    def test_round_trip_from_file(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
            fh.write(VALID)
            path = fh.name
        c = Contract.from_file(path)
        self.assertEqual(c.status, "AGREED")
        self.assertEqual(len(c.items), 3)


if __name__ == "__main__":
    unittest.main()
