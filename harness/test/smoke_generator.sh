#!/usr/bin/env bash
# End-to-end smoke for harness/run_generator.sh — dry-run mode (no Claude API).
#
# A shim script plays the generator: it writes a known-good change under the
# touch-surface allowlist, runs the GUT test it just wrote, drops a ready
# sentinel. The orchestrator's job (create worktree, install hooks, scaffold
# sprint dir, poll for ready, report verdict) is exercised in full.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

RUN_ID="SMOKE-$(date +%s)"
SPRINT_N=1
WORKDIR=$(mktemp -d)

# Goal & touch surface as ephemeral inputs.
GOAL="${WORKDIR}/goal.md"
TOUCH="${WORKDIR}/touch.allow"

cat > "$GOAL" <<'MD'
Add a no-op file under features/economy/diagnostics/ named `smoke_marker.tres`
containing a single `marker = "smoke"` line, then write a GUT test under
test/unit/ that asserts the file exists.
MD

cat > "$TOUCH" <<'ALLOW'
features/economy/diagnostics/**
test/unit/**
harness/runs/**
ALLOW

# The shim — pretends to be the generator. It uses ONLY worktree-relative paths
# so it remains side-effect-free against the primary repo.
SHIM="${WORKDIR}/generator_shim.sh"
cat > "$SHIM" <<'SHIM_BODY'
#!/usr/bin/env bash
set -euo pipefail
WORKTREE="$1"
SPRINT_DIR="$2"   # primary-repo sprint dir, reachable via the worktree symlink too

cd "$WORKTREE"

# 1. Set contract Status: AGREED, embed an action plan + trace rule.
cat > "${SPRINT_DIR}/contract.md" <<'CONTRACT'
# Sprint 1 Contract

## Sprint goal

Smoke generator end-to-end.

## Done means

- [test] `test/unit/test_smoke_marker.gd::test_marker_file_exists` passes
- [trace] events where ev=day_started count >= 1

## Rubric coverage

- Axis 0: smoke

## Status: AGREED

## Action plan: harness/strategies/examples/baseline_observer.json
CONTRACT

# 2. Add the marker resource.
mkdir -p features/economy/diagnostics
cat > features/economy/diagnostics/smoke_marker.tres <<'TRES'
[gd_resource type="Resource" format=3]

[resource]
marker = "smoke"
TRES

# 3. Add the GUT test.
cat > test/unit/test_smoke_marker.gd <<'GD'
extends GutTest

func test_marker_file_exists() -> void:
    assert_true(FileAccess.file_exists("res://features/economy/diagnostics/smoke_marker.tres"))
GD

# 4. Commit (hooks must approve).
git add features/economy/diagnostics/smoke_marker.tres test/unit/test_smoke_marker.gd
git -c user.email=shim@example.com -c user.name=Shim commit -m "feat(smoke): add marker resource + test"

# 5. Drop ready sentinel.
touch "${SPRINT_DIR}/ready"
SHIM_BODY
chmod +x "$SHIM"

# Run the orchestrator with the shim.
GENERATOR_SHIM="$SHIM" \
    bash "${REPO_ROOT}/harness/run_generator.sh" \
    --run-id "$RUN_ID" \
    --sprint "$SPRINT_N" \
    --goal-file "$GOAL" \
    --touch-surface "$TOUCH" \
    --ready-timeout 120 \
    || {
        rc=$?
        # Trace-rule check requires running Godot; exit 0 (no plan grade) is also fine,
        # exit 11 means [trace] not satisfied which is acceptable in a no-Godot smoke run.
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 11 ]; then
            echo "smoke_generator: unexpected exit $rc" >&2
            exit $rc
        fi
    }

# Assertions: worktree, sentinel, commit on harness branch, contract AGREED.
WORKTREE=".worktrees/harness/${RUN_ID}/sprint_${SPRINT_N}"
[ -d "$WORKTREE" ] || { echo "smoke: worktree missing"; exit 1; }
[ -f "harness/runs/${RUN_ID}/sprint_${SPRINT_N}/ready" ] || { echo "smoke: ready sentinel missing"; exit 1; }
grep -q '## Status: AGREED' "harness/runs/${RUN_ID}/sprint_${SPRINT_N}/contract.md" \
    || { echo "smoke: contract not AGREED"; exit 1; }
BRANCH_LOG=$(git -C "$WORKTREE" log --oneline)
echo "$BRANCH_LOG" | grep -q 'feat(smoke)' \
    || { echo "smoke: shim commit not on branch"; exit 1; }

# Cleanup. Order matters: drop the shared pre-commit hook FIRST so subsequent
# commits on the primary repo aren't broken by a stale touch-surface allowlist
# (the hook trampoline points at a path inside harness/runs/<run-id>/ that we
# delete a few lines down). Plan 5's orchestrator will swap this for per-worktree
# `core.hooksPath`; for now this one-liner keeps the smoke side-effect-free.
HOOK_PATH=$(git rev-parse --git-path hooks/pre-commit)
if [ -f "$HOOK_PATH" ] && grep -q 'install_worktree_hooks.sh' "$HOOK_PATH"; then
    rm -f "$HOOK_PATH"
fi
git worktree remove --force "$WORKTREE"
git branch -D "harness/${RUN_ID}/sprint_${SPRINT_N}"
rm -rf "harness/runs/${RUN_ID}"
rm -rf "$WORKDIR"

echo "[smoke_generator] PASS"
