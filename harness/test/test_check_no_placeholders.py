#!/usr/bin/env python3
"""Tests for harness/lib/check_no_placeholders.sh."""
from __future__ import annotations
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (Path(__file__).parent.parent / "lib" / "check_no_placeholders.sh").resolve()


class PlaceholderHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.com")
        self._git("config", "user.name", "Test")
        # Establish a baseline commit so `git diff --cached` works normally.
        (Path(self.tmp) / ".gitkeep").write_text("")
        self._git("add", ".gitkeep")
        self._git("commit", "-q", "-m", "baseline")

    def tearDown(self) -> None:
        subprocess.run(["rm", "-rf", self.tmp], check=False)

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", self.tmp, *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def _stage(self, relpath: str, content: str) -> None:
        p = Path(self.tmp) / relpath
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        self._git("add", relpath)

    def _run(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(SCRIPT)], cwd=self.tmp,
            capture_output=True, text=True,
        )

    def test_clean_file_passes(self) -> None:
        self._stage("features/x.gd", "extends Node\n\nfunc foo() -> int:\n\treturn 1\n")
        self.assertEqual(self._run().returncode, 0)

    def test_todo_comment_rejected(self) -> None:
        self._stage("features/x.gd", "# TODO: write this\nextends Node\n")
        r = self._run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("TODO", r.stderr)

    def test_fixme_rejected(self) -> None:
        self._stage("features/x.gd", "extends Node\n# FIXME hack\n")
        self.assertNotEqual(self._run().returncode, 0)

    def test_gdscript_pass_body_rejected(self) -> None:
        self._stage("features/x.gd", "extends Node\n\nfunc bar() -> void:\n\tpass\n")
        r = self._run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("pass", r.stderr)

    def test_python_raise_notimplemented_rejected(self) -> None:
        self._stage("features/x.py", "def bar():\n    raise NotImplementedError\n")
        self.assertNotEqual(self._run().returncode, 0)

    def test_stub_word_rejected(self) -> None:
        self._stage("features/x.gd", "# stub for later\nextends Node\n")
        self.assertNotEqual(self._run().returncode, 0)

    def test_unstaged_changes_ignored(self) -> None:
        # Modify a file but don't `git add` it. The hook only sees staged changes.
        p = Path(self.tmp) / "loose.gd"
        p.write_text("# TODO\n")
        self.assertEqual(self._run().returncode, 0)


if __name__ == "__main__":
    unittest.main()
