#!/usr/bin/env bash
# run_sprint.sh — full single-sprint orchestrator (Plan 5).
#
# Phases:
#   0. Init sprint dir + seed contract via init_negotiation.sh.
#   A. Negotiation loop (Phase A): alternate generator + evaluator until AGREED or force-pivot.
#   B. Implementation: invoke Plan 3's run_generator.sh on the AGREED contract.
#   C. Grading (Phase B): invoke run_evaluator_phase_b.sh (which wraps Plan 4).
#
# Exit codes:
#   0 — sprint passed Phase B with verdict ∈ {PASS, PIVOT}
#   2 — Phase A force-pivot (no Phase B run)
#   3 — Plan 3 implementation failed
#   4 — Plan 4 grading failed
#
# Usage:
#   run_sprint.sh --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path>
#                 [--max-rounds N] [--base-sha <sha>] [--skip-eval-phase-b] [--dry-run]
set -euo pipefail

RUN_ID=""
SPRINT=""
GOAL_FILE=""
TOUCH_FILE=""
MAX_ROUNDS=5
SKIP_PHASE_B=0
DRY_RUN=0
BASE_SHA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)            RUN_ID="$2"; shift 2 ;;
    --sprint)            SPRINT="$2"; shift 2 ;;
    --goal-file)         GOAL_FILE="$2"; shift 2 ;;
    --touch-surface)     TOUCH_FILE="$2"; shift 2 ;;
    --max-rounds)        MAX_ROUNDS="$2"; shift 2 ;;
    --base-sha)          BASE_SHA="$2"; shift 2 ;;
    --skip-eval-phase-b) SKIP_PHASE_B=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)           grep '^# ' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$RUN_ID" && -n "$SPRINT" && -n "$GOAL_FILE" && -n "$TOUCH_FILE" ]] || \
  { echo "missing required arg; see --help" >&2; exit 64; }

if [[ "$DRY_RUN" -eq 1 ]]; then
  export EVALUATOR_LIVE=0
  export NEGOTIATION_LIVE=0
  export GENERATOR_LIVE=0
fi
# Live mode must be consistent.
: "${EVALUATOR_LIVE:=0}"
: "${NEGOTIATION_LIVE:=$EVALUATOR_LIVE}"
: "${GENERATOR_LIVE:=$EVALUATOR_LIVE}"
if [[ "$EVALUATOR_LIVE" != "$NEGOTIATION_LIVE" || "$EVALUATOR_LIVE" != "$GENERATOR_LIVE" ]]; then
  echo "EVALUATOR_LIVE/NEGOTIATION_LIVE/GENERATOR_LIVE must all match; got $EVALUATOR_LIVE/$NEGOTIATION_LIVE/$GENERATOR_LIVE" >&2
  exit 64
fi
export EVALUATOR_LIVE NEGOTIATION_LIVE GENERATOR_LIVE

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"

echo "[run_sprint] phase 0 — init"
bash "$LIB_DIR/init_negotiation.sh" \
  --run-id "$RUN_ID" \
  --sprint "$SPRINT" \
  --goal-file "$GOAL_FILE" \
  --touch-surface "$TOUCH_FILE" \
  --max-rounds "$MAX_ROUNDS"

echo "[run_sprint] phase A — negotiation"
python3 - "$RUN_ID" "$SPRINT" "$LIB_DIR" <<'PY'
import sys, subprocess
from pathlib import Path
run_id, sprint, lib_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sys.path.insert(0, lib_dir)
from audit_log import append_event, render_audit_markdown
from negotiation_loop import NegotiationLoop, NegotiationOutcome
from claude_agents import negotiation_agents_from_env

sprint_dir = Path(f"harness/runs/{run_id}/sprint_{sprint}")
run_dir = sprint_dir.parent
lock_path = Path(f"harness/.locks/contract_{run_id}_{sprint}.lock")
generator, evaluator = negotiation_agents_from_env(run_id=run_id, sprint=sprint)
append_event(run_dir, "phase_a_started", sprint=sprint)

loop = NegotiationLoop(
    sprint_dir=sprint_dir,
    lock_path=lock_path,
    generator=generator,
    evaluator=evaluator,
)
result = loop.run()

audit_path = sprint_dir / "agreement.json"
import json
from negotiation_state import NegotiationState
state = NegotiationState.from_file(sprint_dir / "negotiation_state.json")
audit = state.audit_log()
audit["rejections"] = {"marker": result.marker_rejections, "schema": result.schema_rejections}
audit_path.write_text(json.dumps(audit, indent=2) + "\n")

if result.outcome == NegotiationOutcome.FORCE_PIVOT:
    pivot = sprint_dir / "force_pivot.json"
    pivot.write_text(json.dumps({
        "run_id": run_id, "sprint": sprint, "rounds_used": result.rounds_used,
        "reason": "phase_a_max_rounds_exceeded",
    }, indent=2) + "\n")
    append_event(run_dir, "phase_a_force_pivot", sprint=sprint, rounds_used=result.rounds_used, path=str(pivot))
    render_audit_markdown(run_dir)
    print(f"[run_sprint] force-pivot after {result.rounds_used} rounds; see {pivot}", file=sys.stderr)
    sys.exit(2)

append_event(run_dir, "phase_a_agreed", sprint=sprint, rounds_used=result.rounds_used, path=str(audit_path))
render_audit_markdown(run_dir)
print(f"[run_sprint] agreed after {result.rounds_used} rounds")
PY
PHASE_A=$?
if [[ "$PHASE_A" -ne 0 ]]; then exit "$PHASE_A"; fi

echo "[run_sprint] phase B-impl — generator implements against AGREED contract"
GENERATOR_LIVE="$EVALUATOR_LIVE" ./harness/run_generator.sh \
  --run-id "$RUN_ID" \
  --sprint "$SPRINT" \
  --goal-file "$SPRINT_DIR/goal.md" \
  --touch-surface "$SPRINT_DIR/touch_surface.allow" \
  --base-sha "$BASE_SHA" \
  || { echo "[run_sprint] generator implementation failed" >&2; exit 3; }
python3 - "$RUN_ID" "$SPRINT" "$LIB_DIR" <<'PY'
import sys
from pathlib import Path
run_id, sprint, lib_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sys.path.insert(0, lib_dir)
from audit_log import append_event, render_audit_markdown
run_dir = Path(f"harness/runs/{run_id}")
append_event(run_dir, "implementation_phase_completed", sprint=sprint)
render_audit_markdown(run_dir)
PY

if [[ "$SKIP_PHASE_B" -eq 1 ]]; then
  echo "[run_sprint] --skip-eval-phase-b set; stopping before grading"
  exit 0
fi

echo "[run_sprint] phase B-grade — evaluator grades implementation"
bash "$LIB_DIR/run_evaluator_phase_b.sh" --run-id "$RUN_ID" --sprint "$SPRINT" \
  || { echo "[run_sprint] grading failed" >&2; exit 4; }
VERDICT=$(python3 -c "import json; print(json.load(open('${SPRINT_DIR}/verdict.json'))['verdict'])")
python3 - "$RUN_ID" "$SPRINT" "$LIB_DIR" "$VERDICT" <<'PY'
import sys
from pathlib import Path
run_id, sprint, lib_dir, verdict = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
sys.path.insert(0, lib_dir)
from audit_log import append_event, render_audit_markdown
run_dir = Path(f"harness/runs/{run_id}")
append_event(run_dir, "grading_phase_completed", sprint=sprint, verdict=verdict)
render_audit_markdown(run_dir)
PY
echo "[run_sprint] verdict: $VERDICT"
