#!/usr/bin/env python3
"""Tests for harness/lib/init_negotiation.sh."""
from __future__ import annotations
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HARNESS_LIB = Path(__file__).parent.parent / "lib"
INIT = HARNESS_LIB / "init_negotiation.sh"

GOAL_MD = """# Sprint 1 — Decision density

Make day-1 decisions diverge across optimizer vs neglect strategies.
"""

TOUCH_ALLOW = """features/economy/
features/case_file/
test/harness/
"""


class TestInitNegotiation(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.cwd = Path(self.tmpdir)
        (self.cwd / "harness" / "lib").mkdir(parents=True)
        (self.cwd / "harness" / ".locks").mkdir(parents=True)
        # Copy our scripts into the temp project root so the script resolves siblings.
        shutil.copy(INIT, self.cwd / "harness" / "lib" / "init_negotiation.sh")
        os.chmod(self.cwd / "harness" / "lib" / "init_negotiation.sh", 0o755)
        # The shell script imports the Python templates by absolute path; symlink them.
        for mod in ("contract_template.py", "contract_schema.py", "negotiation_state.py"):
            src = HARNESS_LIB / mod
            os.symlink(src, self.cwd / "harness" / "lib" / mod)
        # Write goal + allow files.
        self.goal = self.cwd / "sprint_goal.md"
        self.goal.write_text(GOAL_MD)
        self.allow = self.cwd / "sprint_touch.allow"
        self.allow.write_text(TOUCH_ALLOW)

    def _run(self, *extra: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                "bash",
                str(self.cwd / "harness" / "lib" / "init_negotiation.sh"),
                "--run-id", "test-run",
                "--sprint", "1",
                "--goal-file", str(self.goal),
                "--touch-surface", str(self.allow),
                *extra,
            ],
            cwd=self.cwd,
            capture_output=True,
            text=True,
        )

    def test_creates_sprint_dir_and_artifacts(self) -> None:
        cp = self._run()
        self.assertEqual(cp.returncode, 0, cp.stderr)
        sprint_dir = self.cwd / "harness" / "runs" / "test-run" / "sprint_1"
        self.assertTrue(sprint_dir.is_dir())
        self.assertTrue((sprint_dir / "goal.md").exists())
        self.assertTrue((sprint_dir / "touch_surface.allow").exists())
        self.assertTrue((sprint_dir / "contract.md").exists())
        self.assertTrue((sprint_dir / "negotiation_state.json").exists())

    def test_seed_contract_has_replace_me_marker(self) -> None:
        self._run()
        contract = (self.cwd / "harness" / "runs" / "test-run" / "sprint_1" / "contract.md").read_text()
        self.assertIn("__REPLACE_ME__", contract)
        self.assertIn("## Status: NEGOTIATING", contract)

    def test_state_starts_at_zero_turns(self) -> None:
        self._run()
        state = json.loads(
            (self.cwd / "harness" / "runs" / "test-run" / "sprint_1" / "negotiation_state.json").read_text()
        )
        self.assertEqual(state["run_id"], "test-run")
        self.assertEqual(state["sprint"], 1)
        self.assertEqual(state["rounds_used"], 0)
        self.assertEqual(state["turns"], [])

    def test_rerun_without_force_errors(self) -> None:
        self.assertEqual(self._run().returncode, 0)
        cp = self._run()
        self.assertNotEqual(cp.returncode, 0)
        self.assertIn("already initialized", cp.stderr)

    def test_rerun_with_force_overwrites(self) -> None:
        self.assertEqual(self._run().returncode, 0)
        cp = self._run("--force")
        self.assertEqual(cp.returncode, 0, cp.stderr)

    def test_existing_identical_goal_and_allow_files_are_safe(self) -> None:
        sprint_dir = self.cwd / "harness" / "runs" / "test-run" / "sprint_1"
        sprint_dir.mkdir(parents=True)
        (sprint_dir / "goal.md").write_text(GOAL_MD)
        (sprint_dir / "touch_surface.allow").write_text(TOUCH_ALLOW)
        self.goal = sprint_dir / "goal.md"
        self.allow = sprint_dir / "touch_surface.allow"

        cp = self._run()
        self.assertEqual(cp.returncode, 0, cp.stderr)
        self.assertTrue((sprint_dir / "contract.md").exists())


if __name__ == "__main__":
    unittest.main()
