#!/usr/bin/env python3
"""Tests for harness/lib/audit_log.py."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from audit_log import append_event, render_audit_markdown, snapshot_contract_turn  # noqa: E402


class TestAuditLog(unittest.TestCase):
    def test_append_event_writes_run_and_sprint_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            run_dir = Path(td) / "run-1"
            append_event(run_dir, "phase_a_started", sprint=1, round=1, agent="generator")

            run_events = [json.loads(line) for line in (run_dir / "events.jsonl").read_text().splitlines()]
            sprint_events = [
                json.loads(line)
                for line in (run_dir / "sprint_1" / "agent_turns.jsonl").read_text().splitlines()
            ]

        self.assertEqual(run_events[0]["event"], "phase_a_started")
        self.assertEqual(sprint_events[0]["agent"], "generator")

    def test_snapshot_contract_turn_and_render_audit_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            run_dir = Path(td) / "run-1"
            sprint_dir = run_dir / "sprint_1"
            sprint_dir.mkdir(parents=True)
            (sprint_dir / "contract.md").write_text("# Contract\n\n## Status: AGREED\n")
            snapshot = snapshot_contract_turn(sprint_dir, round_number=2, actor="evaluator")
            append_event(run_dir, "negotiation_turn", sprint=1, round=2, snapshot=str(snapshot))
            (run_dir / "sprint_list.md").write_text("# Sprint List\n")
            audit = render_audit_markdown(run_dir)
            text = audit.read_text()

        self.assertEqual(snapshot.name, "round_02_evaluator.md")
        self.assertIn("Harness Process Audit", text)
        self.assertIn("negotiation_turn", text)
        self.assertIn("contract_turns/round_02_evaluator.md", text)
        self.assertNotIn("### sprint_list.md", text)


if __name__ == "__main__":
    unittest.main()
