#!/usr/bin/env bash
# run_evaluator_agent.sh — evaluator-side turn driver for Phase A negotiation.
#
# Invoked by run_sprint.sh once per evaluator turn. Wraps the `claude` CLI to
# spawn or resume a long-lived Opus session.
#
# Usage:
#   run_evaluator_agent.sh --run-id <id> --sprint <N> --round <N>
#
# Behavior:
#   - If harness/runs/<run-id>/sprint_<N>/evaluator_session.id exists, --resume it.
#   - Otherwise spawn fresh with `claude -p` + harness/prompts/evaluator.md as
#     system prompt.
#   - Per-turn user prompt: instruct the evaluator to read the contract, critique
#     it, optionally edit it, and stop.
#   - On exit, the agent will have rewritten contract.md.
#
# Env vars:
#   EVALUATOR_LIVE=1   → use real `claude` CLI; default 0 (shim/no-op).
#   CLAUDE_MODEL_EVAL  → defaults to claude-opus-4-7 when EVALUATOR_LIVE=1.
#
# NOTE: This script calls `claude` CLI directly. Session id persistence uses
#   claude_subprocess.py's parse_session_id helper to parse stream-json output.
set -euo pipefail

RUN_ID=""
SPRINT=""
ROUND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)  RUN_ID="$2"; shift 2 ;;
    --sprint)  SPRINT="$2"; shift 2 ;;
    --round)   ROUND="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$RUN_ID" && -n "$SPRINT" && -n "$ROUND" ]] || {
  echo "usage: $0 --run-id <id> --sprint <N> --round <R>" >&2
  exit 64
}

REPO_ROOT="$(git rev-parse --show-toplevel)"
LIB_DIR="${REPO_ROOT}/harness/lib"
PROMPT_DIR="${REPO_ROOT}/harness/prompts"
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT}"
SESSION_FILE="${SPRINT_DIR}/evaluator_session.id"
LOG_FILE="${SPRINT_DIR}/evaluator_session.log"
CONTRACT_PATH="${SPRINT_DIR}/contract.md"

mkdir -p "$(dirname "$LOG_FILE")"

[[ -f "$CONTRACT_PATH" ]] || { echo "contract.md missing at $CONTRACT_PATH" >&2; exit 65; }

# Read current status via contract_schema (no flock dependency here — caller
# holds the lock if needed; this script runs synchronously inside a turn slot).
STATUS=$(python3 - "$CONTRACT_PATH" "$LIB_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from contract_schema import parse_contract
print(parse_contract(open(sys.argv[1]).read()).status)
PY
)

USER_PROMPT="$(cat <<EOF
It is round ${ROUND} of Phase A negotiation for sprint ${SPRINT}.

The current contract is at \`${CONTRACT_PATH}\`. Its current status is \`${STATUS}\`.

Read the contract, the sprint goal (\`${SPRINT_DIR}/goal.md\`), the rubric (\`docs/rubric/rubric.md\`), and the relevant anchors under \`docs/rubric/anchors/\`.

Make at most 3 concrete edits to the contract, OR confirm the contract as-is. Follow the rules in your system prompt — in particular, you may write \`## Status: AGREED\` ONLY if you made no edits beyond the status line.

Stop after writing.
EOF
)"

SYSTEM_PROMPT_TEXT="$(cat "$PROMPT_DIR/evaluator.md")"
MODEL="${CLAUDE_MODEL_EVAL:-claude-opus-4-7}"

if [[ "${EVALUATOR_LIVE:-0}" != "1" ]]; then
  # Dry-run / shim mode: no-op. The negotiation loop smoke test supplies its
  # own TurnAgent shim; this script is only wired for EVALUATOR_LIVE=1 runs.
  echo "[run_evaluator_agent] EVALUATOR_LIVE=0 — shim mode, no-op" >&2
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "run_evaluator_agent: EVALUATOR_LIVE=1 but \`claude\` CLI not found" >&2
  exit 2
fi

# Temp file to capture stream-json output so we can extract the session id.
STREAM_TMP=$(mktemp)
trap 'rm -f "$STREAM_TMP"' EXIT

if [[ -f "$SESSION_FILE" ]]; then
  SESSION_ID="$(<"$SESSION_FILE")"
  echo "[run_evaluator_agent] resuming session $SESSION_ID (round $ROUND)" >&2
  (
    cd "$REPO_ROOT"
    claude -p "$USER_PROMPT" \
      --resume "$SESSION_ID" \
      --model "$MODEL" \
      --append-system-prompt "$SYSTEM_PROMPT_TEXT" \
      --output-format stream-json \
      --permission-mode acceptEdits \
      2>&1 | tee -a "$LOG_FILE"
  )
else
  echo "[run_evaluator_agent] spawning fresh Opus session (round $ROUND)" >&2
  (
    cd "$REPO_ROOT"
    claude -p "$USER_PROMPT" \
      --model "$MODEL" \
      --append-system-prompt "$SYSTEM_PROMPT_TEXT" \
      --output-format stream-json \
      --permission-mode acceptEdits \
      2>&1 | tee -a "$LOG_FILE" > "$STREAM_TMP"
  )

  # Extract and persist the session id from stream-json output.
  python3 - "$STREAM_TMP" "$SESSION_FILE" "$LIB_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from claude_subprocess import parse_session_id
text = open(sys.argv[1]).read()
sid = parse_session_id(text)
if sid:
    open(sys.argv[2], "w").write(sid)
    print(f"[run_evaluator_agent] session id saved: {sid}", file=sys.stderr)
else:
    print("[run_evaluator_agent] WARNING: could not parse session id from output", file=sys.stderr)
PY
fi
