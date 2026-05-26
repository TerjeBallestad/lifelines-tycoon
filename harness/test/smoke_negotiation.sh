#!/usr/bin/env bash
# smoke_negotiation.sh — end-to-end dry-run for Plan 5 Phase A.
#
# Strategy: snapshot the repo into a temp workdir, REPLACE claude_agents.py
# with a scripted-writes shim that produces (NEGOTIATING → AGREED → AGREED),
# run run_sprint.sh --dry-run --skip-eval-phase-b, and assert artifacts.
set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cp -R "$REPO/harness" "$WORKDIR/"
cp -R "$REPO/docs"    "$WORKDIR/"
# Provide a fake git repo so run_generator.sh's `git rev-parse --show-toplevel` works.
# Use -b main so worktree_up.sh's `git rev-parse main` succeeds.
(cd "$WORKDIR" && git init -q -b main && git -c user.email=smoke@x -c user.name=smoke commit -q --allow-empty -m "init")
cd "$WORKDIR"

mkdir -p sprint_inputs
cat > sprint_inputs/goal.md <<'EOF'
# Sprint 1 — Decision density

Make day-1 decisions diverge across optimizer vs neglect strategies.
EOF
cat > sprint_inputs/touch.allow <<'EOF'
features/economy/
features/case_file/
test/harness/
EOF

# Use the built-in non-Anthropic scripted Phase A agent path. This proves the
# orchestrator can negotiate without patching in Claude-flavored test doubles.
export NEGOTIATION_AGENT_MODE=scripted

# Stub run_evaluator_phase_b.sh so we never actually run Plan 4 grading.
cat > harness/lib/run_evaluator_phase_b.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
echo "[smoke] skipping phase B grading"
exit 0
BASH
chmod +x harness/lib/run_evaluator_phase_b.sh

# Provide a generator shim for the implementation phase (Phase B-impl).
# run_generator.sh (implementation mode) needs GENERATOR_SHIM when GENERATOR_LIVE=0.
# The shim receives: <worktree_abs> <sprint_dir_abs>
# It must drop the ready sentinel so the orchestrator's polling loop exits.
SMOKE_GEN_SHIM="$(mktemp -t smoke_gen_shim).sh"
cat > "$SMOKE_GEN_SHIM" <<'SHIM'
#!/usr/bin/env bash
# args: <worktree_abs> <sprint_dir_abs>
touch "$2/ready"
SHIM
chmod +x "$SMOKE_GEN_SHIM"
export GENERATOR_SHIM="$SMOKE_GEN_SHIM"

RUN_ID="smoke-$(date +%s)"
./harness/run_sprint.sh \
  --run-id "$RUN_ID" \
  --sprint 1 \
  --goal-file sprint_inputs/goal.md \
  --touch-surface sprint_inputs/touch.allow \
  --skip-eval-phase-b \
  --dry-run

SPRINT_DIR="harness/runs/${RUN_ID}/sprint_1"
test -f "$SPRINT_DIR/contract.md"            || { echo "[smoke] contract.md missing" >&2; exit 1; }
test -f "$SPRINT_DIR/negotiation_state.json" || { echo "[smoke] state missing" >&2; exit 1; }
test -f "$SPRINT_DIR/agreement.json"         || { echo "[smoke] agreement.json missing" >&2; exit 1; }
grep -q '^## Status: AGREED$' "$SPRINT_DIR/contract.md" || { echo "[smoke] not agreed" >&2; exit 1; }
python3 -c "
import json
a = json.load(open('$SPRINT_DIR/agreement.json'))
assert a['terminal_status'] == 'AGREED', a
assert a['rounds_used'] == 2, a
"
echo "[smoke] OK"
