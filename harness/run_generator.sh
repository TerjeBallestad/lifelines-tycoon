#!/usr/bin/env bash
# Operator-facing generator launcher.
#
# Usage:
#   ./harness/run_generator.sh \
#       --run-id <id> \
#       --sprint <N> \
#       --goal-file <path-to-goal.md> \
#       --touch-surface <path-to-allowlist> \
#       [--ready-timeout <seconds>]   # default 1800
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

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)         RUN_ID="$2"; shift 2 ;;
        --sprint)         SPRINT_N="$2"; shift 2 ;;
        --goal-file)      GOAL_FILE="$2"; shift 2 ;;
        --touch-surface)  TOUCH="$2"; shift 2 ;;
        --ready-timeout)  TIMEOUT_S="$2"; shift 2 ;;
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

echo "[run_generator] scaffolding sprint dir…"
bash "${REPO_ROOT}/harness/lib/init_sprint.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --goal-file "$GOAL_FILE" --touch-surface "$TOUCH"

echo "[run_generator] creating worktree…"
WORKTREE_ABS=$(bash "${REPO_ROOT}/harness/lib/worktree_up.sh" "$RUN_ID" "$SPRINT_N" \
    "${SPRINT_DIR_ABS}/touch_surface.allow")
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
