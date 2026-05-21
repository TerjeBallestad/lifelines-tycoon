#!/usr/bin/env python3
"""Tests for harness/lib/check_touch.py — invoked as a subprocess against a temp git repo."""
from __future__ import annotations
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (Path(__file__).parent.parent / "lib" / "check_touch.py").resolve()


class TouchCheckHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.com")
        self._git("config", "user.name", "Test")

    def tearDown(self) -> None:
        subprocess.run(["rm", "-rf", self.tmp], check=False)

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", self.tmp, *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def _stage(self, relpath: str, content: str = "x\n") -> None:
        p = Path(self.tmp) / relpath
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        self._git("add", relpath)

    def _allowlist(self, lines: list[str]) -> str:
        p = Path(self.tmp) / ".allow"
        p.write_text("\n".join(lines) + "\n")
        return str(p)

    def _run(self, allowlist: str) -> subprocess.CompletedProcess:
        env = {**os.environ, "HARNESS_TOUCH_SURFACE_FILE": allowlist}
        return subprocess.run(
            ["python3", str(SCRIPT)],
            cwd=self.tmp,
            env=env,
            capture_output=True,
            text=True,
        )

    def test_passes_when_all_staged_in_allowlist(self) -> None:
        self._stage("features/economy/diagnostics/foo.tres")
        result = self._run(self._allowlist(["features/economy/diagnostics/*.tres"]))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fails_when_staged_outside_allowlist(self) -> None:
        self._stage("autoload/event_bus.gd")
        result = self._run(self._allowlist(["features/economy/**"]))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("autoload/event_bus.gd", result.stderr)

    def test_recursive_glob_matches(self) -> None:
        self._stage("features/economy/diagnostics/sub/deep.tres")
        result = self._run(self._allowlist(["features/economy/**"]))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_blank_lines_ignored(self) -> None:
        self._stage("features/x.gd")
        result = self._run(self._allowlist(["", "features/**", "  "]))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_allowlist_var_fails_loud(self) -> None:
        self._stage("features/x.gd")
        result = subprocess.run(
            ["python3", str(SCRIPT)],
            cwd=self.tmp,
            env={k: v for k, v in os.environ.items() if k != "HARNESS_TOUCH_SURFACE_FILE"},
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HARNESS_TOUCH_SURFACE_FILE", result.stderr)


if __name__ == "__main__":
    unittest.main()
