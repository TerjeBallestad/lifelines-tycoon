#!/usr/bin/env python3
"""Pre-commit guard: reject any staged file that is not in the allowlist.

Required env:
  HARNESS_TOUCH_SURFACE_FILE — path to a newline-separated list of glob patterns.

Globs use shell-style pathname semantics extended with `**`:
  features/economy/**       — matches every path under features/economy
  features/**/*.tres        — matches any .tres file under features
  features/*.gd             — matches one-level .gd files in features/

Exit codes:
  0 — all staged files are within the allowlist
  1 — at least one staged file is outside; offenders printed to stderr
  2 — bad usage / missing env
"""
from __future__ import annotations
import os
import re
import subprocess
import sys
from pathlib import Path


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Translate a shell-style glob (with ** support) to an anchored regex.

    `**` matches any number of path components (including zero) — including
    slashes. `*` matches any character sequence within a single path component
    (no slashes). `?` matches a single non-slash character. All other regex
    metachars are escaped.
    """
    parts: list[str] = []
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if ch == "*":
            if i + 1 < len(pattern) and pattern[i + 1] == "*":
                parts.append(".*")
                i += 2
                # Optional trailing slash after `**/` collapses cleanly.
                if i < len(pattern) and pattern[i] == "/":
                    i += 1
            else:
                parts.append("[^/]*")
                i += 1
        elif ch == "?":
            parts.append("[^/]")
            i += 1
        elif ch in r".^$+(){}|\\[]":
            parts.append("\\" + ch)
            i += 1
        else:
            parts.append(re.escape(ch) if not ch.isalnum() and ch not in "/_-" else ch)
            i += 1
    return re.compile("^" + "".join(parts) + "$")


def _load_patterns(path: Path) -> list[str]:
    patterns: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line:
            patterns.append(line)
    return patterns


def _staged_files() -> list[str]:
    """Return staged files relative to repo root."""
    head_present = (
        subprocess.run(
            ["git", "rev-parse", "--verify", "HEAD"],
            capture_output=True,
        ).returncode
        == 0
    )
    if head_present:
        cmd = ["git", "diff", "--name-only", "--cached"]
    else:
        cmd = ["git", "ls-files", "--cached"]
    out = subprocess.check_output(cmd, text=True)
    return [ln for ln in out.splitlines() if ln.strip()]


def main(argv: list[str]) -> int:
    allowlist_env = os.environ.get("HARNESS_TOUCH_SURFACE_FILE")
    if not allowlist_env:
        print("check_touch: HARNESS_TOUCH_SURFACE_FILE not set", file=sys.stderr)
        return 2
    allowlist_path = Path(allowlist_env)
    if not allowlist_path.is_file():
        print(
            f"check_touch: allowlist file not found: {allowlist_path}",
            file=sys.stderr,
        )
        return 2

    patterns = _load_patterns(allowlist_path)
    if not patterns:
        print(
            "check_touch: allowlist is empty — every staged file would be rejected",
            file=sys.stderr,
        )
        return 2

    compiled = [_glob_to_regex(p) for p in patterns]
    staged = _staged_files()
    if not staged:
        return 0

    offenders = [f for f in staged if not any(rx.match(f) for rx in compiled)]
    if offenders:
        print(
            "check_touch: staged files outside touch-surface allowlist:",
            file=sys.stderr,
        )
        for f in offenders:
            print(f"  {f}", file=sys.stderr)
        print(f"Allowlist: {allowlist_path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
