#!/usr/bin/env python3
"""Run state model for Phase 6 orchestration."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import json
import os
from pathlib import Path
from typing import Any


RUN_STATUSES = {"PLANNING", "RUNNING", "HALTED", "COMPLETE"}
SPRINT_STATUSES = {
    "PENDING",
    "RUNNING",
    "PASS",
    "PIVOT",
    "REJECT",
    "FORCE_PIVOT",
    "PASS_PENDING_MERGE",
    "SKIPPED",
}


class RunStateError(ValueError):
    """Raised when run state data or transitions are invalid."""


@dataclass
class SprintRunState:
    number: int
    title: str
    optional: bool
    attempt: int = 1
    status: str = "PENDING"
    branch: str | None = None
    worktree: str | None = None
    verdict: str | None = None
    notes: list[str] = field(default_factory=list)

    def __setattr__(self, name: str, value: Any) -> None:
        if name == "status":
            _validate_sprint_status(value)
        super().__setattr__(name, value)

    def __post_init__(self) -> None:
        _validate_sprint_status(self.status)
        self.notes = list(self.notes)


@dataclass
class RunState:
    run_id: str
    base_sha: str
    integration_branch: str
    status: str = "PLANNING"
    current_sprint: int | None = None
    sprints: list[SprintRunState] = field(default_factory=list)
    history: list[dict[str, Any]] = field(default_factory=list)

    def __setattr__(self, name: str, value: Any) -> None:
        if name == "status":
            _validate_run_status(value)
        super().__setattr__(name, value)

    def __post_init__(self) -> None:
        _validate_run_status(self.status)
        self.sprints = [
            sprint
            if isinstance(sprint, SprintRunState)
            else SprintRunState(**sprint)
            for sprint in self.sprints
        ]
        self.history = [dict(event) for event in self.history]

    @classmethod
    def new(cls, run_id: str, base_sha: str, integration_branch: str) -> "RunState":
        state = cls(
            run_id=run_id,
            base_sha=base_sha,
            integration_branch=integration_branch,
        )
        state.record("run_created")
        return state

    @classmethod
    def from_file(cls, path: Path) -> "RunState":
        data = json.loads(Path(path).read_text())
        return cls(**data)

    def to_file(self, path: Path) -> None:
        _validate_run_status(self.status)
        for sprint in self.sprints:
            _validate_sprint_status(sprint.status)
        target = Path(path)
        tmp = target.with_name(f".{target.name}.tmp")
        tmp.write_text(json.dumps(asdict(self), indent=2, sort_keys=True) + "\n")
        os.replace(tmp, target)

    def record(self, event: str, **payload: Any) -> None:
        entry = {**payload, "event": event, "ts": _utc_timestamp()}
        self.history.append(entry)

    def set_sprint_status(self, number: int, status: str, **payload: Any) -> None:
        _validate_sprint_status(status)
        sprint = self._sprint(number)
        sprint.status = status
        if status in {"PIVOT", "FORCE_PIVOT"}:
            sprint.attempt += 1
        _merge_sprint_payload(sprint, payload)

    def _sprint(self, number: int) -> SprintRunState:
        for sprint in self.sprints:
            if sprint.number == number:
                return sprint
        raise RunStateError(f"unknown sprint number: {number}")


def _validate_run_status(status: str) -> None:
    if status not in RUN_STATUSES:
        raise RunStateError(f"illegal run status: {status!r}")


def _validate_sprint_status(status: str) -> None:
    if status not in SPRINT_STATUSES:
        raise RunStateError(f"illegal sprint status: {status!r}")


def _merge_sprint_payload(sprint: SprintRunState, payload: dict[str, Any]) -> None:
    for field_name in ("branch", "worktree", "verdict"):
        if field_name in payload:
            setattr(sprint, field_name, payload[field_name])

    if "note" in payload and payload["note"] is not None:
        sprint.notes.append(str(payload["note"]))
    if "notes" in payload:
        notes = payload["notes"]
        if notes is None:
            return
        if isinstance(notes, str):
            sprint.notes.append(notes)
        else:
            sprint.notes.extend(str(note) for note in notes)


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


__all__ = [
    "RUN_STATUSES",
    "SPRINT_STATUSES",
    "RunState",
    "RunStateError",
    "SprintRunState",
]
