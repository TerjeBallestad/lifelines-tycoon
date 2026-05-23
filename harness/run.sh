#!/usr/bin/env bash
# run.sh - Phase 6 run-level entrypoint scaffold.
#
# Usage:
#   ./harness/run.sh "<prompt>"
#   ./harness/run.sh --resume <run-id>
#   ./harness/run.sh --replay <run-id> <sprint-N>
#
# Phase 6 live agent execution is configurable and disabled by default while
# the planner, run state, git integration, and report renderer are introduced.
set -euo pipefail

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

echo "[run] Phase 6 scaffold only: no planner or sprint orchestration invoked." >&2
echo "[run] Live agent execution will be configurable; dry-run/shimmed mode is the default." >&2
exit 64
