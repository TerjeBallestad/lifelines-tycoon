#!/usr/bin/env bash
# init_negotiation.sh — bootstrap a sprint dir for Phase A contract negotiation.
#
# Usage:
#   init_negotiation.sh --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path> [--force] [--max-rounds N]
#
# Creates:
#   harness/runs/<run-id>/sprint_<N>/{goal.md, touch_surface.allow, contract.md, negotiation_state.json}
#   harness/.locks/contract_<run-id>_<N>.lock (empty)
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path> [--force] [--max-rounds N]
EOF
  exit 64
}

RUN_ID=""
SPRINT=""
GOAL_FILE=""
TOUCH_FILE=""
FORCE=0
MAX_ROUNDS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)        RUN_ID="$2"; shift 2 ;;
    --sprint)        SPRINT="$2"; shift 2 ;;
    --goal-file)     GOAL_FILE="$2"; shift 2 ;;
    --touch-surface) TOUCH_FILE="$2"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    --max-rounds)    MAX_ROUNDS="$2"; shift 2 ;;
    -h|--help)       usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$RUN_ID"     ]] || { echo "missing --run-id" >&2; usage; }
[[ -n "$SPRINT"     ]] || { echo "missing --sprint" >&2; usage; }
[[ -n "$GOAL_FILE"  ]] || { echo "missing --goal-file" >&2; usage; }
[[ -n "$TOUCH_FILE" ]] || { echo "missing --touch-surface" >&2; usage; }
[[ -f "$GOAL_FILE"  ]] || { echo "goal file not found: $GOAL_FILE" >&2; exit 65; }
[[ -f "$TOUCH_FILE" ]] || { echo "touch surface file not found: $TOUCH_FILE" >&2; exit 65; }
[[ "$SPRINT" =~ ^[0-9]+$ ]] || { echo "sprint must be an integer" >&2; usage; }

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"
LOCK_PATH="harness/.locks/contract_${RUN_ID}_${SPRINT}.lock"

if [[ -e "$SPRINT_DIR/contract.md" && "$FORCE" -ne 1 ]]; then
  echo "sprint already initialized at $SPRINT_DIR (use --force to overwrite)" >&2
  exit 66
fi

mkdir -p "$SPRINT_DIR" "harness/.locks"
cp "$GOAL_FILE"  "$SPRINT_DIR/goal.md"
cp "$TOUCH_FILE" "$SPRINT_DIR/touch_surface.allow"

# Seed contract.md via the Python template module.
python3 - "$RUN_ID" "$SPRINT" "$SPRINT_DIR/goal.md" "$SPRINT_DIR/contract.md" "$LIB_DIR" <<'PY'
import sys
from pathlib import Path
run_id, sprint, goal_path, out_path, lib_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
sys.path.insert(0, lib_dir)
from contract_template import seed_contract_text
Path(out_path).write_text(seed_contract_text(run_id=run_id, sprint=sprint, goal_md=Path(goal_path).read_text()))
PY

# Initialize negotiation_state.json (zero turns).
python3 - "$RUN_ID" "$SPRINT" "$MAX_ROUNDS" "$SPRINT_DIR/negotiation_state.json" "$LIB_DIR" <<'PY'
import sys
from pathlib import Path
run_id, sprint, max_rounds, out_path, lib_dir = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
sys.path.insert(0, lib_dir)
from negotiation_state import NegotiationState
NegotiationState.new(run_id=run_id, sprint=sprint, max_rounds=max_rounds).to_file(out_path)
PY

# Create the lock file (empty).
touch "$LOCK_PATH"

echo "initialized $SPRINT_DIR"
