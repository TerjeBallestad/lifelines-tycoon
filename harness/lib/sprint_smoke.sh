#!/usr/bin/env bash
# Run a scripted playtest + scan its trace against the contract's [trace] rules.
#
# Usage:
#   sprint_smoke.sh --run-id <id> --sprint <N> --plan <action-plan.json> \
#                   [--godot <godot-binary>] [--reveal-hidden]
#
# Resolves the contract from harness/runs/<run-id>/sprint_<N>/contract.md and
# extracts every "[trace] events where ... count ... N | must exist" line, then
# evaluates each rule against the trace produced by the playtest. Exits 0 iff
# every rule passes.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
PLAN=""
GODOT="${GODOT_BIN:-}"
REVEAL_FLAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)        RUN_ID="$2"; shift 2 ;;
        --sprint)        SPRINT_N="$2"; shift 2 ;;
        --plan)          PLAN="$2"; shift 2 ;;
        --godot)         GODOT="$2"; shift 2 ;;
        --reveal-hidden) REVEAL_FLAG="--reveal-hidden"; shift ;;
        *) echo "sprint_smoke: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$RUN_ID" ];   then echo "sprint_smoke: missing --run-id" >&2; exit 2; fi
if [ -z "$SPRINT_N" ]; then echo "sprint_smoke: missing --sprint" >&2; exit 2; fi
if [ -z "$PLAN" ];     then echo "sprint_smoke: missing --plan" >&2;   exit 2; fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
CONTRACT="${SPRINT_DIR}/contract.md"
COMMS_DIR="${SPRINT_DIR}/comms"
TRACE_OUT="${SPRINT_DIR}/trace.jsonl"

if [ ! -f "$CONTRACT" ]; then echo "sprint_smoke: no contract.md at $CONTRACT" >&2; exit 2; fi
if [ ! -f "$PLAN" ];     then echo "sprint_smoke: no plan at $PLAN" >&2; exit 2; fi

# Resolve Godot binary if not supplied.
if [ -z "$GODOT" ]; then
    for candidate in \
        "$HOME/Applications/Godot/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot"; do
        if [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
    done
    if [ -z "$GODOT" ] && command -v godot &>/dev/null; then GODOT=godot; fi
fi
if [ -z "$GODOT" ]; then echo "sprint_smoke: cannot find Godot binary" >&2; exit 2; fi

mkdir -p "$COMMS_DIR"

# Run the scripted player from Plan 1.
python3 "${REPO_ROOT}/harness/lib/scripted_player.py" \
    --godot "$GODOT" \
    --project "$REPO_ROOT" \
    --plan "$PLAN" \
    --comms-dir "$COMMS_DIR" \
    --trace-out "$TRACE_OUT" \
    $REVEAL_FLAG

# Evaluate every [trace] rule from contract.md against the trace.
python3 - "$CONTRACT" "$TRACE_OUT" <<'PY'
import sys, re
sys.path.insert(0, "harness/lib")
from contract_schema import parse_contract
from scan_contract_trace import scan_trace_file

contract_path, trace_path = sys.argv[1], sys.argv[2]
with open(contract_path) as fh:
    contract = parse_contract(fh.read())

trace_items = [i for i in contract.items if i.kind == "trace"]
if not trace_items:
    print("sprint_smoke: no [trace] items in contract — nothing to verify")
    sys.exit(0)

rules = [i.body for i in trace_items]
results = scan_trace_file(trace_path, rules)
fails = [r for r in results if not r.passed]
for r in results:
    status = "PASS" if r.passed else "FAIL"
    print(f"  [{status}] {r.rule.raw} — {r.message}")
if fails:
    print(f"sprint_smoke: {len(fails)}/{len(results)} trace rules failed", file=sys.stderr)
    sys.exit(1)
print(f"sprint_smoke: {len(results)} trace rules passed")
PY
