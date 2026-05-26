#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from run_state import RunState, SprintRunState, RunStateError  # noqa: E402


class TestRunState(unittest.TestCase):
    def test_new_state_has_planning_status(self) -> None:
        state = RunState.new("run-1", "abc123", "harness/run-1/integration")
        self.assertEqual(state.status, "PLANNING")
        self.assertEqual(state.run_id, "run-1")
        self.assertEqual(state.base_sha, "abc123")
        self.assertEqual(state.integration_branch, "harness/run-1/integration")
        self.assertEqual(state.history[-1]["event"], "run_created")

    def test_record_appends_timestamped_history(self) -> None:
        state = RunState.new("run-1", "abc123", "harness/run-1/integration")
        state.record("planner_started", attempt=1)
        event = state.history[-1]
        self.assertEqual(event["event"], "planner_started")
        self.assertEqual(event["attempt"], 1)
        self.assertIn("ts", event)

    def test_pivot_increments_sprint_attempt(self) -> None:
        state = RunState.new("run-1", "abc123", "harness/run-1/integration")
        state.sprints.append(SprintRunState(number=1, title="First", optional=False))
        state.set_sprint_status(1, "PIVOT", verdict="PIVOT", note="too bland")
        sprint = state.sprints[0]
        self.assertEqual(sprint.status, "PIVOT")
        self.assertEqual(sprint.attempt, 2)
        self.assertEqual(sprint.verdict, "PIVOT")
        self.assertIn("too bland", sprint.notes)

    def test_state_round_trips_through_json(self) -> None:
        state = RunState.new("run-1", "abc123", "harness/run-1/integration")
        state.status = "RUNNING"
        state.current_sprint = 1
        state.sprints.append(SprintRunState(number=1, title="First", optional=True, branch="harness/run-1/sprint_1"))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "run_state.json"
            state.to_file(path)
            loaded = RunState.from_file(path)
            self.assertEqual(json.loads(path.read_text())["sprints"][0]["title"], "First")
        self.assertEqual(loaded, state)

    def test_illegal_sprint_status_raises(self) -> None:
        state = RunState.new("run-1", "abc123", "harness/run-1/integration")
        state.sprints.append(SprintRunState(number=1, title="First", optional=False))
        with self.assertRaises(RunStateError):
            state.set_sprint_status(1, "BOGUS")

    def test_unknown_sprint_number_raises(self) -> None:
        state = RunState.new("run-1", "abc123", "harness/run-1/integration")
        with self.assertRaises(RunStateError):
            state.set_sprint_status(99, "RUNNING")


if __name__ == "__main__":
    unittest.main()
