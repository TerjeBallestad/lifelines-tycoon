#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from planner_agent import PlannerError, run_planner  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestPlannerAgent(unittest.TestCase):
    def test_shim_mode_copies_and_validates_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            prompt_file = run_dir / "prompt.txt"
            prompt_file.write_text("Make day-one decisions diverge.\n")

            output = run_planner(
                run_dir=run_dir,
                prompt_file=prompt_file,
                live=False,
                shim_output=FIXTURES / "sprint_list_valid.md",
            )

            self.assertEqual(output, run_dir / "sprint_list.md")
            self.assertEqual(output.read_text(), (FIXTURES / "sprint_list_valid.md").read_text())

    def test_invalid_shim_output_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            prompt_file = run_dir / "prompt.txt"
            prompt_file.write_text("Make day-one decisions diverge.\n")

            with self.assertRaises(PlannerError):
                run_planner(
                    run_dir=run_dir,
                    prompt_file=prompt_file,
                    live=False,
                    shim_output=FIXTURES / "sprint_list_invalid_missing_touch.md",
                )

    def test_shim_mode_requires_fixture_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            prompt_file = run_dir / "prompt.txt"
            prompt_file.write_text("Make day-one decisions diverge.\n")

            with self.assertRaises(PlannerError):
                run_planner(run_dir=run_dir, prompt_file=prompt_file, live=False)

    def test_live_mode_fails_early_when_configured_agent_command_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            prompt_file = run_dir / "prompt.txt"
            prompt_file.write_text("Make day-one decisions diverge.\n")

            env = {"HARNESS_PLANNER_COMMAND": "definitely-missing-planner-agent"}
            with mock.patch.dict(os.environ, env, clear=False):
                with self.assertRaises(PlannerError):
                    run_planner(run_dir=run_dir, prompt_file=prompt_file, live=True, max_retries=1)

    def test_live_mode_retries_and_accepts_fenced_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            run_dir = tmp_path / "run"
            prompt_file = tmp_path / "prompt.txt"
            prompt_file.write_text("Make day-one decisions diverge.\n")
            valid_fixture = FIXTURES / "sprint_list_valid.md"
            invalid_fixture = FIXTURES / "sprint_list_invalid_missing_touch.md"
            script = tmp_path / "planner_command.py"
            script.write_text(
                "from __future__ import annotations\n"
                "import os\n"
                "from pathlib import Path\n"
                f"valid = Path({str(valid_fixture)!r})\n"
                f"invalid = Path({str(invalid_fixture)!r})\n"
                "if os.environ.get('HARNESS_PLANNER_ATTEMPT') == '1':\n"
                "    print(invalid.read_text())\n"
                "else:\n"
                "    print('```markdown')\n"
                "    print(valid.read_text())\n"
                "    print('```')\n"
            )

            env = {"HARNESS_PLANNER_COMMAND": f"python3 {script}"}
            with mock.patch.dict(os.environ, env, clear=False):
                output = run_planner(
                    run_dir=run_dir,
                    prompt_file=prompt_file,
                    live=True,
                    max_retries=1,
                )

            self.assertEqual(output.read_text(), valid_fixture.read_text())
            self.assertTrue((run_dir / "planner_session.jsonl").is_file())


if __name__ == "__main__":
    unittest.main()
