#!/usr/bin/env python3
"""Tests for harness/lib/init_sprint.sh."""
from __future__ import annotations
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (Path(__file__).parent.parent / "lib" / "init_sprint.sh").resolve()


class InitSprintHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        # init_sprint resolves paths relative to a git toplevel.
        subprocess.run(["git", "-C", self.tmp, "init", "-q"], check=True)

    def tearDown(self) -> None:
        subprocess.run(["rm", "-rf", self.tmp], check=False)

    def _run(self, *extra: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(SCRIPT), *extra],
            cwd=self.tmp, capture_output=True, text=True,
        )

    def test_creates_sprint_dir(self) -> None:
        goal = Path(self.tmp) / "goal.md"
        goal.write_text("Add a noop diagnostic\n")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("features/economy/**\n")
        r = self._run(
            "--run-id", "RUN1",
            "--sprint", "1",
            "--goal-file", str(goal),
            "--touch-surface", str(touch),
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        sprint_dir = Path(self.tmp) / "harness/runs/RUN1/sprint_1"
        self.assertTrue(sprint_dir.exists())
        self.assertTrue((sprint_dir / "contract.md").exists())
        self.assertTrue((sprint_dir / "meta.json").exists())
        self.assertTrue((sprint_dir / "touch_surface.allow").exists())
        # generator_session.jsonl created empty so tee can append.
        self.assertTrue((sprint_dir / "generator_session.jsonl").exists())

    def test_meta_records_inputs(self) -> None:
        goal = Path(self.tmp) / "goal.md"
        goal.write_text("Goal text")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("features/**\n")
        self._run(
            "--run-id", "RUN2", "--sprint", "3",
            "--goal-file", str(goal), "--touch-surface", str(touch),
        )
        meta = json.loads((Path(self.tmp) / "harness/runs/RUN2/sprint_3/meta.json").read_text())
        self.assertEqual(meta["run_id"], "RUN2")
        self.assertEqual(meta["sprint"], 3)
        self.assertIn("created_at", meta)
        self.assertIn("base_sha", meta)
        self.assertEqual(meta["touch_surface"], "harness/runs/RUN2/sprint_3/touch_surface.allow")

    def test_contract_template_includes_goal(self) -> None:
        goal = Path(self.tmp) / "g.md"
        goal.write_text("My sprint goal here.\n")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("**\n")
        self._run(
            "--run-id", "RUN3", "--sprint", "1",
            "--goal-file", str(goal), "--touch-surface", str(touch),
        )
        contract = (Path(self.tmp) / "harness/runs/RUN3/sprint_1/contract.md").read_text()
        self.assertIn("My sprint goal here.", contract)
        self.assertIn("## Status: NEGOTIATING", contract)

    def test_idempotent_when_dir_exists(self) -> None:
        goal = Path(self.tmp) / "g.md"
        goal.write_text("Goal")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("**\n")
        a = self._run("--run-id", "RX", "--sprint", "1",
                      "--goal-file", str(goal), "--touch-surface", str(touch))
        self.assertEqual(a.returncode, 0)
        # Second invocation must not overwrite contract.md if it has been edited.
        contract = Path(self.tmp) / "harness/runs/RX/sprint_1/contract.md"
        contract.write_text("# Custom contract\n\n## Done means\n- [test] x\n- [trace] events where ev=x must exist\n\n## Status: AGREED\n")
        b = self._run("--run-id", "RX", "--sprint", "1",
                      "--goal-file", str(goal), "--touch-surface", str(touch))
        self.assertEqual(b.returncode, 0)
        self.assertEqual(contract.read_text(), "# Custom contract\n\n## Done means\n- [test] x\n- [trace] events where ev=x must exist\n\n## Status: AGREED\n")


if __name__ == "__main__":
    unittest.main()
