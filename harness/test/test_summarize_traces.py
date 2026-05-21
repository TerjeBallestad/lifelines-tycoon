#!/usr/bin/env python3
"""Tests for harness/lib/summarize_traces.py."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from summarize_traces import (  # noqa: E402
    summarize_trace,
    summarize_directory,
    TraceSummary,
)

FIXTURES = Path(__file__).parent / "fixtures"


class TestSummarizeTrace(unittest.TestCase):
    def test_counts_events(self) -> None:
        s = summarize_trace(FIXTURES / "trace_optimizer_seed1.jsonl")
        self.assertEqual(s.strategy, "optimizer")
        self.assertEqual(s.seed, 1)
        self.assertEqual(s.counts["diagnostic_completed"], 2)
        self.assertEqual(s.counts["intervention_completed"], 0)
        self.assertEqual(s.counts["action_failed"], 1)
        self.assertEqual(s.counts["case_file_updated"], 2)
        self.assertEqual(s.days_observed, 2)

    def test_collects_case_file_entries(self) -> None:
        s = summarize_trace(FIXTURES / "trace_optimizer_seed1.jsonl")
        self.assertIn("obs_alphabetizes", s.case_file_entries)
        self.assertIn("obs_morning_quiet", s.case_file_entries)

    def test_collects_failures_with_reason(self) -> None:
        s = summarize_trace(FIXTURES / "trace_optimizer_seed1.jsonl")
        self.assertEqual(s.failures, [("int_phone_call", "client_refuses")])

    def test_freeplay_collects_narration(self) -> None:
        s = summarize_trace(FIXTURES / "trace_freeplay.jsonl")
        self.assertEqual(len(s.narration), 2)
        self.assertIn("quiet", s.narration[1])

    def test_directory_summarize(self) -> None:
        summaries = summarize_directory(FIXTURES, glob="trace_*.jsonl")
        ids = sorted(s.strategy for s in summaries)
        self.assertEqual(ids, ["freeplay", "intervention", "optimizer"])


if __name__ == "__main__":
    unittest.main()
