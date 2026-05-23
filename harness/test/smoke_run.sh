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

for module_name in (
    "planner_schema",
    "planner_agent",
    "run_state",
    "run_orchestrator",
    "git_integration",
    "report_renderer",
):
    module = importlib.import_module(module_name)
    assert module.__all__ == [], module_name

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
