#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from git_integration import (  # noqa: E402
    archive_sprint_branch,
    cherry_pick_sprint,
    collect_sprint_commits,
    current_sha,
    ensure_integration_branch,
    git,
    sprint_branch,
)


def write(repo: Path, rel: str, text: str) -> None:
    path = repo / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class TestGitIntegration(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        git(self.repo, "init", "-b", "main")
        git(self.repo, "config", "user.email", "harness@example.test")
        git(self.repo, "config", "user.name", "Harness Test")
        write(self.repo, "file.txt", "base\n")
        git(self.repo, "add", "file.txt")
        git(self.repo, "commit", "-m", "base")
        self.base_sha = current_sha(self.repo)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_current_sha_returns_head(self) -> None:
        expected = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        self.assertEqual(current_sha(self.repo), expected)

    def test_ensure_integration_branch_creates_branch_at_base(self) -> None:
        branch = ensure_integration_branch(self.repo, "run-1", self.base_sha)
        self.assertEqual(branch, "harness/run-1/integration")
        self.assertEqual(git(self.repo, "rev-parse", branch).stdout.strip(), self.base_sha)
        self.assertEqual(ensure_integration_branch(self.repo, "run-1", self.base_sha), branch)

    def test_sprint_branch_name(self) -> None:
        self.assertEqual(sprint_branch("run-1", 2), "harness/run-1/sprint_2")

    def test_collect_sprint_commits_returns_oldest_to_newest(self) -> None:
        branch = sprint_branch("run-1", 1)
        git(self.repo, "switch", "-c", branch, self.base_sha)
        write(self.repo, "a.txt", "a\n")
        git(self.repo, "add", "a.txt")
        git(self.repo, "commit", "-m", "a")
        first = current_sha(self.repo)
        write(self.repo, "b.txt", "b\n")
        git(self.repo, "add", "b.txt")
        git(self.repo, "commit", "-m", "b")
        second = current_sha(self.repo)
        self.assertEqual(collect_sprint_commits(self.repo, self.base_sha, branch), [first, second])

    def test_cherry_pick_sprint_handles_empty_and_success(self) -> None:
        integration = ensure_integration_branch(self.repo, "run-1", self.base_sha)
        self.assertEqual(cherry_pick_sprint(self.repo, integration, []), "NO_COMMITS")
        branch = sprint_branch("run-1", 1)
        git(self.repo, "switch", "-c", branch, self.base_sha)
        write(self.repo, "feature.txt", "feature\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "feature")
        commits = collect_sprint_commits(self.repo, self.base_sha, branch)
        self.assertEqual(cherry_pick_sprint(self.repo, integration, commits), "OK")
        self.assertEqual((self.repo / "feature.txt").read_text(), "feature\n")

    def test_cherry_pick_sprint_returns_conflict(self) -> None:
        integration = ensure_integration_branch(self.repo, "run-1", self.base_sha)
        branch = sprint_branch("run-1", 1)
        git(self.repo, "switch", "-c", branch, self.base_sha)
        write(self.repo, "file.txt", "sprint\n")
        git(self.repo, "add", "file.txt")
        git(self.repo, "commit", "-m", "sprint change")
        commits = collect_sprint_commits(self.repo, self.base_sha, branch)
        git(self.repo, "switch", integration)
        write(self.repo, "file.txt", "integration\n")
        git(self.repo, "add", "file.txt")
        git(self.repo, "commit", "-m", "integration change")
        self.assertEqual(cherry_pick_sprint(self.repo, integration, commits), "CONFLICT")
        self.assertNotEqual(git(self.repo, "status", "--porcelain").stdout.strip(), "")

    def test_archive_sprint_branch_creates_tag(self) -> None:
        branch = sprint_branch("run-1", 1)
        git(self.repo, "switch", "-c", branch, self.base_sha)
        tag = archive_sprint_branch(self.repo, "run-1", 1, branch)
        self.assertEqual(tag, "harness-archive/run-1/1")
        self.assertEqual(git(self.repo, "rev-parse", tag).stdout.strip(), self.base_sha)


if __name__ == "__main__":
    unittest.main()
