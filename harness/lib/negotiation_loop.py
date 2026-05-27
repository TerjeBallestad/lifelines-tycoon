"""Negotiation loop — alternate generator + evaluator agents until terminal AGREED
or force-pivot. Each agent is an abstract TurnAgent that, when asked, writes a new
`contract.md` and returns.

The loop owns:
- mutex acquisition (contract_lock)
- contract parse + hash + status detection (contract_schema, contract_hash)
- state transitions (negotiation_state)
- seed-marker check (contract_template)
- retry budget for malformed turns

Concrete agent implementations (claude subprocesses) live in
harness/lib/claude_agents.py — wired by run_evaluator_agent.sh / run_generator.sh
at the call site. The loop is agnostic of how agents are produced.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Protocol

from audit_log import append_event, snapshot_contract_turn
from contract_hash import hash_contract_file
from contract_lock import contract_lock
from contract_schema import parse_contract, ContractSchemaError
from contract_template import SEED_MARKER
from negotiation_state import NegotiationState, NegotiationStateError, Turn


class NegotiationOutcome(str, Enum):
    AGREED = "agreed"
    FORCE_PIVOT = "force_pivot"


@dataclass(frozen=True)
class NegotiationResult:
    outcome: NegotiationOutcome
    rounds_used: int
    marker_rejections: int = 0
    schema_rejections: int = 0


class TurnAgent(Protocol):
    """An agent that, when invoked, edits contract.md and returns.

    Concrete implementations wrap `claude -p --resume` subprocesses. Production
    callers must ensure they hold no exclusive lock on contract.md when calling
    `take_turn` — the loop manages locking around the call.
    """

    role: Turn

    def take_turn(self, sprint_dir: Path, round_number: int) -> None: ...


@dataclass
class NegotiationLoop:
    sprint_dir: Path
    lock_path: Path
    generator: TurnAgent
    evaluator: TurnAgent
    max_marker_retries: int = 1
    max_schema_retries: int = 1
    _marker_rejections: int = field(default=0, init=False)
    _schema_rejections: int = field(default=0, init=False)

    def run(self) -> NegotiationResult:
        contract_path = self.sprint_dir / "contract.md"
        state_path = self.sprint_dir / "negotiation_state.json"

        while True:
            state = NegotiationState.from_file(state_path)
            if state.is_terminal_agreed():
                return NegotiationResult(
                    outcome=NegotiationOutcome.AGREED,
                    rounds_used=state.current_round(),
                    marker_rejections=self._marker_rejections,
                    schema_rejections=self._schema_rejections,
                )
            if state.should_force_pivot():
                return NegotiationResult(
                    outcome=NegotiationOutcome.FORCE_PIVOT,
                    rounds_used=state.current_round(),
                    marker_rejections=self._marker_rejections,
                    schema_rejections=self._schema_rejections,
                )

            actor = state.next_actor()
            agent = self.generator if actor == Turn.GENERATOR else self.evaluator
            if agent.role != actor:
                raise NegotiationStateError(
                    f"agent role mismatch: expected {actor.value}, got {agent.role.value}"
                )

            round_number = state.current_round() + 1
            before_hash = _contract_hash_or_none(contract_path)
            before_status = _contract_status_or_missing(contract_path)

            # The agent edits the contract in its own process. The loop releases
            # the lock while the agent runs (long-lived subprocess); the agent's
            # wrapper must take the lock itself for read+write where needed.
            agent.take_turn(self.sprint_dir, round_number=round_number)

            with contract_lock(str(self.lock_path), timeout=10.0):
                if not contract_path.exists():
                    raise NegotiationStateError(
                        f"agent {actor.value} did not write contract.md"
                    )
                raw = contract_path.read_text()
                snapshot_path = snapshot_contract_turn(
                    self.sprint_dir,
                    round_number=round_number,
                    actor=actor.value,
                    contract_text=raw,
                )
                if SEED_MARKER in raw and self._marker_rejections < self.max_marker_retries:
                    self._marker_rejections += 1
                    append_event(
                        self.sprint_dir.parent,
                        "negotiation_turn_rejected_marker",
                        sprint=_sprint_number(self.sprint_dir),
                        round=round_number,
                        agent=actor.value,
                        snapshot=str(snapshot_path),
                    )
                    # Do NOT record the turn; force the same actor to retry.
                    continue
                try:
                    contract = parse_contract(raw)
                except ContractSchemaError:
                    if self._schema_rejections < self.max_schema_retries:
                        self._schema_rejections += 1
                        append_event(
                            self.sprint_dir.parent,
                            "negotiation_turn_rejected_schema",
                            sprint=_sprint_number(self.sprint_dir),
                            round=round_number,
                            agent=actor.value,
                            snapshot=str(snapshot_path),
                        )
                        continue
                    raise
                contract_hash = hash_contract_file(contract_path)

            append_event(
                self.sprint_dir.parent,
                "negotiation_turn",
                sprint=_sprint_number(self.sprint_dir),
                round=round_number,
                agent=actor.value,
                status_before=before_status,
                status_after=contract.status,
                contract_changed=before_hash != contract_hash,
                snapshot=str(snapshot_path),
            )

            state = state.record_turn(
                actor=actor,
                status=contract.status,
                contract_hash=contract_hash,
            )
            state.to_file(state_path)


def _contract_status_or_missing(contract_path: Path) -> str:
    if not contract_path.exists():
        return "missing"
    try:
        return parse_contract(contract_path.read_text()).status
    except ContractSchemaError:
        return "invalid"


def _contract_hash_or_none(contract_path: Path) -> str | None:
    if not contract_path.exists():
        return None
    try:
        return hash_contract_file(contract_path)
    except ContractSchemaError:
        return None


def _sprint_number(sprint_dir: Path) -> int | str:
    raw = sprint_dir.name.removeprefix("sprint_")
    try:
        return int(raw)
    except ValueError:
        return raw
