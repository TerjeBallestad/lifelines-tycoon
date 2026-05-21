#!/usr/bin/env python3
"""Tests for harness/lib/scan_contract_trace.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from scan_contract_trace import (  # noqa: E402
    parse_trace_rule,
    evaluate_rule,
    scan_trace_file,
    TraceRuleError,
    TraceResult,
)

SAMPLE_EVENTS = [
    {"ev": "day_started", "day": 1, "t": {"d": 1, "h": 0.0}},
    {"ev": "diagnostic_completed", "id": "diag_psych_eval", "t": {"d": 1, "h": 9.5}},
    {"ev": "diagnostic_completed", "id": "diag_noop", "t": {"d": 1, "h": 12.0}},
    {"ev": "day_started", "day": 2, "t": {"d": 2, "h": 0.0}},
    {"ev": "overskudd_changed", "client": "elling", "v": 42.0, "t": {"d": 2, "h": 0.0}},
]


class TestParseTraceRule(unittest.TestCase):
    def test_count_ge_rule(self) -> None:
        r = parse_trace_rule("events where ev=diagnostic_completed count >= 1")
        self.assertEqual(r.predicates, {"ev": "diagnostic_completed"})
        self.assertEqual(r.op, ">=")
        self.assertEqual(r.value, 1)

    def test_conjunctive_predicates(self) -> None:
        r = parse_trace_rule("events where ev=diagnostic_completed and id=diag_noop count >= 1")
        self.assertEqual(r.predicates, {"ev": "diagnostic_completed", "id": "diag_noop"})

    def test_must_exist_sugar(self) -> None:
        r = parse_trace_rule("events where ev=day_started and day=2 must exist")
        self.assertEqual(r.op, ">=")
        self.assertEqual(r.value, 1)

    def test_unknown_op_rejected(self) -> None:
        with self.assertRaises(TraceRuleError):
            parse_trace_rule("events where ev=x count ~~ 3")

    def test_missing_count_or_must_rejected(self) -> None:
        with self.assertRaises(TraceRuleError):
            parse_trace_rule("events where ev=x")


class TestEvaluateRule(unittest.TestCase):
    def test_count_ge_pass(self) -> None:
        rule = parse_trace_rule("events where ev=diagnostic_completed count >= 1")
        res = evaluate_rule(rule, SAMPLE_EVENTS)
        self.assertTrue(res.passed)
        self.assertEqual(res.actual_count, 2)

    def test_count_eq_fail(self) -> None:
        rule = parse_trace_rule("events where ev=diagnostic_completed count == 3")
        res = evaluate_rule(rule, SAMPLE_EVENTS)
        self.assertFalse(res.passed)
        self.assertEqual(res.actual_count, 2)

    def test_conjunctive_predicate(self) -> None:
        rule = parse_trace_rule(
            "events where ev=diagnostic_completed and id=diag_noop must exist"
        )
        res = evaluate_rule(rule, SAMPLE_EVENTS)
        self.assertTrue(res.passed)
        self.assertEqual(res.actual_count, 1)


class TestScanTraceFile(unittest.TestCase):
    def _write(self, events: list[dict]) -> str:
        f = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
        for e in events:
            f.write(json.dumps(e) + "\n")
        f.close()
        return f.name

    def test_all_rules_pass(self) -> None:
        path = self._write(SAMPLE_EVENTS)
        rules_text = [
            "events where ev=day_started count >= 2",
            "events where ev=diagnostic_completed and id=diag_noop must exist",
        ]
        results = scan_trace_file(path, rules_text)
        self.assertTrue(all(r.passed for r in results))

    def test_one_rule_fails(self) -> None:
        path = self._write(SAMPLE_EVENTS)
        rules_text = [
            "events where ev=day_started count >= 5",   # only 2 in sample
        ]
        results = scan_trace_file(path, rules_text)
        self.assertFalse(results[0].passed)
        self.assertEqual(results[0].actual_count, 2)


if __name__ == "__main__":
    unittest.main()
