#!/usr/bin/env bash
# smoke_run.sh - scaffold-level checks for the Phase 6 run entrypoint.
set -euo pipefail

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO"

test -x harness/run.sh || { echo "[smoke_run] harness/run.sh is not executable" >&2; exit 1; }
test -f harness/prompts/planner.md || { echo "[smoke_run] planner prompt missing" >&2; exit 1; }

python3 - <<'PY'
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "harness" / "lib"))

planner_schema = importlib.import_module("planner_schema")
assert set(planner_schema.__all__) == {
    "SprintList",
    "SprintListError",
    "SprintSpec",
    "parse_sprint_list",
    "validate_sprint_list",
}
valid_plan = planner_schema.parse_sprint_list((repo / "harness" / "test" / "fixtures" / "sprint_list_valid.md").read_text())
planner_schema.validate_sprint_list(valid_plan)
try:
    invalid_plan = planner_schema.parse_sprint_list((repo / "harness" / "test" / "fixtures" / "sprint_list_invalid_missing_touch.md").read_text())
    planner_schema.validate_sprint_list(invalid_plan)
except planner_schema.SprintListError:
    pass
else:
    raise AssertionError("invalid sprint-list fixture should fail validation")

run_state = importlib.import_module("run_state")
assert set(run_state.__all__) == {
    "RUN_STATUSES",
    "SPRINT_STATUSES",
    "RunState",
    "RunStateError",
    "SprintRunState",
}

git_integration = importlib.import_module("git_integration")
assert set(git_integration.__all__) == {
    "archive_sprint_branch",
    "cherry_pick_sprint",
    "collect_sprint_commits",
    "current_sha",
    "ensure_integration_branch",
    "git",
    "sprint_branch",
}

for module_name in (
    "run_orchestrator",
    "report_renderer",
):
    module = importlib.import_module(module_name)
    assert module.__all__ == [], module_name

planner_agent = importlib.import_module("planner_agent")
assert set(planner_agent.__all__) == {"PlannerError", "run_planner"}

fixtures = repo / "harness" / "test" / "fixtures"
for name in ("verdict_pass.json", "verdict_pivot.json", "verdict_reject.json"):
    data = json.loads((fixtures / name).read_text())
    assert data["verdict"] in {"PASS", "PIVOT", "REJECT"}, name
PY

./harness/run.sh --help >/dev/null

set +e
RUN_OUTPUT="$(./harness/run.sh "phase 6 smoke prompt" 2>&1)"
RUN_STATUS=$?
set -e

if [[ "$RUN_STATUS" -eq 0 ]]; then
  echo "[smoke_run] run.sh should not execute orchestration yet" >&2
  exit 1
fi

case "$RUN_OUTPUT" in
  *"Phase 6 scaffold only"*) ;;
  *)
    echo "[smoke_run] scaffold message missing" >&2
    exit 1
    ;;
esac

echo "[smoke_run] OK"
