"""Concrete TurnAgent implementations backed by harness wrappers or local scripts.

Historically this module only exposed Claude-backed shell agents. Plan 5 now needs a
non-Anthropic path too: Phase A negotiation can run in a deterministic scripted
mode, or delegate each turn to caller-provided shell commands.
"""
from __future__ import annotations

import os
import shlex
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


@dataclass
class _CommandAgent:
    """TurnAgent that invokes a caller-provided shell command.

    The command receives context through environment variables instead of argv so
    callers can wrap Codex, OpenCode, a local script, or any other non-Claude
    runner without the harness knowing its CLI shape.
    """

    role: Turn
    command: str
    run_id: str
    sprint: int

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        env = os.environ.copy()
        env.update(
            {
                "HARNESS_AGENT_ROLE": self.role.value,
                "HARNESS_RUN_ID": self.run_id,
                "HARNESS_SPRINT": str(self.sprint),
                "HARNESS_ROUND": str(round_number),
                "HARNESS_SPRINT_DIR": str(sprint_dir),
                "HARNESS_CONTRACT": str(sprint_dir / "contract.md"),
                "HARNESS_GOAL": str(sprint_dir / "goal.md"),
                "HARNESS_TOUCH_SURFACE": str(sprint_dir / "touch_surface.allow"),
            }
        )
        subprocess.run(self.command, shell=True, check=True, cwd=Path.cwd(), env=env)


@dataclass
class _ScriptedAgreementAgent:
    """Deterministic Phase A agent for dry-runs and harness plumbing tests.

    This is intentionally dumb: it makes the seed contract concrete, sets it to
    AGREED, and then confirms unchanged. It is not a design brain. It is a wire
    tester that proves Plan 5 can move past Phase A without Claude.
    """

    role: Turn
    run_id: str
    sprint: int

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        contract_path = sprint_dir / "contract.md"
        text = contract_path.read_text()
        text = _make_seed_contract_concrete(text, sprint=self.sprint)
        if self.role == Turn.GENERATOR:
            text = _set_status(text, "AGREED")
            contract_path.write_text(text)
            return

        # Evaluator confirms unchanged when the generator already produced an
        # agreed concrete contract. If it somehow sees NEGOTIATING, agree without
        # changing acceptance criteria.
        if "## Status: AGREED" not in text:
            text = _set_status(text, "AGREED")
            contract_path.write_text(text)


def _make_seed_contract_concrete(text: str, *, sprint: int) -> str:
    return (
        text.replace(
            "[test] __REPLACE_ME__ replace with one concrete GUT test path + assertion in plain English",
            f"[test] `test/harness/test_sprint_{sprint}_contract.gd::test_contract_smoke` passes",
        )
        .replace(
            "[trace] events where __REPLACE_ME__=value count >= 1   # replace with a real trace-rule",
            "[trace] events where event=phase_a_agreed count >= 1",
        )
        .replace("Axis ?: primary — replace with the axis you intend to move", "Axis Decision Quality: primary")
        .replace("Axis ?: touched — replace with axes that must not regress", "Axis Scope Control: touched")
        .replace("__REPLACE_ME__", "concrete_phase_a_acceptance")
    )


def _set_status(text: str, status: str) -> str:
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("## Status:"):
            lines[i] = f"## Status: {status}"
            return "\n".join(lines) + "\n"
    return text.rstrip() + f"\n\n## Status: {status}\n"


def claude_generator_agent(*, run_id: str, sprint: int) -> _ShellAgent:
    # run_generator.sh from Plan 3 — invoked with --round for Phase A.
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


def scripted_generator_agent(*, run_id: str, sprint: int) -> _ScriptedAgreementAgent:
    return _ScriptedAgreementAgent(role=Turn.GENERATOR, run_id=run_id, sprint=sprint)


def scripted_evaluator_agent(*, run_id: str, sprint: int) -> _ScriptedAgreementAgent:
    return _ScriptedAgreementAgent(role=Turn.EVALUATOR, run_id=run_id, sprint=sprint)


def command_generator_agent(*, run_id: str, sprint: int) -> _CommandAgent:
    command = os.environ.get("GENERATOR_PHASE_A_CMD") or os.environ.get("NEGOTIATION_PHASE_A_CMD")
    if not command:
        raise RuntimeError(
            "NEGOTIATION_AGENT_MODE=command requires GENERATOR_PHASE_A_CMD "
            "or NEGOTIATION_PHASE_A_CMD"
        )
    return _CommandAgent(role=Turn.GENERATOR, command=command, run_id=run_id, sprint=sprint)


def command_evaluator_agent(*, run_id: str, sprint: int) -> _CommandAgent:
    command = os.environ.get("EVALUATOR_PHASE_A_CMD") or os.environ.get("NEGOTIATION_PHASE_A_CMD")
    if not command:
        raise RuntimeError(
            "NEGOTIATION_AGENT_MODE=command requires EVALUATOR_PHASE_A_CMD "
            "or NEGOTIATION_PHASE_A_CMD"
        )
    return _CommandAgent(role=Turn.EVALUATOR, command=command, run_id=run_id, sprint=sprint)


def negotiation_agents_from_env(*, run_id: str, sprint: int):
    """Return (generator, evaluator) for Plan 5 Phase A.

    NEGOTIATION_AGENT_MODE:
      - claude: existing Claude CLI wrappers
      - scripted: deterministic local contract agreement, no LLM
      - command: caller-provided shell command(s), no provider assumption

    If unset, live negotiation keeps the old Claude behavior; dry-run/non-live
    negotiation uses scripted mode so Phase A no longer degenerates into no-op
    force-pivots.
    """
    mode = os.environ.get("NEGOTIATION_AGENT_MODE", "").strip().lower()
    if not mode:
        mode = "claude" if os.environ.get("NEGOTIATION_LIVE", "0") == "1" else "scripted"

    if mode == "claude":
        return (
            claude_generator_agent(run_id=run_id, sprint=sprint),
            claude_evaluator_agent(run_id=run_id, sprint=sprint),
        )
    if mode == "scripted":
        return (
            scripted_generator_agent(run_id=run_id, sprint=sprint),
            scripted_evaluator_agent(run_id=run_id, sprint=sprint),
        )
    if mode == "command":
        return (
            command_generator_agent(run_id=run_id, sprint=sprint),
            command_evaluator_agent(run_id=run_id, sprint=sprint),
        )

    valid = ", ".join(shlex.quote(v) for v in ("claude", "scripted", "command"))
    raise RuntimeError(f"unknown NEGOTIATION_AGENT_MODE={mode!r}; expected one of: {valid}")
