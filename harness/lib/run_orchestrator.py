#!/usr/bin/env python3
"""Sequential run-level orchestration for Phase 6."""
from __future__ import annotations

from dataclasses import dataclass
import json
import subprocess
from pathlib import Path
from typing import Sequence

from git_integration import (
    cherry_pick_sprint,
    collect_sprint_commits,
    current_sha,
    ensure_integration_branch,
    sprint_branch,
)
from planner_schema import SprintList, SprintSpec, validate_sprint_list
from run_state import RunState, SprintRunState


@dataclass
class OrchestratorConfig:
    repo: Path
    run_id: str
    live: bool
    max_pivots_per_sprint: int = 1
    sprint_timeout_seconds: int = 7200


class OrchestratorError(RuntimeError):
    """Raised when orchestration cannot continue safely."""


class RunOrchestrator:
    def __init__(self, config: OrchestratorConfig):
        self.config = config
        self.repo = Path(config.repo)
        self.run_dir = self.repo / "harness" / "runs" / config.run_id
        self.state_path = self.run_dir / "run_state.json"
        self.runner = _default_runner

    def init_run(self, prompt_text: str, sprint_list: SprintList) -> RunState:
        validate_sprint_list(sprint_list)
        self.run_dir.mkdir(parents=True, exist_ok=True)
        (self.run_dir / "prompt.txt").write_text(prompt_text)
        (self.run_dir / "sprint_list.md").write_text(_render_sprint_list(sprint_list))

        base_sha = current_sha(self.repo)
        integration_branch = ensure_integration_branch(
            self.repo,
            self.config.run_id,
            base_sha,
        )
        state = RunState.new(self.config.run_id, base_sha, integration_branch)
        state.sprints = [
            SprintRunState(
                number=sprint.number,
                title=sprint.title,
                optional=sprint.optional,
                branch=sprint_branch(self.config.run_id, sprint.number),
            )
            for sprint in sprint_list.sprints
        ]

        for sprint in sprint_list.sprints:
            self._materialize_sprint(sprint)

        state.to_file(self.state_path)
        return state

    def resume(self) -> RunState:
        state = RunState.from_file(self.state_path)
        if state.status in {"HALTED", "COMPLETE"}:
            return state

        state.status = "RUNNING"
        self._save(state)

        while True:
            sprint = self._next_runnable_sprint(state)
            if sprint is None:
                state.current_sprint = None
                state.status = "COMPLETE"
                state.record("run_complete")
                self._save(state)
                return state

            if self._kill_requested():
                state.current_sprint = sprint.number
                state.status = "HALTED"
                state.record(
                    "kill_file_detected",
                    sprint=sprint.number,
                    path=str(self.repo / "harness" / ".kill"),
                )
                self._save(state)
                return state

            state.current_sprint = sprint.number
            state.set_sprint_status(sprint.number, "RUNNING")
            state.record("sprint_started", sprint=sprint.number, attempt=sprint.attempt)
            self._save(state)

            try:
                result = self.runner(
                    self._sprint_command(sprint.number, state.base_sha),
                    cwd=self.repo,
                    timeout=self.config.sprint_timeout_seconds,
                )
            except subprocess.TimeoutExpired:
                self._pivot_or_exhaust(
                    state,
                    sprint.number,
                    "PIVOT",
                    note="sprint_timeout",
                )
                return state

            if result.returncode == 0:
                action = self._handle_verdict(state, sprint.number)
                if action == "continue":
                    continue
                return state
            if result.returncode == 2:
                self._pivot_or_exhaust(
                    state,
                    sprint.number,
                    "FORCE_PIVOT",
                    note="force_pivot",
                )
                return state
            if result.returncode == 3:
                self._pivot_or_exhaust(
                    state,
                    sprint.number,
                    "PIVOT",
                    note="generator_failed",
                )
                return state
            if result.returncode == 4:
                state.status = "HALTED"
                state.set_sprint_status(
                    sprint.number,
                    "RUNNING",
                    note="evaluator_infra_failed",
                )
                state.record("evaluator_infra_failed", sprint=sprint.number)
                self._save(state)
                return state

            state.status = "HALTED"
            state.set_sprint_status(
                sprint.number,
                "RUNNING",
                note=f"run_sprint_exit_{result.returncode}",
            )
            state.record(
                "run_sprint_unexpected_exit",
                sprint=sprint.number,
                returncode=result.returncode,
            )
            self._save(state)
            return state

    def replay_grade(self, sprint: int) -> None:
        command = [
            "bash",
            "harness/run_evaluator.sh",
            "--run-id",
            self.config.run_id,
            "--sprint",
            str(sprint),
        ]
        if not self.config.live:
            command.append("--dry-run")
        result = self.runner(
            command,
            cwd=self.repo,
            timeout=self.config.sprint_timeout_seconds,
        )
        if result.returncode != 0:
            raise OrchestratorError(
                f"replay grade for sprint {sprint} exited {result.returncode}"
            )

    def _materialize_sprint(self, sprint: SprintSpec) -> None:
        sprint_dir = self._sprint_dir(sprint.number)
        sprint_dir.mkdir(parents=True, exist_ok=True)
        (sprint_dir / "goal.md").write_text(_render_goal(sprint))
        (sprint_dir / "touch_surface.allow").write_text(
            "\n".join(sprint.touch_surface) + "\n"
        )

    def _sprint_command(self, sprint_number: int, base_sha: str) -> list[str]:
        sprint_dir = self._sprint_dir(sprint_number)
        command = [
            "bash",
            "harness/run_sprint.sh",
            "--run-id",
            self.config.run_id,
            "--sprint",
            str(sprint_number),
            "--goal-file",
            str(sprint_dir / "goal.md"),
            "--touch-surface",
            str(sprint_dir / "touch_surface.allow"),
            "--base-sha",
            base_sha,
        ]
        if not self.config.live:
            command.append("--dry-run")
        return command

    def _handle_verdict(self, state: RunState, sprint_number: int) -> str:
        verdict_data = self._read_verdict(sprint_number)
        verdict = verdict_data["verdict"]
        notes = verdict_data.get("notes", [])

        if verdict == "PASS":
            self._integrate_pass(state, sprint_number, notes)
            if state.status == "HALTED":
                return "stop"
            return "continue"
        if verdict == "PIVOT":
            self._pivot_or_exhaust(
                state,
                sprint_number,
                "PIVOT",
                notes=notes,
            )
            return "stop"
        if verdict == "REJECT":
            self._handle_reject(state, sprint_number, notes)
            if state.status == "HALTED":
                return "stop"
            return "continue"

        raise OrchestratorError(
            f"sprint {sprint_number}: unexpected verdict {verdict!r}"
        )

    def _integrate_pass(
        self,
        state: RunState,
        sprint_number: int,
        notes: object,
    ) -> None:
        sprint = state._sprint(sprint_number)
        branch = sprint.branch or sprint_branch(self.config.run_id, sprint_number)
        commits = collect_sprint_commits(self.repo, state.base_sha, branch)
        result = cherry_pick_sprint(self.repo, state.integration_branch, commits)
        if result == "CONFLICT":
            state.status = "HALTED"
            state.set_sprint_status(
                sprint_number,
                "PASS_PENDING_MERGE",
                verdict="PASS",
                notes=notes,
                note="cherry_pick_conflict",
            )
            state.record(
                "sprint_pass_pending_merge",
                sprint=sprint_number,
                branch=branch,
                commits=commits,
            )
            self._save(state)
            return

        state.set_sprint_status(
            sprint_number,
            "PASS",
            verdict="PASS",
            branch=branch,
            notes=notes,
            note=f"integration_{result.lower()}",
        )
        state.record(
            "sprint_passed",
            sprint=sprint_number,
            branch=branch,
            commits=commits,
            integration_result=result,
        )
        self._save(state)

    def _pivot_or_exhaust(
        self,
        state: RunState,
        sprint_number: int,
        status: str,
        *,
        note: str | None = None,
        notes: object = None,
    ) -> bool:
        sprint = state._sprint(sprint_number)
        if not self._pivot_available(sprint):
            exhausted_note = "pivot_budget_exhausted"
            if note:
                exhausted_note = f"{exhausted_note}: {note}"
            if sprint.optional:
                state.set_sprint_status(
                    sprint_number,
                    "SKIPPED",
                    verdict=status,
                    notes=notes,
                    note=exhausted_note,
                )
                state.record("optional_sprint_skipped", sprint=sprint_number)
                self._save(state)
                return True

            state.status = "HALTED"
            state.set_sprint_status(
                sprint_number,
                "REJECT",
                verdict=status,
                notes=notes,
                note=exhausted_note,
            )
            state.record("required_sprint_rejected", sprint=sprint_number)
            self._save(state)
            return False

        self._write_replan_context(state, sprint_number, status.lower())
        state.status = "HALTED"
        state.set_sprint_status(
            sprint_number,
            status,
            verdict=status,
            notes=notes,
            note=note,
        )
        context_path = self._sprint_dir(sprint_number) / "replan_context.md"
        state.record(
            "sprint_replan_required",
            sprint=sprint_number,
            status=status,
            next_attempt=state._sprint(sprint_number).attempt,
            path=str(context_path),
        )
        self._save(state)
        return False

    def _handle_reject(
        self,
        state: RunState,
        sprint_number: int,
        notes: object,
    ) -> None:
        sprint = state._sprint(sprint_number)
        if sprint.optional:
            state.set_sprint_status(
                sprint_number,
                "SKIPPED",
                verdict="REJECT",
                notes=notes,
            )
            state.record("optional_sprint_rejected", sprint=sprint_number)
            self._save(state)
            return

        state.status = "HALTED"
        state.set_sprint_status(
            sprint_number,
            "REJECT",
            verdict="REJECT",
            notes=notes,
        )
        state.record("required_sprint_rejected", sprint=sprint_number)
        self._save(state)

    def _read_verdict(self, sprint_number: int) -> dict[str, object]:
        verdict_path = self._sprint_dir(sprint_number) / "verdict.json"
        try:
            data = json.loads(verdict_path.read_text())
        except OSError as exc:
            raise OrchestratorError(
                f"sprint {sprint_number}: could not read verdict.json: {exc}"
            ) from exc
        except json.JSONDecodeError as exc:
            raise OrchestratorError(
                f"sprint {sprint_number}: invalid verdict.json: {exc}"
            ) from exc

        verdict = data.get("verdict")
        if verdict not in {"PASS", "PIVOT", "REJECT"}:
            raise OrchestratorError(
                f"sprint {sprint_number}: unexpected verdict {verdict!r}"
            )
        return data

    def _write_replan_context(
        self,
        state: RunState,
        sprint_number: int,
        reason: str,
    ) -> None:
        sprint_dir = self._sprint_dir(sprint_number)
        parts = [
            f"# Replan context for sprint {sprint_number}",
            "",
            f"Reason: {reason}",
            "",
            "## Original sprint goal",
            _read_optional(sprint_dir / "goal.md") or "(missing goal.md)",
        ]
        for filename, heading in (
            ("critique.md", "Critique"),
            ("force_pivot.json", "Force pivot"),
            ("agreement.json", "Agreement"),
            ("contract.md", "Current contract"),
        ):
            text = _read_optional(sprint_dir / filename)
            if text:
                parts.extend(["", f"## {heading}", text])

        parts.extend(
            [
                "",
                "## Instruction",
                (
                    "Narrow the same sprint. Do not expand touch surface unless "
                    "the critique proves the original surface was wrong."
                ),
            ]
        )
        (sprint_dir / "replan_context.md").write_text("\n".join(parts).rstrip() + "\n")
        state.record(
            "replan_context_written",
            sprint=sprint_number,
            reason=reason,
            path=str(sprint_dir / "replan_context.md"),
        )

    def _next_runnable_sprint(self, state: RunState) -> SprintRunState | None:
        for sprint in state.sprints:
            if sprint.status in {"PENDING", "RUNNING"}:
                return sprint
        return None

    def _pivot_available(self, sprint: SprintRunState) -> bool:
        pivots_used = sprint.attempt - 1
        return pivots_used < self.config.max_pivots_per_sprint

    def _kill_requested(self) -> bool:
        return (self.repo / "harness" / ".kill").exists()

    def _sprint_dir(self, sprint_number: int) -> Path:
        return self.run_dir / f"sprint_{sprint_number}"

    def _save(self, state: RunState) -> None:
        state.to_file(self.state_path)


