#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
import run_orchestrator  # noqa: E402
from planner_schema import SprintList, SprintSpec  # noqa: E402
from run_orchestrator import OrchestratorConfig, RunOrchestrator  # noqa: E402


class FakeRunner:
    def __init__(self, repo: Path, run_id: str, outcomes: list[dict[str, object]]):
        self.repo = repo
        self.run_id = run_id
        self.outcomes = list(outcomes)
        self.calls: list[list[str]] = []

    def __call__(
        self,
        command: list[str],
        *,
        cwd: Path,
        timeout: int,
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append(list(command))
        if not self.outcomes:
            raise AssertionError("fake runner exhausted")
        outcome = self.outcomes.pop(0)
        sprint = int(command[command.index("--sprint") + 1])
        sprint_dir = self.repo / "harness" / "runs" / self.run_id / f"sprint_{sprint}"
        sprint_dir.mkdir(parents=True, exist_ok=True)

        verdict = outcome.get("verdict")
        if verdict is not None:
            (sprint_dir / "verdict.json").write_text(
                json.dumps(
                    {
                        "verdict": verdict,
                        "total": 84.0 if verdict == "PASS" else 42.0,
                        "max_total": 84.0,
                        "notes": outcome.get("notes", []),
                    },
                    indent=2,
                )
                + "\n"
            )
        if "critique" in outcome:
            (sprint_dir / "critique.md").write_text(str(outcome["critique"]))
        if "contract" in outcome:
            (sprint_dir / "contract.md").write_text(str(outcome["contract"]))
        if "force_pivot" in outcome:
            (sprint_dir / "force_pivot.json").write_text(
                json.dumps(outcome["force_pivot"], indent=2) + "\n"
            )

        after = outcome.get("after")
        if after is not None:
            after()
        return subprocess.CompletedProcess(command, int(outcome.get("returncode", 0)))


class TestRunOrchestrator(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        (self.repo / "harness" / "runs").mkdir(parents=True)
        self.run_id = "run-1"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_pass_runs_sprint_integrates_commits_and_marks_pass(self) -> None:
        runner = FakeRunner(self.repo, self.run_id, [{"returncode": 0, "verdict": "PASS"}])
        orch = self._orchestrator(runner)

        with self._git_mocks() as git_mocks:
            state = orch.init_run("Make decisions diverge.\n", _plan([False]))
            state = orch.resume()

        self.assertEqual(state.status, "COMPLETE")
        self.assertEqual(state.sprints[0].status, "PASS")
        self.assertEqual(state.sprints[0].verdict, "PASS")
        self.assertEqual(len(runner.calls), 1)
        self.assertEqual(runner.calls[0][0:2], ["bash", "harness/run_sprint.sh"])
        self.assertIn("--dry-run", runner.calls[0])
        self.assertIn("--goal-file", runner.calls[0])
        self.assertIn("--touch-surface", runner.calls[0])
        self.assertEqual(runner.calls[0][runner.calls[0].index("--base-sha") + 1], "base-sha")
        self.assertIn("goal 1", (self.repo / "harness" / "runs" / self.run_id / "sprint_1" / "goal.md").read_text())
        self.assertEqual(
            (self.repo / "harness" / "runs" / self.run_id / "sprint_1" / "touch_surface.allow").read_text(),
            "features/one/\n",
        )
        git_mocks["current_sha"].assert_called_once_with(self.repo)
        git_mocks["ensure_integration_branch"].assert_called_once_with(
            self.repo,
            self.run_id,
            "base-sha",
        )
        git_mocks["collect_sprint_commits"].assert_called_once_with(
            self.repo,
            "base-sha",
            "harness/run-1/sprint_1",
        )
        git_mocks["cherry_pick_sprint"].assert_called_once_with(
            self.repo,
            "harness/run-1/integration",
            ["commit-1"],
        )

    def test_pivot_verdict_writes_context_and_halts_for_replan(self) -> None:
        runner = FakeRunner(
            self.repo,
            self.run_id,
            [
                {
                    "returncode": 0,
                    "verdict": "PIVOT",
                    "notes": ["needs narrower evidence"],
                    "critique": "Critique body\n",
                    "contract": "Contract body\n",
                },
                {"returncode": 0, "verdict": "PASS"},
            ],
        )
        orch = self._orchestrator(runner)

        with self._git_mocks():
            orch.init_run("Make decisions diverge.\n", _plan([False]))
            state = orch.resume()

        sprint_dir = self.repo / "harness" / "runs" / self.run_id / "sprint_1"
        context = (sprint_dir / "replan_context.md").read_text()
        self.assertEqual(len(runner.calls), 1)
        self.assertEqual(state.status, "HALTED")
        self.assertEqual(state.sprints[0].attempt, 2)
        self.assertEqual(state.sprints[0].status, "PIVOT")
        self.assertEqual(state.history[-1]["event"], "sprint_replan_required")
        self.assertIn("goal 1", context)
        self.assertIn("Critique body", context)
        self.assertIn("Contract body", context)

    def test_exit_code_two_marks_force_pivot_and_halts_for_replan(self) -> None:
        runner = FakeRunner(
            self.repo,
            self.run_id,
            [
                {
                    "returncode": 2,
                    "force_pivot": {"reason": "phase_a_max_rounds_exceeded"},
                    "contract": "Rejected contract\n",
                },
            ],
        )
        orch = self._orchestrator(runner)

        with self._git_mocks():
            orch.init_run("Make decisions diverge.\n", _plan([False]))
            state = orch.resume()

        context_path = (
            self.repo
            / "harness"
            / "runs"
            / self.run_id
            / "sprint_1"
            / "replan_context.md"
        )
        context = context_path.read_text()
        self.assertEqual(len(runner.calls), 1)
        self.assertEqual(state.status, "HALTED")
        self.assertEqual(state.sprints[0].status, "FORCE_PIVOT")
        self.assertEqual(state.sprints[0].attempt, 2)
        self.assertEqual(state.history[-1]["event"], "sprint_replan_required")
        self.assertIn("phase_a_max_rounds_exceeded", context)
        self.assertIn("Rejected contract", context)

    def test_reject_required_halts_run(self) -> None:
        runner = FakeRunner(self.repo, self.run_id, [{"returncode": 0, "verdict": "REJECT"}])
        orch = self._orchestrator(runner)

        with self._git_mocks():
            orch.init_run("Make decisions diverge.\n", _plan([False]))
            state = orch.resume()

        self.assertEqual(state.status, "HALTED")
        self.assertEqual(state.sprints[0].status, "REJECT")
        self.assertEqual(state.sprints[0].verdict, "REJECT")
        self.assertEqual(len(runner.calls), 1)

    def test_reject_optional_skips_and_continues_to_next_sprint(self) -> None:
        runner = FakeRunner(
            self.repo,
            self.run_id,
            [
                {"returncode": 0, "verdict": "REJECT"},
                {"returncode": 0, "verdict": "PASS"},
            ],
        )
        orch = self._orchestrator(runner)

        with self._git_mocks():
            orch.init_run("Make decisions diverge.\n", _plan([True, False]))
            state = orch.resume()

        self.assertEqual(state.status, "COMPLETE")
        self.assertEqual([sprint.status for sprint in state.sprints], ["SKIPPED", "PASS"])
        self.assertEqual(_called_sprints(runner.calls), [1, 2])

    def test_kill_file_stops_before_next_sprint(self) -> None:
        def create_kill() -> None:
            (self.repo / "harness" / ".kill").write_text("stop\n")

        runner = FakeRunner(
            self.repo,
            self.run_id,
            [{"returncode": 0, "verdict": "PASS", "after": create_kill}],
        )
        orch = self._orchestrator(runner)

        with self._git_mocks():
            orch.init_run("Make decisions diverge.\n", _plan([False, False]))
            state = orch.resume()

        self.assertEqual(state.status, "HALTED")
        self.assertEqual([sprint.status for sprint in state.sprints], ["PASS", "PENDING"])
        self.assertEqual(len(runner.calls), 1)
        self.assertEqual(state.history[-1]["event"], "kill_file_detected")
        self.assertEqual(state.history[-1]["sprint"], 2)

    def _orchestrator(self, runner: FakeRunner) -> RunOrchestrator:
        orch = RunOrchestrator(
            OrchestratorConfig(
                repo=self.repo,
                run_id=self.run_id,
                live=False,
            )
        )
        orch.runner = runner
        return orch

    def _git_mocks(self):
        patches = {
            "current_sha": mock.patch.object(
                run_orchestrator,
                "current_sha",
                autospec=True,
                return_value="base-sha",
            ),
            "ensure_integration_branch": mock.patch.object(
                run_orchestrator,
                "ensure_integration_branch",
                autospec=True,
                return_value="harness/run-1/integration",
            ),
            "collect_sprint_commits": mock.patch.object(
                run_orchestrator,
                "collect_sprint_commits",
                autospec=True,
                return_value=["commit-1"],
            ),
            "cherry_pick_sprint": mock.patch.object(
                run_orchestrator,
                "cherry_pick_sprint",
                autospec=True,
                return_value="OK",
            ),
        }
        return _PatchGroup(patches)


class _PatchGroup:
    def __init__(self, patches: dict[str, mock._patch]):
        self.patches = patches
        self.mocks: dict[str, mock.Mock] = {}

    def __enter__(self) -> dict[str, mock.Mock]:
        for name, patcher in self.patches.items():
            self.mocks[name] = patcher.__enter__()
        return self.mocks

    def __exit__(self, exc_type, exc, tb) -> bool:
        for patcher in reversed(list(self.patches.values())):
            patcher.__exit__(exc_type, exc, tb)
        return False


def _plan(optionals: list[bool]) -> SprintList:
    user_intent = [f"intent {index}" for index in range(1, len(optionals) + 1)]
    return SprintList(
        user_intent=user_intent,
        sprints=[
            SprintSpec(
                number=index,
                title=f"Sprint {index}",
                goal=f"goal {index}",
                user_intent_coverage=[user_intent[index - 1]],
                touch_surface=[f"features/{_number_name(index)}/"],
                rubric_focus=[f"axis {index}"],
                optional=optional,
            )
            for index, optional in enumerate(optionals, start=1)
        ],
    )


def _number_name(number: int) -> str:
    names = {
        1: "one",
        2: "two",
        3: "three",
    }
    return names.get(number, str(number))


def _called_sprints(calls: list[list[str]]) -> list[int]:
    return [int(command[command.index("--sprint") + 1]) for command in calls]


if __name__ == "__main__":
    unittest.main()
