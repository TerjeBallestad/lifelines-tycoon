"""Concrete TurnAgent implementations backed by harness bash wrappers."""
from __future__ import annotations
import subprocess
from dataclasses import dataclass
from pathlib import Path

from negotiation_state import Turn


@dataclass
class _ShellAgent:
    role: Turn
    script: str         # absolute path to the wrapper script
    run_id: str
    sprint: int

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        subprocess.run(
            [
                "bash",
                self.script,
                "--run-id", self.run_id,
                "--sprint", str(self.sprint),
                "--round", str(round_number),
            ],
            check=True,
            cwd=Path.cwd(),
        )


def claude_generator_agent(*, run_id: str, sprint: int) -> _ShellAgent:
    # run_generator.sh from Plan 3 — must be invoked with --negotiate-only to
    # produce a contract turn rather than a full implementation cycle. (Plan 3
    # already supports this when status == NEGOTIATING; we pass --round so the
    # script knows it is in Phase A.)
    return _ShellAgent(
        role=Turn.GENERATOR,
        script=str(Path("harness/run_generator.sh").resolve()),
        run_id=run_id,
        sprint=sprint,
    )


def claude_evaluator_agent(*, run_id: str, sprint: int) -> _ShellAgent:
    return _ShellAgent(
        role=Turn.EVALUATOR,
        script=str(Path("harness/run_evaluator_agent.sh").resolve()),
        run_id=run_id,
        sprint=sprint,
    )
