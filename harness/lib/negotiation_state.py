"""Negotiation state model — turn alternation, round counting, terminal AGREED detection.

The state object is immutable; every transition returns a new state. The orchestrator
serializes the state to JSON after every turn so it can be inspected or resumed.

Terminal AGREED rule (spec §4.5 step 5): both sides must write '## Status: AGREED'
consecutively, AND the contract hash must be unchanged across the final confirming
turn (the confirming actor MUST NOT edit the contract; if they edit, it counts as a
new draft and the other side must see + confirm again).
"""
from __future__ import annotations
import json
from dataclasses import dataclass, asdict, replace
from enum import Enum
from pathlib import Path


class Turn(str, Enum):
    GENERATOR = "generator"
    EVALUATOR = "evaluator"


class NegotiationStateError(RuntimeError):
    """Raised on illegal turn transitions."""


@dataclass(frozen=True)
class TurnRecord:
    actor: Turn
    status: str          # "NEGOTIATING" | "AGREED"
    contract_hash: str   # opaque hash; see contract_hash.py


@dataclass(frozen=True)
class NegotiationState:
    run_id: str
    sprint: int
    max_rounds: int
    turns: tuple[TurnRecord, ...]

    @classmethod
    def new(cls, *, run_id: str, sprint: int, max_rounds: int = 5) -> "NegotiationState":
        if max_rounds < 2:
            raise NegotiationStateError("max_rounds must be >= 2 (at least one G+E pair)")
        return cls(run_id=run_id, sprint=sprint, max_rounds=max_rounds, turns=())

    def current_round(self) -> int:
        return len(self.turns)

    def next_actor(self) -> Turn:
        if not self.turns:
            return Turn.GENERATOR
        last = self.turns[-1].actor
        return Turn.EVALUATOR if last == Turn.GENERATOR else Turn.GENERATOR

    def should_force_pivot(self) -> bool:
        return self.current_round() >= self.max_rounds and not self.is_terminal_agreed()

    def is_terminal_agreed(self) -> bool:
        # Need at least two turns, both with status=AGREED, distinct actors,
        # AND the confirming (last) turn must NOT have changed the hash.
        if len(self.turns) < 2:
            return False
        a, b = self.turns[-2], self.turns[-1]
        return (
            a.status == "AGREED"
            and b.status == "AGREED"
            and a.actor != b.actor
            and a.contract_hash == b.contract_hash
        )

    def record_turn(self, *, actor: Turn, status: str, contract_hash: str) -> "NegotiationState":
        if status not in ("AGREED", "NEGOTIATING"):
            raise NegotiationStateError(f"status must be AGREED|NEGOTIATING, got {status!r}")
        if self.should_force_pivot():
            raise NegotiationStateError(
                f"force-pivot already triggered at round {self.current_round()}; refusing further turns"
            )
        expected = self.next_actor()
        if actor != expected:
            raise NegotiationStateError(
                f"out-of-turn write: expected {expected.value}, got {actor.value}"
            )
        record = TurnRecord(actor=actor, status=status, contract_hash=contract_hash)
        return replace(self, turns=self.turns + (record,))

    def audit_log(self) -> dict:
        terminal = "AGREED" if self.is_terminal_agreed() else (
            "FORCE_PIVOT" if self.should_force_pivot() else "IN_PROGRESS"
        )
        return {
            "run_id": self.run_id,
            "sprint": self.sprint,
            "max_rounds": self.max_rounds,
            "rounds_used": self.current_round(),
            "terminal_status": terminal,
            "turns": [
                {"round": i + 1, "actor": t.actor.value, "status": t.status, "contract_hash": t.contract_hash}
                for i, t in enumerate(self.turns)
            ],
        }

    def to_file(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.audit_log(), indent=2) + "\n")

    @classmethod
    def from_file(cls, path: str | Path) -> "NegotiationState":
        data = json.loads(Path(path).read_text())
        state = cls.new(run_id=data["run_id"], sprint=data["sprint"], max_rounds=data["max_rounds"])
        for t in data["turns"]:
            state = state.record_turn(
                actor=Turn(t["actor"]),
                status=t["status"],
                contract_hash=t["contract_hash"],
            )
        return state
