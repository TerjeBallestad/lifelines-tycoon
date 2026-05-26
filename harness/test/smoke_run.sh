#!/usr/bin/env bash
# End-to-end dry-run smoke for the Phase 6 run entrypoint.
set -euo pipefail

SRC_REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lifelines-smoke-run.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

cp -R "${SRC_REPO}/harness" "${WORKDIR}/harness"
cp -R "${SRC_REPO}/docs" "${WORKDIR}/docs"
cd "$WORKDIR"

find harness -name __pycache__ -type d -prune -exec rm -rf {} +
chmod +x harness/run.sh harness/test/smoke_run.sh harness/run_sprint.sh

if ! git init -q -b main >/dev/null 2>&1; then
  git init -q
  git checkout -q -b main
fi
git config user.email smoke@example.test
git config user.name "Smoke Test"
git add harness docs
git commit -q -m "base"
BASE_SHA="$(git rev-parse HEAD)"

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

run_orchestrator = importlib.import_module("run_orchestrator")
assert set(run_orchestrator.__all__) == {
    "OrchestratorConfig",
    "RunOrchestrator",
}

report_renderer = importlib.import_module("report_renderer")
assert set(report_renderer.__all__) == {"render_final_markdown", "render_report"}

planner_agent = importlib.import_module("planner_agent")
assert set(planner_agent.__all__) == {"PlannerError", "run_planner"}

fixtures = repo / "harness" / "test" / "fixtures"
for name in ("verdict_pass.json", "verdict_pivot.json", "verdict_reject.json"):
    data = json.loads((fixtures / name).read_text())
    assert data["verdict"] in {"PASS", "PIVOT", "REJECT"}, name
PY

cat > harness/run_sprint.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

RUN_ID=""
SPRINT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    --goal-file|--touch-surface) shift 2 ;;
    --dry-run) shift ;;
    *) shift ;;
  esac
done

if [[ -z "$RUN_ID" || -z "$SPRINT" ]]; then
  echo "smoke run_sprint stub: missing --run-id or --sprint" >&2
  exit 64
fi

SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"
mkdir -p "$SPRINT_DIR"
cat > "${SPRINT_DIR}/contract.md" <<'EOF'
# Contract

## Done means
- [test] smoke stub passes

## Status: AGREED
EOF
cat > "${SPRINT_DIR}/verdict.json" <<'EOF'
{
  "verdict": "PASS",
  "total": 84.0,
  "max_total": 84.0,
  "per_axis": {
    "decision-density": {
      "axis_score": 3.0,
      "weight": 5,
      "weighted": 15.0,
      "floor": 2,
      "below_floor": false
    }
  },
  "floor_violations": [],
  "test_pass": true,
  "trace_pass": true,
  "notes": ["smoke pass"]
}
EOF
cat > "${SPRINT_DIR}/critique.md" <<'EOF'
Smoke critique: deterministic PASS.
EOF
touch "${SPRINT_DIR}/ready"
SH
chmod +x harness/run_sprint.sh

grep -E '^## Sprint [0-9]+' harness/test/fixtures/sprint_list_valid.md | awk '{print $3}' | while read -r sprint; do
  git branch "harness/smoke-run/sprint_${sprint}" "$BASE_SHA"
done

./harness/run.sh --dry-run --planner-shim harness/test/fixtures/sprint_list_valid.md --run-id smoke-run --no-open "Make day-one decisions diverge."

test -f harness/runs/smoke-run/sprint_list.md
test -f harness/runs/smoke-run/run_state.json
test -f harness/runs/smoke-run/final.md
test -f harness/runs/smoke-run/report.html
grep -q "Day-one decision divergence" harness/runs/smoke-run/report.html
grep -q "PASS" harness/runs/smoke-run/report.html

echo "[smoke_run] OK"