def _default_runner(
    command: Sequence[str],
    *,
    cwd: Path,
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, timeout=timeout)


def _render_goal(sprint: SprintSpec) -> str:
    return "\n".join(
        [
            f"# Sprint {sprint.number} \u2014 {sprint.title}",
            "",
            "## Goal",
            sprint.goal,
            "",
            "## User-intent coverage",
            *_bullet_lines(sprint.user_intent_coverage),
            "",
            "## Rubric focus",
            *_bullet_lines(sprint.rubric_focus),
            "",
        ]
    )


def _render_sprint_list(sprint_list: SprintList) -> str:
    parts = ["# Sprint List", "", "## User intent", *_bullet_lines(sprint_list.user_intent)]
    for sprint in sprint_list.sprints:
        parts.extend(
            [
                "",
                f"## Sprint {sprint.number} \u2014 {sprint.title}",
                "",
                "### Goal",
                sprint.goal,
                "",
                "### User-intent coverage",
                *_bullet_lines(sprint.user_intent_coverage),
                "",
                "### Touch surface",
                *_bullet_lines(sprint.touch_surface),
                "",
                "### Rubric focus",
                *_bullet_lines(sprint.rubric_focus),
                "",
                "### Optional",
                "true" if sprint.optional else "false",
            ]
        )
    return "\n".join(parts).rstrip() + "\n"


def _bullet_lines(items: list[str]) -> list[str]:
    return [f"- {item}" for item in items]


def _read_optional(path: Path) -> str | None:
    try:
        text = path.read_text().strip()
    except OSError:
        return None
    return text or None


__all__ = [
    "OrchestratorConfig",
    "RunOrchestrator",
]
