#!/usr/bin/env bash
# Operator-facing generator launcher.
#
# Usage:
#   ./harness/run_generator.sh \
#       --run-id <id> \
#       --sprint <N> \
#       --goal-file <path-to-goal.md> \
#       --touch-surface <path-to-allowlist> \
#       [--ready-timeout <seconds>] [--base-sha <sha>]   # default timeout 1800
#
# Effect:
#   1. Scaffold sprint dir via init_sprint.sh.
#   2. Create worktree via worktree_up.sh.
#   3. Spawn the generator subprocess (claude -p in real mode, or a recorded
#      shim in dry-run mode controlled by GENERATOR_LIVE=1).
#   4. Poll for the `ready` sentinel; on appearance, report verdict by reading
#      the sprint's trace.jsonl + contract.md (re-uses sprint_smoke logic).
#   5. Print the worktree path so the operator can review the diff or
#      cherry-pick manually.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GOAL_FILE=""
TOUCH=""
TIMEOUT_S="${HARNESS_READY_TIMEOUT:-1800}"
ROUND=""
BASE_SHA=""

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)         RUN_ID="$2"; shift 2 ;;
        --sprint)         SPRINT_N="$2"; shift 2 ;;
        --goal-file)      GOAL_FILE="$2"; shift 2 ;;
        --touch-surface)  TOUCH="$2"; shift 2 ;;
        --ready-timeout)  TIMEOUT_S="$2"; shift 2 ;;
        --round)          ROUND="$2"; shift 2 ;;
        --base-sha)       BASE_SHA="$2"; shift 2 ;;
        *) echo "run_generator: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$RUN_ID" ];    then echo "run_generator: missing --run-id" >&2;        exit 2; fi
if [ -z "$SPRINT_N" ];  then echo "run_generator: missing --sprint" >&2;        exit 2; fi
if [ -z "$GOAL_FILE" ]; then echo "run_generator: missing --goal-file" >&2;     exit 2; fi
if [ -z "$TOUCH" ];     then echo "run_generator: missing --touch-surface" >&2; exit 2; fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR_REL="harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
SPRINT_DIR_ABS="${REPO_ROOT}/${SPRINT_DIR_REL}"
READY_FILE="${SPRINT_DIR_ABS}/ready"

# Plan 5 Phase A negotiation: single-turn edit-and-stop mode.
if [ -n "$ROUND" ]; then
    CONTRACT_PATH="${SPRINT_DIR_ABS}/contract.md"
    if [ ! -f "$CONTRACT_PATH" ]; then
        echo "[run_generator] --round set but $CONTRACT_PATH missing — init_negotiation.sh must run first" >&2
        exit 2
    fi

    LIB_DIR="${REPO_ROOT}/harness/lib"
    PROMPT_DIR="${REPO_ROOT}/harness/prompts"
    SESSION_FILE="${SPRINT_DIR_ABS}/generator_session.id"
    LOG_FILE="${SPRINT_DIR_ABS}/generator_session.log"

    STATUS=$(python3 - "$CONTRACT_PATH" "$LIB_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from contract_schema import parse_contract
print(parse_contract(open(sys.argv[1]).read()).status)
PY
)

    PHASE_A_USER_PROMPT="It is round ${ROUND} of Phase A negotiation for sprint ${SPRINT_N}.

