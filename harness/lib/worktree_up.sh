#!/usr/bin/env bash
# Create an isolated worktree for one sprint.
#
# Usage:
#   worktree_up.sh <run-id> <sprint-N> <touch-surface-allowlist-path>
#
# Effect:
#   - Creates branch `harness/<run-id>/sprint_<N>` off main HEAD if missing.
#   - Adds worktree at `.worktrees/harness/<run-id>/sprint_<N>/`.
#   - Installs pre-commit hooks via install_worktree_hooks.sh.
#   - Symlinks the *primary repo's* `harness/runs/<run-id>` into the worktree at
#     the same path, so the generator writes sentinels back to the primary
#     repo where the orchestrator polls them.
#   - Prints the worktree absolute path on stdout.

set -euo pipefail

RUN_ID="${1:?usage: worktree_up.sh <run-id> <sprint-N> <allowlist>}"
SPRINT_N="${2:?usage: worktree_up.sh <run-id> <sprint-N> <allowlist>}"
ALLOWLIST="${3:?usage: worktree_up.sh <run-id> <sprint-N> <allowlist>}"

REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_REL=".worktrees/harness/${RUN_ID}/sprint_${SPRINT_N}"
WORKTREE_ABS="${REPO_ROOT}/${WORKTREE_REL}"
BRANCH="harness/${RUN_ID}/sprint_${SPRINT_N}"
PRIMARY_RUN_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}"

if [ ! -d "$PRIMARY_RUN_DIR" ]; then
    echo "worktree_up: primary run dir missing: $PRIMARY_RUN_DIR" >&2
    echo "  (init_sprint.sh must be invoked before worktree_up.sh)" >&2
    exit 2
fi

# If the worktree already exists, surface it without re-creating.
if [ -d "$WORKTREE_ABS" ]; then
    echo "$WORKTREE_ABS"
    exit 0
fi

# Branch off main (not the current branch — the orchestrator may have its own work).
BASE_SHA=$(git rev-parse main)

mkdir -p "$(dirname "$WORKTREE_ABS")"
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git worktree add "$WORKTREE_ABS" "$BRANCH"
else
    git worktree add -b "$BRANCH" "$WORKTREE_ABS" "$BASE_SHA"
fi

# Install hooks.
bash "${REPO_ROOT}/harness/lib/install_worktree_hooks.sh" "$WORKTREE_ABS" "$ALLOWLIST"

# Link the run dir into the worktree at the *same relative path* so paths
# referenced from the generator's tool surface resolve identically inside the
# worktree and from the orchestrator. Use a symlink, not a separate copy.
WORKTREE_RUN_DIR="${WORKTREE_ABS}/harness/runs/${RUN_ID}"
mkdir -p "$(dirname "$WORKTREE_RUN_DIR")"
if [ ! -L "$WORKTREE_RUN_DIR" ] && [ ! -e "$WORKTREE_RUN_DIR" ]; then
    ln -s "$PRIMARY_RUN_DIR" "$WORKTREE_RUN_DIR"
fi

echo "$WORKTREE_ABS"
