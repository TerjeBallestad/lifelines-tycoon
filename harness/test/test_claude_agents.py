#!/usr/bin/env python3
"""Tests for Plan 5 Phase A agent selection."""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_agents import negotiation_agents_from_env  # noqa: E402
from contract_schema import parse_contract  # noqa: E402
from contract_template import seed_contract_text  # noqa: E402
from negotiation_state import Turn  # noqa: E402


class TestNegotiationAgentSelection(unittest.TestCase):
    def test_dry_run_defaults_to_scripted_agents_that_write_agreed_contract(self) -> None:
        with tempfile.TemporaryDirectory() as td, mock.patch.dict(os.environ, {}, clear=True):
            sprint_dir = Path(td)
            (sprint_dir / "contract.md").write_text(
                seed_contract_text(run_id="r", sprint=1, goal_md="# Goal\n")
            )
            gen, evaluator = negotiation_agents_from_env(run_id="r", sprint=1)

            self.assertEqual(gen.role, Turn.GENERATOR)
            self.assertEqual(evaluator.role, Turn.EVALUATOR)

            gen.take_turn(sprint_dir, 1)
            after_generator = (sprint_dir / "contract.md").read_text()
            self.assertNotIn("__REPLACE_ME__", after_generator)
            self.assertEqual(parse_contract(after_generator).status, "AGREED")

            evaluator.take_turn(sprint_dir, 2)
            after_evaluator = (sprint_dir / "contract.md").read_text()
            self.assertEqual(after_generator, after_evaluator)

    def test_command_mode_requires_role_commands(self) -> None:
        with mock.patch.dict(os.environ, {"NEGOTIATION_AGENT_MODE": "command"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "GENERATOR_PHASE_A_CMD"):
                negotiation_agents_from_env(run_id="r", sprint=1)

    def test_live_defaults_to_claude_wrappers(self) -> None:
        with mock.patch.dict(os.environ, {"NEGOTIATION_LIVE": "1"}, clear=True):
            gen, evaluator = negotiation_agents_from_env(run_id="r", sprint=1)
            self.assertEqual(gen.role, Turn.GENERATOR)
            self.assertEqual(evaluator.role, Turn.EVALUATOR)
            self.assertIn("run_generator.sh", gen.script)
            self.assertIn("run_evaluator_agent.sh", evaluator.script)


if __name__ == "__main__":
    unittest.main()
