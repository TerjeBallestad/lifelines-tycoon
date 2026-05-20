#!/usr/bin/env bash
# End-to-end smoke test for AgentBridge + scripted player.
#
# Runs the baseline_observer plan against the prototype, verifies:
#   1. Godot exits cleanly (rc 0)
#   2. trace.jsonl is non-empty
#   3. trace contains at least one diagnostic_completed event
#   4. trace contains at least one day_started event

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Resolve Godot binary
if [ -n "${GODOT_BIN:-}" ]; then
    GODOT="$GODOT_BIN"
else
    GODOT=""
    for candidate in \
        "$HOME/Applications/Godot/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot_4.app/Contents/MacOS/Godot"; do
        if [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
    done
    if [ -z "$GODOT" ] && command -v godot &>/dev/null; then GODOT=godot; fi
fi
if [ -z "${GODOT:-}" ]; then echo "Error: cannot find Godot binary"; exit 1; fi

COMMS_DIR="/tmp/lifelines-harness-smoke/$(date +%s)"
TRACE_OUT="$COMMS_DIR/trace.jsonl"

echo "[smoke] godot:       $GODOT"
echo "[smoke] project:     $PROJECT_DIR"
echo "[smoke] comms-dir:   $COMMS_DIR"

# Ensure assets are imported before headless run.
"$GODOT" --headless --path "$PROJECT_DIR" --import &>/dev/null || true

python3 "$PROJECT_DIR/harness/lib/scripted_player.py" \
    --godot "$GODOT" \
    --project "$PROJECT_DIR" \
    --plan "$PROJECT_DIR/harness/strategies/examples/baseline_observer.json" \
    --comms-dir "$COMMS_DIR" \
    --trace-out "$TRACE_OUT" \
    --step-hours 1.0 \
    --checkpoint-timeout 30.0

if [ ! -s "$TRACE_OUT" ]; then
    echo "[smoke] FAIL: trace file empty: $TRACE_OUT"; exit 1
fi

# Trace assertions (Python json.dumps uses ": " separators)
if ! grep -q '"ev"[[:space:]]*:[[:space:]]*"day_started"' "$TRACE_OUT"; then
    echo "[smoke] FAIL: no day_started event in trace"; exit 1
fi

if ! grep -q '"ev"[[:space:]]*:[[:space:]]*"diagnostic_completed"' "$TRACE_OUT"; then
    echo "[smoke] FAIL: no diagnostic_completed event in trace"; exit 1
fi

# Schema validate every line
python3 - "$TRACE_OUT" <<'PY'
import sys
sys.path.insert(0, "harness/lib")
from trace_schema import validate_trace_file
lines, errs = validate_trace_file(sys.argv[1])
print(f"[smoke] {lines} lines, {errs} schema errors")
if errs > 0:
    sys.exit(2)
PY

echo "[smoke] PASS"
