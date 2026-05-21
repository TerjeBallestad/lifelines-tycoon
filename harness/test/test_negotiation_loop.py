#!/usr/bin/env python3
"""Tests for harness/lib/negotiation_loop.py."""
from __future__ import annotations
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from negotiation_loop import (  # noqa: E402
    NegotiationLoop,
    TurnAgent,
    NegotiationOutcome,
)
from negotiation_state import NegotiationState, Turn  # noqa: E402
from contract_template import seed_contract_text  # noqa: E402
from contract_hash import hash_contract_text  # noqa: E402


VALID_NEGOTIATING = """# Sprint 1 Contract — X

## Done means
- [test] `test/harness/sprint_1.gd::test_x` passes
- [trace] events where ev=diagnostic_completed count >= 1

## Status: NEGOTIATING
"""

VALID_AGREED = VALID_NEGOTIATING.replace("## Status: NEGOTIATING", "## Status: AGREED")
VALID_EDITED_AGREED = """# Sprint 1 Contract — X

## Done means
- [test] `test/harness/sprint_1.gd::test_x_specific` passes
- [trace] events where ev=diagnostic_completed and id=diag_psych_eval count >= 1

## Status: AGREED
"""


class ScriptedAgent(TurnAgent):
    """Test double — writes a pre-programmed sequence of contracts on each turn."""

    def __init__(self, role: Turn, scripted_writes: list[str]) -> None:
        self.role = role
        self.scripted_writes = scripted_writes
        self.calls = 0

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        contract_path = sprint_dir / "contract.md"
        contract_path.write_text(self.scripted_writes[self.calls])
        self.calls += 1


class TestNegotiationLoopHappyPath(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.sprint = self.tmp / "harness" / "runs" / "test-run" / "sprint_1"
        self.sprint.mkdir(parents=True)
        self.lock = self.tmp / "harness" / ".locks" / "x.lock"
        self.lock.parent.mkdir(parents=True)
        self.lock.touch()
        # Seed initial contract + state.
        seed = seed_contract_text(run_id="test-run", sprint=1, goal_md="# Goal\n")
        # Replace markers so the seed parses (the agents would normally do this).
        seed = seed.replace("__REPLACE_ME__", "concrete")
        (self.sprint / "contract.md").write_text(seed)
        NegotiationState.new(run_id="test-run", sprint=1, max_rounds=5).to_file(
            self.sprint / "negotiation_state.json"
        )

    def test_terminates_when_both_agree_consecutively(self) -> None:
        # Generator: draft NEGOTIATING, then confirm AGREED unchanged.
        gen = ScriptedAgent(Turn.GENERATOR, [VALID_NEGOTIATING, VALID_AGREED])
        # Evaluator: respond AGREED unchanged after seeing gen's first draft.
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        # Final state should record: gen NEGOTIATING, eval AGREED, gen AGREED.
        state = NegotiationState.from_file(self.sprint / "negotiation_state.json")
        self.assertTrue(state.is_terminal_agreed())
        self.assertEqual(state.current_round(), 3)

    def test_edits_on_confirming_turn_reset_terminal(self) -> None:
        # Generator: NEGOTIATING, then AGREED-BUT-EDITED (hash changes).
        gen = ScriptedAgent(Turn.GENERATOR, [VALID_NEGOTIATING, VALID_EDITED_AGREED, VALID_EDITED_AGREED])
        # Evaluator: AGREED, then AGREED unchanged.
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED, VALID_EDITED_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        state = NegotiationState.from_file(self.sprint / "negotiation_state.json")
        # gen-draft, eval-agreed, gen-agreed-edited, eval-agreed-unchanged → terminal at round 4
        self.assertEqual(state.current_round(), 4)

    def test_force_pivot_at_max_rounds(self) -> None:
        gen = ScriptedAgent(Turn.GENERATOR, [VALID_NEGOTIATING] * 5)
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_NEGOTIATING] * 5)
        # max_rounds=4 so loop hits pivot after 4 turns.
        NegotiationState.new(run_id="test-run", sprint=1, max_rounds=4).to_file(
            self.sprint / "negotiation_state.json"
        )
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.FORCE_PIVOT)
        state = NegotiationState.from_file(self.sprint / "negotiation_state.json")
        self.assertTrue(state.should_force_pivot())

    def test_replace_me_marker_rejects_turn(self) -> None:
        # Generator writes a contract that still has the seed marker.
        bad = VALID_NEGOTIATING.replace(
            "test_x", "__REPLACE_ME__"
        )
        gen = ScriptedAgent(Turn.GENERATOR, [bad, VALID_NEGOTIATING, VALID_AGREED])
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
            max_marker_retries=2,
        )
        result = loop.run()
        # Loop should retry the generator turn once (marker rejected), then succeed.
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        self.assertEqual(result.marker_rejections, 1)

    def test_invalid_contract_schema_rejects_turn(self) -> None:
        # Generator writes a contract with no test/trace items (pure-judge).
        pure_judge = """# X\n\n## Done means\n- [judge] looks good\n\n## Status: NEGOTIATING\n"""
        gen = ScriptedAgent(Turn.GENERATOR, [pure_judge, VALID_NEGOTIATING, VALID_AGREED])
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
            max_schema_retries=2,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        self.assertEqual(result.schema_rejections, 1)


if __name__ == "__main__":
    unittest.main()
