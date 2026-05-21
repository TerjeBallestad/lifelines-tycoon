#!/usr/bin/env python3
"""Tests for harness/lib/install_worktree_hooks.sh."""
from __future__ import annotations
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (Path(__file__).parent.parent / "lib" / "install_worktree_hooks.sh").resolve()


class InstallHookHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.com")
        self._git("config", "user.name", "Test")
        (Path(self.tmp) / "a.txt").write_text("a\n")
        self._git("add", "a.txt")
        self._git("commit", "-q", "-m", "baseline")
        self.allowlist = Path(self.tmp) / ".touch_allow"
        self.allowlist.write_text("features/**\n")

    def tearDown(self) -> None:
        subprocess.run(["rm", "-rf", self.tmp], check=False)

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", self.tmp, *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def _install(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(SCRIPT), self.tmp, str(self.allowlist)],
            capture_output=True, text=True,
        )

    def test_install_succeeds(self) -> None:
        r = self._install()
        self.assertEqual(r.returncode, 0, r.stderr)
        hook = Path(self.tmp) / ".git" / "hooks" / "pre-commit"
        self.assertTrue(hook.exists())
        self.assertTrue(os.access(hook, os.X_OK), "hook must be executable")

    def test_hook_blocks_offending_commit(self) -> None:
        self._install()
        (Path(self.tmp) / "autoload" ).mkdir()
        (Path(self.tmp) / "autoload" / "x.gd").write_text("extends Node\n")
        self._git("add", "autoload/x.gd")
        r = subprocess.run(
            ["git", "-C", self.tmp, "commit", "-m", "bad"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(r.returncode, 0)
        # Touch-surface check should have fired.
        self.assertIn("touch-surface", r.stderr + r.stdout)

    def test_hook_allows_allowed_commit(self) -> None:
        self._install()
        (Path(self.tmp) / "features").mkdir()
        (Path(self.tmp) / "features" / "x.gd").write_text("extends Node\nfunc f() -> int:\n\treturn 1\n")
        self._git("add", "features/x.gd")
        r = subprocess.run(
            ["git", "-C", self.tmp, "commit", "-m", "good"],
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)


if __name__ == "__main__":
    unittest.main()
