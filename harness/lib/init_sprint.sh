#!/usr/bin/env bash
# Scaffold a sprint run directory under harness/runs/<run-id>/sprint_<N>/.
#
# Usage:
#   init_sprint.sh --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path>
#
# Creates:
#   contract.md              — template using the goal-file body, Status: NEGOTIATING
#   meta.json                — run metadata (run id, sprint, created_at, base SHA)
#   touch_surface.allow      — copy of the supplied allowlist
#   generator_session.jsonl  — empty file for tee'd subprocess output

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GOAL_FILE=""
TOUCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)        RUN_ID="$2"; shift 2 ;;
        --sprint)        SPRINT_N="$2"; shift 2 ;;
        --goal-file)     GOAL_FILE="$2"; shift 2 ;;
        --touch-surface) TOUCH="$2"; shift 2 ;;
        *) echo "init_sprint: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$RUN_ID" ];    then echo "init_sprint: missing --run-id" >&2;        exit 2; fi
if [ -z "$SPRINT_N" ];  then echo "init_sprint: missing --sprint" >&2;        exit 2; fi
if [ -z "$GOAL_FILE" ]; then echo "init_sprint: missing --goal-file" >&2;     exit 2; fi
if [ -z "$TOUCH" ];     then echo "init_sprint: missing --touch-surface" >&2; exit 2; fi

if [ ! -f "$GOAL_FILE" ]; then echo "init_sprint: goal-file not found: $GOAL_FILE" >&2; exit 2; fi
if [ ! -f "$TOUCH" ];     then echo "init_sprint: touch-surface not found: $TOUCH" >&2; exit 2; fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
mkdir -p "$SPRINT_DIR"

# touch_surface.allow — verbatim copy
cp "$TOUCH" "${SPRINT_DIR}/touch_surface.allow"

# generator_session.jsonl — empty placeholder
[ -f "${SPRINT_DIR}/generator_session.jsonl" ] || : > "${SPRINT_DIR}/generator_session.jsonl"

# meta.json — write only if missing (idempotency for resume)
META="${SPRINT_DIR}/meta.json"
if [ ! -f "$META" ]; then
    BASE_SHA=$(git rev-parse --verify HEAD 2>/dev/null || echo "uncommitted")
    CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "$META" <<JSON
{
  "run_id": "${RUN_ID}",
  "sprint": ${SPRINT_N},
  "created_at": "${CREATED_AT}",
  "base_sha": "${BASE_SHA}",
  "touch_surface": "harness/runs/${RUN_ID}/sprint_${SPRINT_N}/touch_surface.allow",
  "goal_file": "harness/runs/${RUN_ID}/sprint_${SPRINT_N}/goal.md"
}
JSON
fi

# goal.md — verbatim copy (idempotent)
[ -f "${SPRINT_DIR}/goal.md" ] || cp "$GOAL_FILE" "${SPRINT_DIR}/goal.md"

# contract.md — write template only if missing.
CONTRACT="${SPRINT_DIR}/contract.md"
if [ ! -f "$CONTRACT" ]; then
    GOAL_BODY=$(cat "$GOAL_FILE")
    cat > "$CONTRACT" <<MD
# Sprint ${SPRINT_N} Contract

> Generator drafts this, then operator (or Plan 4 evaluator) edits + flips Status.

## Sprint goal

${GOAL_BODY}

## Done means

- [test] <fill in: which .gd test must pass, exact path::test_name>
- [trace] <fill in: trace rule, e.g. "events where ev=diagnostic_completed and id=X count >= 1">

## Rubric coverage

- Axis ?: primary
- Axis ?: touched

## Forbidden side-effects

- <baseline expectations that must continue to hold>

## Status: NEGOTIATING
MD
fi

echo "$SPRINT_DIR"
