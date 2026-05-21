#!/usr/bin/env bash
# harness/lib/tournament.sh
#
# Run a strategy × seed tournament + (optional) freeplay run, writing trace
# jsonl files into harness/runs/<run-id>/sprint_<N>/traces/.
#
# Required env (or args):
#   --run-id     <run-id>
#   --sprint     <N>
#   --godot      <godot binary path>
#   --project    <worktree path>           # the sprint's worktree, not the main repo
#
# Optional:
#   --strategies <comma-list>              # default: eager_diagnostician,intervention_spammer,patient_observer,neglect
#   --seeds      <comma-list>              # default: 1,2,3
#   --skip-freeplay                        # do not run freeplay
#   --live                                 # use real claude (else shim)
#   --shim-canned <path>                   # required if --live not set
#
# Exits 0 iff every requested run wrote a non-empty trace file.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GODOT=""
PROJECT=""
STRATEGIES="eager_diagnostician,intervention_spammer,patient_observer,neglect"
SEEDS="1,2,3"
SKIP_FREEPLAY=0
LIVE=0
SHIM_CANNED=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-id)         RUN_ID="$2";        shift 2 ;;
        --sprint)         SPRINT_N="$2";      shift 2 ;;
        --godot)          GODOT="$2";         shift 2 ;;
        --project)        PROJECT="$2";       shift 2 ;;
        --strategies)     STRATEGIES="$2";    shift 2 ;;
        --seeds)          SEEDS="$2";         shift 2 ;;
        --skip-freeplay)  SKIP_FREEPLAY=1;    shift   ;;
        --live)           LIVE=1;             shift   ;;
        --shim-canned)    SHIM_CANNED="$2";   shift 2 ;;
        *) echo "tournament: unknown arg: $1" >&2; exit 2 ;;
    esac
done

for var in RUN_ID SPRINT_N GODOT PROJECT; do
    if [ -z "${!var}" ]; then
        echo "tournament: missing required --$(echo $var | tr A-Z_ a-z- | sed 's/run-id/run-id/')" >&2
        exit 2
    fi
done
if [ "$LIVE" = "0" ] && [ -z "$SHIM_CANNED" ]; then
    echo "tournament: --live not set; --shim-canned <path> is required for dry-run mode" >&2
    exit 2
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
TRACES_DIR="${SPRINT_DIR}/traces"
SESSIONS_DIR="${SPRINT_DIR}/strategy_sessions"
mkdir -p "$TRACES_DIR" "$SESSIONS_DIR"

run_one() {
    local strategy_id="$1"
    local seed="$2"
    local mode_flag="$3"  # "prior" or "freeplay"
    local trace_out="${TRACES_DIR}/${strategy_id}_seed${seed}.jsonl"
    if [ "$mode_flag" = "freeplay" ]; then
        trace_out="${TRACES_DIR}/freeplay.jsonl"
    fi
    local session_log="${SESSIONS_DIR}/${strategy_id}_seed${seed}.log"
    local comms_dir
    comms_dir=$(mktemp -d -t "lifelines-tournament.XXXXXX")
    trap 'rm -rf "$comms_dir"' RETURN
    local strategy_md="${REPO_ROOT}/harness/strategies/${strategy_id}.md"

    if [ ! -f "$strategy_md" ]; then
        echo "tournament: strategy file not found: $strategy_md" >&2
        return 1
    fi

    local args=(
        "${REPO_ROOT}/harness/lib/llm_player.py"
        --godot "$GODOT"
        --project "$PROJECT"
        --strategy "$strategy_md"
        --seed "$seed"
        --comms-dir "$comms_dir"
        --trace-out "$trace_out"
        --session-log "$session_log"
    )
    if [ "$LIVE" = "1" ]; then
        args+=( --live )
    else
        args+=( --shim-canned "$SHIM_CANNED" )
    fi

    echo "[tournament] strategy=$strategy_id seed=$seed -> $trace_out" >&2
    python3 "${args[@]}"

    if [ ! -s "$trace_out" ]; then
        echo "[tournament] empty trace: $trace_out" >&2
        return 1
    fi
}

IFS=',' read -r -a STRAT_ARR <<<"$STRATEGIES"
IFS=',' read -r -a SEED_ARR  <<<"$SEEDS"

for strat in "${STRAT_ARR[@]}"; do
    for seed in "${SEED_ARR[@]}"; do
        run_one "$strat" "$seed" "prior"
    done
done

if [ "$SKIP_FREEPLAY" = "0" ]; then
    run_one "freeplay" "1" "freeplay"
fi

echo "[tournament] complete: $(ls "$TRACES_DIR" | wc -l | tr -d ' ') traces in $TRACES_DIR" >&2
