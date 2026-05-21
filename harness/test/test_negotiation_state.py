#!/usr/bin/env python3
"""Tests for harness/lib/negotiation_state.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from negotiation_state import (  # noqa: E402
    NegotiationState,
    TurnRecord,
    NegotiationStateError,
    Turn,
)


class TestInit(unittest.TestCase):
    def test_initial_state_has_no_turns(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1, max_rounds=5)
        self.assertEqual(s.run_id, "r1")
        self.assertEqual(s.sprint, 1)
        self.assertEqual(s.max_rounds, 5)
        self.assertEqual(s.turns, ())
        self.assertEqual(s.current_round(), 0)
        self.assertEqual(s.next_actor(), Turn.GENERATOR)

    def test_first_turn_must_be_generator(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        with self.assertRaises(NegotiationStateError):
            s.record_turn(actor=Turn.EVALUATOR, status="NEGOTIATING", contract_hash="x")


class TestRecordTurn(unittest.TestCase):
    def _seed_generator_draft(self) -> NegotiationState:
        s = NegotiationState.new(run_id="r1", sprint=1)
        return s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")

    def test_round_increments(self) -> None:
        s = self._seed_generator_draft()
        self.assertEqual(s.current_round(), 1)
        self.assertEqual(s.next_actor(), Turn.EVALUATOR)
        s2 = s.record_turn(actor=Turn.EVALUATOR, status="NEGOTIATING", contract_hash="h2")
        self.assertEqual(s2.current_round(), 2)
        self.assertEqual(s2.next_actor(), Turn.GENERATOR)

    def test_actor_must_alternate(self) -> None:
        s = self._seed_generator_draft()
        with self.assertRaises(NegotiationStateError):
            s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h2")


class TestTerminalAgreed(unittest.TestCase):
    def test_terminal_requires_two_consecutive_agreed_distinct_actors(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        # Not terminal yet — generator hasn't confirmed.
        self.assertFalse(s.is_terminal_agreed())
        # Generator confirms by leaving the contract alone and writing AGREED.
        s = s.record_turn(actor=Turn.GENERATOR, status="AGREED", contract_hash="h2")
        self.assertTrue(s.is_terminal_agreed())

    def test_agreed_after_edit_is_not_terminal(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        # Generator wrote AGREED but ALSO edited the contract (hash changed)
        # → evaluator must see and confirm before terminal.
        s = s.record_turn(actor=Turn.GENERATOR, status="AGREED", contract_hash="h3")
        self.assertFalse(s.is_terminal_agreed())


class TestForcePivot(unittest.TestCase):
    def test_pivot_at_max_rounds(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1, max_rounds=4)
        for _ in range(4):
            actor = s.next_actor()
            s = s.record_turn(actor=actor, status="NEGOTIATING", contract_hash="h")
        # Round 4 done. Recording a 5th turn must raise force_pivot.
        self.assertTrue(s.should_force_pivot())

    def test_pivot_blocks_further_turns(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1, max_rounds=2)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="NEGOTIATING", contract_hash="h2")
        self.assertTrue(s.should_force_pivot())
        with self.assertRaises(NegotiationStateError):
            s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h3")


class TestPersistence(unittest.TestCase):
    def test_round_trip_disk(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as fh:
            path = fh.name
        s.to_file(path)
        s2 = NegotiationState.from_file(path)
        self.assertEqual(s.run_id, s2.run_id)
        self.assertEqual(s.sprint, s2.sprint)
        self.assertEqual(s.current_round(), s2.current_round())
        self.assertEqual(len(s.turns), len(s2.turns))
        self.assertEqual(s.turns[-1].contract_hash, s2.turns[-1].contract_hash)


class TestAgreementAuditLog(unittest.TestCase):
    def test_audit_log_emits_each_turn(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        s = s.record_turn(actor=Turn.GENERATOR, status="AGREED", contract_hash="h2")
        audit = s.audit_log()
        self.assertEqual(audit["run_id"], "r1")
        self.assertEqual(audit["sprint"], 1)
        self.assertEqual(audit["terminal_status"], "AGREED")
        self.assertEqual(len(audit["turns"]), 3)
        self.assertEqual(audit["turns"][0]["actor"], "generator")
        self.assertEqual(audit["turns"][-1]["actor"], "generator")


if __name__ == "__main__":
    unittest.main()
