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

# Override claude_agents.py with a scripted shim.
cat > harness/lib/claude_agents.py <<'PY'
"""SMOKE STUB — overrides production claude_agents.py inside the smoke workdir."""
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
from negotiation_state import Turn

# Programme: gen drafts NEGOTIATING (round 1), eval responds AGREED (round 2),
# gen confirms AGREED unchanged (round 3) → terminal AGREED after 3 turns.
_VALID_NEGOTIATING = """# Sprint 1 Contract — Decision density

## Done means
- [test] `test/harness/s1.gd::test_x` passes
- [trace] events where ev=diagnostic_completed count >= 1

## Status: NEGOTIATING
"""
_VALID_AGREED = _VALID_NEGOTIATING.replace("## Status: NEGOTIATING", "## Status: AGREED")

_SCRIPT = {
    "generator": [_VALID_NEGOTIATING, _VALID_AGREED],
    "evaluator": [_VALID_AGREED],
}


@dataclass
class _ScriptedAgent:
    role: Turn
    run_id: str
    sprint: int
    _calls: int = field(default=0, init=False)

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        key = self.role.value
        seq = _SCRIPT[key]
        if self._calls >= len(seq):
            raise RuntimeError(f"smoke stub exhausted for {key} at call {self._calls}")
        (sprint_dir / "contract.md").write_text(seq[self._calls])
        self._calls += 1


def claude_generator_agent(*, run_id: str, sprint: int):
    return _ScriptedAgent(role=Turn.GENERATOR, run_id=run_id, sprint=sprint)


def claude_evaluator_agent(*, run_id: str, sprint: int):
    return _ScriptedAgent(role=Turn.EVALUATOR, run_id=run_id, sprint=sprint)
PY

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
assert a['rounds_used'] == 3, a
"
echo "[smoke] OK"