The current contract is at \`${CONTRACT_PATH}\`. Its current status is \`${STATUS}\`.

If the contract still contains the literal token \`__REPLACE_ME__\`, you must replace every occurrence with a concrete value before doing anything else.

Read the contract, the sprint goal (\`${SPRINT_DIR_ABS}/goal.md\`), and the rubric (\`docs/rubric/rubric.md\`). If the contract is gradable and matches the sprint's intent, write \`## Status: AGREED\` (and make no other edits). Otherwise edit it in place and write \`## Status: NEGOTIATING\`.

Stop after writing."

    mkdir -p "$(dirname "$LOG_FILE")"

    if [ "${GENERATOR_LIVE:-0}" != "1" ]; then
        echo "[run_generator] --round mode but GENERATOR_LIVE=0 — shim no-op (smoke supplies its own TurnAgent)" >&2
        exit 0
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "[run_generator] GENERATOR_LIVE=1 but \`claude\` CLI not found" >&2
        exit 2
    fi

    SYSTEM_PROMPT_TEXT="$(cat "$PROMPT_DIR/generator.md")"
    MODEL="${CLAUDE_MODEL_GEN:-claude-sonnet-4-6}"

    STREAM_TMP=$(mktemp)
    trap 'rm -f "$STREAM_TMP"' EXIT

    if [ -f "$SESSION_FILE" ]; then
        SESSION_ID="$(cat "$SESSION_FILE")"
        echo "[run_generator] Phase A: resuming session $SESSION_ID (round $ROUND)" >&2
        (
            cd "$REPO_ROOT"
            claude -p "$PHASE_A_USER_PROMPT" \
                --resume "$SESSION_ID" \
                --model "$MODEL" \
                --append-system-prompt "$SYSTEM_PROMPT_TEXT" \
                --output-format stream-json \
                --permission-mode acceptEdits \
                2>&1 | tee -a "$LOG_FILE"
        )
    else
        echo "[run_generator] Phase A: spawning fresh Sonnet session (round $ROUND)" >&2
        (
            cd "$REPO_ROOT"
            claude -p "$PHASE_A_USER_PROMPT" \
                --model "$MODEL" \
                --append-system-prompt "$SYSTEM_PROMPT_TEXT" \
                --output-format stream-json \
                --permission-mode acceptEdits \
                2>&1 | tee -a "$LOG_FILE" > "$STREAM_TMP"
        )
        python3 - "$STREAM_TMP" "$SESSION_FILE" "$LIB_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from claude_subprocess import parse_session_id
text = open(sys.argv[1]).read()
sid = parse_session_id(text)
if sid:
    open(sys.argv[2], "w").write(sid)
PY
    fi

    exit 0
fi

echo "[run_generator] scaffolding sprint dir…"
bash "${REPO_ROOT}/harness/lib/init_sprint.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --goal-file "$GOAL_FILE" --touch-surface "$TOUCH"

echo "[run_generator] creating worktree…"
WORKTREE_ABS=$(bash "${REPO_ROOT}/harness/lib/worktree_up.sh" "$RUN_ID" "$SPRINT_N" \
    "${SPRINT_DIR_ABS}/touch_surface.allow" "$BASE_SHA")
echo "[run_generator] worktree: $WORKTREE_ABS"

# Make sure no stale sentinel survives a previous run.
rm -f "$READY_FILE" "${SPRINT_DIR_ABS}/blocker.md"

# Build the subprocess command.
SYSTEM_PROMPT="${REPO_ROOT}/harness/prompts/generator.md"
USER_PROMPT_FILE="${SPRINT_DIR_ABS}/goal.md"
SESSION_LOG="${SPRINT_DIR_ABS}/generator_session.jsonl"

if [ "${GENERATOR_LIVE:-0}" = "1" ]; then
    if ! command -v claude >/dev/null 2>&1; then
        echo "run_generator: GENERATOR_LIVE=1 but \`claude\` CLI not found" >&2
        exit 2
    fi
    # Real generator: claude -p, Sonnet 4.6, system prompt = generator.md.
    # The user prompt is the rendered sprint context.
    USER_PROMPT="Sprint ${SPRINT_N} for run ${RUN_ID}.
Read in this order:
  1. ${SPRINT_DIR_REL}/goal.md
  2. ${SPRINT_DIR_REL}/contract.md
  3. docs/rubric/vision.md
  4. docs/rubric/rubric.md
Then proceed per the system prompt's per-sprint loop. Stop when ${SPRINT_DIR_REL}/ready exists."

    (
        cd "$WORKTREE_ABS"
        claude -p "$USER_PROMPT" \
            --model claude-sonnet-4-6 \
            --append-system-prompt "$(cat "$SYSTEM_PROMPT")" \
            --output-format stream-json \
            --permission-mode acceptEdits \
            2>&1 | tee -a "$SESSION_LOG"
    ) &
    GEN_PID=$!
elif [ -n "${GENERATOR_SHIM:-}" ]; then
    # Dry-run / smoke shim: a script that simulates the generator's effect on disk.
    "$GENERATOR_SHIM" "$WORKTREE_ABS" "$SPRINT_DIR_ABS" >> "$SESSION_LOG" 2>&1 &
    GEN_PID=$!
else
    echo "run_generator: must set GENERATOR_LIVE=1 (real run) or GENERATOR_SHIM=<path> (dry-run)" >&2
    exit 2
fi

echo "[run_generator] generator PID $GEN_PID; awaiting $READY_FILE (timeout ${TIMEOUT_S}s)…"

deadline=$(( $(date +%s) + TIMEOUT_S ))
while [ ! -f "$READY_FILE" ]; do
    if [ $(date +%s) -ge $deadline ]; then
        echo "[run_generator] TIMEOUT: no ready sentinel after ${TIMEOUT_S}s; killing generator" >&2
        kill -TERM "$GEN_PID" 2>/dev/null || true
        wait "$GEN_PID" 2>/dev/null || true
        exit 3
    fi
    if ! kill -0 "$GEN_PID" 2>/dev/null; then
        echo "[run_generator] generator exited before writing ready sentinel" >&2
        exit 4
    fi
    sleep 2
done

# Allow the subprocess to settle then capture exit.
wait "$GEN_PID" 2>/dev/null || true
echo "[run_generator] ready sentinel observed; producing verdict…"

# Verdict: blocker.md → BLOCKED; else run sprint_smoke for [trace] items.
if [ -f "${SPRINT_DIR_ABS}/blocker.md" ]; then
    echo "[run_generator] BLOCKED — see ${SPRINT_DIR_REL}/blocker.md"
    cat "${SPRINT_DIR_ABS}/blocker.md"
    echo
    echo "[run_generator] worktree: $WORKTREE_ABS"
    exit 10
fi

# Trace verdict — only valid when the contract supplies an action plan path.
# Convention: contract.md may include a line "## Action plan: <relative path>"
PLAN_PATH=$(awk '/^##[[:space:]]+Action plan:/{print $4}' "${SPRINT_DIR_ABS}/contract.md" || true)
if [ -n "$PLAN_PATH" ]; then
    if [ "${PLAN_PATH:0:1}" != "/" ]; then PLAN_PATH="${REPO_ROOT}/${PLAN_PATH}"; fi
    if bash "${REPO_ROOT}/harness/lib/sprint_smoke.sh" \
        --run-id "$RUN_ID" --sprint "$SPRINT_N" --plan "$PLAN_PATH"; then
        echo "[run_generator] PASS"
        echo "[run_generator] worktree: $WORKTREE_ABS"
        exit 0
    else
        echo "[run_generator] FAIL — trace rules unsatisfied"
        echo "[run_generator] worktree: $WORKTREE_ABS"
        exit 11
    fi
else
    echo "[run_generator] ready observed; no action plan declared in contract — operator must grade manually"
    echo "[run_generator] worktree: $WORKTREE_ABS"
    exit 0
fi
