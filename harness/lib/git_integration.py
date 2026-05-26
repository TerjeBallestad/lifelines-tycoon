#!/usr/bin/env python3
"""Git helpers for Phase 6 sprint integration."""
from __future__ import annotations

import subprocess
from pathlib import Path

__all__ = [
    "archive_sprint_branch",
    "cherry_pick_sprint",
    "collect_sprint_commits",
    "current_sha",
    "ensure_integration_branch",
    "git",
    "sprint_branch",
]


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def current_sha(repo: Path) -> str:
    return git(repo, "rev-parse", "HEAD").stdout.strip()


def ensure_integration_branch(repo: Path, run_id: str, base_sha: str) -> str:
    branch = f"harness/{run_id}/integration"
    existing = git(
        repo,
        "show-ref",
        "--verify",
        "--quiet",
        f"refs/heads/{branch}",
        check=False,
    )
    if existing.returncode == 0:
        return branch
    if existing.returncode != 1:
        existing.check_returncode()

    git(repo, "branch", branch, base_sha)
    return branch


def sprint_branch(run_id: str, sprint: int) -> str:
    return f"harness/{run_id}/sprint_{sprint}"


def collect_sprint_commits(repo: Path, base_sha: str, branch: str) -> list[str]:
    result = git(repo, "rev-list", "--reverse", f"{base_sha}..{branch}")
    return [line for line in result.stdout.splitlines() if line]


def cherry_pick_sprint(repo: Path, integration_branch: str, commits: list[str]) -> str:
    if not commits:
        return "NO_COMMITS"
    _ensure_clean(repo)
    _ensure_no_in_progress_operation(repo)

    git(repo, "switch", integration_branch)
    for commit in commits:
        result = git(repo, "cherry-pick", commit, check=False)
        if result.returncode == 0:
            continue
        if _is_cherry_pick_in_progress(repo):
            return "CONFLICT"
        raise subprocess.CalledProcessError(
            result.returncode,
            result.args,
            output=result.stdout,
            stderr=result.stderr,
        )

    return "OK"


def _ensure_clean(repo: Path) -> None:
    status = git(repo, "status", "--porcelain").stdout.strip()
    if status:
        raise RuntimeError("git worktree must be clean before sprint integration")


def _ensure_no_in_progress_operation(repo: Path) -> None:
    git_dir = Path(git(repo, "rev-parse", "--git-dir").stdout.strip())
    if not git_dir.is_absolute():
        git_dir = repo / git_dir
    markers = ["CHERRY_PICK_HEAD", "REBASE_HEAD", "MERGE_HEAD", "BISECT_LOG"]
    present = [marker for marker in markers if (git_dir / marker).exists()]
    if present:
        raise RuntimeError(f"git operation in progress: {', '.join(present)}")


def _is_cherry_pick_in_progress(repo: Path) -> bool:
    git_dir = Path(git(repo, "rev-parse", "--git-dir").stdout.strip())
    if not git_dir.is_absolute():
        git_dir = repo / git_dir
    return (git_dir / "CHERRY_PICK_HEAD").exists()


def archive_sprint_branch(repo: Path, run_id: str, sprint: int, branch: str) -> str:
    tag = f"harness-archive/{run_id}/{sprint}"
    git(repo, "tag", "-f", tag, branch)
    return tag
