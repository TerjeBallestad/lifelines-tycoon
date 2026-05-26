#!/usr/bin/env python3
"""Tests for harness/lib/scan_tournament_trace.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from scan_tournament_trace import (  # noqa: E402
    parse_trace_rule,
    Quantifier,
    evaluate_rule,
    run_all,
    TraceRule,
)


class TestParseTraceRule(unittest.TestCase):
    def test_any_quantifier(self) -> None:
        body = "in any strategy: events where ev=diagnostic_completed count >= 2"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.ANY)
        self.assertEqual(r.event_filter, {"ev": "diagnostic_completed"})
        self.assertEqual(r.comparator, ">=")
        self.assertEqual(r.threshold, 2)

    def test_every_quantifier(self) -> None:
        body = "in every strategy: events where ev=case_file_updated count > 0"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.EVERY)

    def test_across_quantifier_with_field_filter(self) -> None:
        body = "across strategies: events where ev=action_failed and reason=client_refuses count >= 1"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.ACROSS)
        self.assertEqual(r.event_filter, {"ev": "action_failed", "reason": "client_refuses"})

    def test_default_to_across(self) -> None:
        body = "events where ev=intervention_completed count >= 1"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.ACROSS)


class TestEvaluateRule(unittest.TestCase):
    def setUp(self) -> None:
        self.fixtures = Path(__file__).parent / "fixtures"

    def test_any_passes_when_one_trace_meets_threshold(self) -> None:
        rule = parse_trace_rule("in any strategy: events where ev=diagnostic_completed count >= 1")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",
            self.fixtures / "trace_intervention_seed1.jsonl",
        ])
        self.assertTrue(result.passed)

    def test_every_fails_when_one_trace_misses(self) -> None:
        rule = parse_trace_rule("in every strategy: events where ev=diagnostic_completed count >= 1")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",   # has 2
            self.fixtures / "trace_intervention_seed1.jsonl",  # has 0
        ])
        self.assertFalse(result.passed)
        self.assertIn("intervention", result.failing_traces[0])

    def test_across_sums_counts(self) -> None:
        rule = parse_trace_rule("across strategies: events where ev=action_failed count >= 2")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",     # 1 fail
            self.fixtures / "trace_intervention_seed1.jsonl",  # 1 fail
        ])
        self.assertTrue(result.passed)

    def test_across_under_threshold_fails(self) -> None:
        rule = parse_trace_rule("across strategies: events where ev=action_failed count >= 5")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",
            self.fixtures / "trace_intervention_seed1.jsonl",
        ])
        self.assertFalse(result.passed)
        self.assertEqual(result.observed, 2)


    def test_process_event_vocabulary_matches_phase_a_audit_events(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            events = Path(td) / "events.jsonl"
            events.write_text(json.dumps({"event": "phase_a_agreed", "sprint": 1}) + "\n")
            rule = parse_trace_rule("events where event=phase_a_agreed count >= 1")
            result = evaluate_rule(rule, [events])
            self.assertTrue(result.passed)
            self.assertEqual(result.observed, 1)


class TestRunAll(unittest.TestCase):
    def test_writes_findings_json(self) -> None:
        fixtures = Path(__file__).parent / "fixtures"
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "trace_findings.json"
            findings = run_all(
                rules=[
                    TraceRule.parse("in any strategy: events where ev=diagnostic_completed count >= 1", index=0),
                    TraceRule.parse("in every strategy: events where ev=diagnostic_completed count >= 1", index=1),
                ],
                trace_files=[
                    fixtures / "trace_optimizer_seed1.jsonl",
                    fixtures / "trace_intervention_seed1.jsonl",
                ],
                out_path=out,
            )
            data = json.loads(out.read_text())
            self.assertEqual(len(data["items"]), 2)
            self.assertTrue(data["items"][0]["pass"])
            self.assertFalse(data["items"][1]["pass"])
            self.assertFalse(findings["all_pass"])


if __name__ == "__main__":
    unittest.main()
