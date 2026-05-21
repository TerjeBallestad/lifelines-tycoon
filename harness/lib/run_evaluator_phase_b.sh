#!/usr/bin/env bash
# run_evaluator_phase_b.sh — invoke Plan 4's grading pipeline on an AGREED sprint.
#
# Preconditions:
#   - harness/runs/<run-id>/sprint_<N>/contract.md exists with Status: AGREED
#   - harness/runs/<run-id>/sprint_<N>/ready exists (generator signaled done)
#
# Exits 0 iff Plan 4 wrote verdict.json + critique.md and the verdict.json's
# top-level "verdict" field is one of: PASS, PIVOT, REJECT.
set -euo pipefail

RUN_ID=""
SPRINT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$RUN_ID" && -n "$SPRINT" ]] || { echo "usage: $0 --run-id <id> --sprint <N>" >&2; exit 64; }

SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"
CONTRACT="${SPRINT_DIR}/contract.md"
READY="${SPRINT_DIR}/ready"

[[ -f "$CONTRACT" ]] || { echo "missing $CONTRACT" >&2; exit 65; }
grep -q '^## Status: AGREED$' "$CONTRACT" || { echo "contract is not AGREED at $CONTRACT" >&2; exit 65; }
[[ -f "$READY" ]] || { echo "generator did not signal ready at $READY" >&2; exit 65; }

# Hand off to Plan 4.
./harness/run_evaluator.sh --run-id "$RUN_ID" --sprint "$SPRINT"

VERDICT="${SPRINT_DIR}/verdict.json"
CRITIQUE="${SPRINT_DIR}/critique.md"
[[ -f "$VERDICT"  ]] || { echo "Plan 4 did not produce verdict.json" >&2; exit 70; }
[[ -f "$CRITIQUE" ]] || { echo "Plan 4 did not produce critique.md" >&2; exit 70; }

python3 - "$VERDICT" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
if v.get("verdict") not in ("PASS", "PIVOT", "REJECT"):
    print(f"verdict.json has unexpected verdict: {v.get('verdict')!r}", file=sys.stderr)
    sys.exit(70)
PY
