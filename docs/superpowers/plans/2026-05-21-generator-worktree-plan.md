# Generator + Worktree Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the single-agent build loop. An operator runs `harness/run_generator.sh` with a sprint goal + touch-surface allowlist; the script creates an isolated git worktree, scaffolds a contract.md, spawns a Sonnet 4.6 `claude -p` subprocess with the generator system prompt, polls for a `ready` sentinel, and reports a pass/fail verdict derived from the generator's self-check trace scan. Evaluator-driven contract negotiation and adversarial grading remain out of scope (Plan 4).

**Architecture:** Three layers of glue. (1) Bash orchestrator (`run_generator.sh`) owns subprocess lifecycle, worktree creation, sentinel polling, and verdict reporting. (2) Python `harness/lib/` modules own structured concerns: contract parsing, trace scanning, pre-commit guard logic, sprint dir scaffolding. (3) Generator-side helpers are pure CLI: `sprint_smoke.sh` re-uses Plan 1's `scripted_player.py` against a sprint-supplied plan, and `check_touch.sh` / `check_no_placeholders.sh` run as worktree pre-commit hooks. Generator's tool surface is plain Read / Edit / Write / Bash inside its worktree; no agent spawning, no web fetch. All run artifacts live in `harness/runs/<run-id>/sprint_<N>/`, mirroring spec §5.1.

**Tech Stack:** Bash 3+ orchestrator, Python 3.11+ stdlib (`unittest`, `subprocess`, `argparse`), Godot 4.5 + GUT for engine-side smoke (re-used from Plan 1), `claude` CLI (`claude -p` subprocess invocation), `git worktree`. No third-party Python deps.

**Plan position:** Plan 3 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11. Depends on Plan 1 (AgentBridge + scripted player). Required input for Plan 4 (evaluator can replace the operator-authored contract with negotiated contract).

---

## File Structure

**Files created:**

```
harness/
├── run_generator.sh                                   # NEW — single-agent orchestrator
├── prompts/
│   └── generator.md                                   # NEW — Sonnet 4.6 system prompt
├── lib/
│   ├── check_touch.sh                                 # NEW — touch-surface allowlist enforcer
│   ├── check_no_placeholders.sh                       # NEW — TODO/stub/pass-only-body rejecter
│   ├── install_worktree_hooks.sh                      # NEW — writes .git/hooks/pre-commit
│   ├── worktree_up.sh                                 # NEW — git worktree add + hook install
│   ├── init_sprint.sh                                 # NEW — sprint dir scaffolder
│   ├── sprint_smoke.sh                                # NEW — runs scripted player + trace scan
│   ├── contract_schema.py                             # NEW — parse contract.md + extract verifier items
│   └── scan_contract_trace.py                         # NEW — evaluate [trace] items against trace.jsonl
├── runs/                                              # NEW — per-run artifacts (gitignored)
│   └── .gitkeep
└── test/
    ├── test_contract_schema.py                        # NEW — unittest
    ├── test_scan_contract_trace.py                    # NEW — unittest
    ├── test_check_touch.py                            # NEW — unittest driving the bash helper
    ├── test_check_no_placeholders.py                  # NEW — unittest driving the bash helper
    ├── test_install_worktree_hooks.py                 # NEW — unittest
    ├── test_init_sprint.py                            # NEW — unittest
    └── smoke_generator.sh                             # NEW — end-to-end dry-run integration
```

**Files modified:**

```
.gitignore                                             # ignore harness/runs/ + .worktrees/
harness/README.md                                      # status table: Plan 3 done; protocol notes
```

**Files deleted:** none. No game-code or autoload changes — Plan 3 is pure harness orchestration.

---

## Conventions used by this plan

- **Run id**: `YYYYMMDD-HHMMSS-<short-hex>`, e.g. `20260521-141832-3f9a1c`. Generator never picks the id; the orchestrator does.
- **Worktree path**: `.worktrees/harness/<run-id>/sprint_<N>/` (mirrors spec §2 + §4.4).
- **Worktree branch**: `harness/<run-id>/sprint_<N>`, branched from `main` HEAD at run start (per spec §4.4).
- **Sprint dir**: `harness/runs/<run-id>/sprint_<N>/` (mirrors spec §5.1).
- **Sentinel**: `harness/runs/<run-id>/sprint_<N>/ready` — empty file written by generator on completion. The same path is reachable from inside the worktree because `harness/runs/` is symlinked into the worktree by `worktree_up.sh` (see Task 7).
- **Bash style**: `set -euo pipefail` at the top of every script. Subshell errors fail loud.
- **Python style**: stdlib only. Each module ships with a unittest suite under `harness/test/`.
- **Commit style**: Conventional Commits, matches Plans 1–2: `feat(harness):`, `feat(lib):`, `test(harness):`, etc.

---

## Task 1: Repo scaffolding + .gitignore + README status bump

**Files:**
- Create: `harness/prompts/.gitkeep`
- Create: `harness/runs/.gitkeep`
- Modify: `.gitignore`
- Modify: `harness/README.md`

- [ ] **Step 1: Create empty subdirectories**

```bash
mkdir -p harness/prompts harness/runs
touch harness/prompts/.gitkeep harness/runs/.gitkeep
```

- [ ] **Step 2: Append to `.gitignore`**

Append the following lines to the existing `.gitignore` (preserve existing content):

```
# Harness Plan 3 runtime
/.worktrees/
harness/runs/*/
!harness/runs/.gitkeep
```

The pattern keeps the `.gitkeep` (so the empty dir is tracked) but ignores every concrete `<run-id>/` subdirectory.

Verify:

```bash
grep -q '^/.worktrees/$' .gitignore || { echo "missing .worktrees ignore"; exit 1; }
grep -q '^harness/runs/\*/$' .gitignore || { echo "missing runs ignore"; exit 1; }
```

- [ ] **Step 3: Update `harness/README.md` status row**

In the Status table, change Plan 3's status from `pending` to `🚧 in progress`:

```markdown
| 3 | Generator agent + worktree loop | 🚧 in progress |
```

(Final flip to `✅ done` happens in Task 12.)

- [ ] **Step 4: Commit**

```bash
git add harness/prompts/.gitkeep harness/runs/.gitkeep .gitignore harness/README.md
git commit -m "feat(harness): scaffold Plan 3 dirs + gitignore runtime artifacts"
```

---

## Task 2: Contract schema parser

The contract is plain Markdown with `[test]`, `[trace]`, `[judge]` checklist items and an explicit `Status:` line. The parser is the single source of truth for what the generator must satisfy. Spec §4.5's contract shape is the canonical reference.

**Files:**
- Create: `harness/lib/contract_schema.py`
- Create: `harness/test/test_contract_schema.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_contract_schema.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/contract_schema.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_schema import (  # noqa: E402
    parse_contract,
    Contract,
    ContractItem,
    ContractSchemaError,
)


VALID = """# Sprint 1 Contract

## Done means
- [test] `test/harness/sprint_1_noop.gd::test_runs` passes
- [trace] events where ev=diagnostic_completed and id=diag_noop count >= 1
- [judge] freeplay run text mentions "Elling" specifically

## Rubric coverage
Axis 2 (Decision Density): primary
Axis 1 (Theme): touched

## Forbidden side-effects
- baseline axis 5 must hold

## Status: AGREED
"""

NEGOTIATING = VALID.replace("## Status: AGREED", "## Status: NEGOTIATING")
ONLY_JUDGE = """# Sprint X Contract

## Done means
- [judge] looks good

## Status: AGREED
"""


class TestParseContract(unittest.TestCase):
    def test_parses_agreed(self) -> None:
        c = parse_contract(VALID)
        self.assertEqual(c.status, "AGREED")
        self.assertEqual(len(c.items), 3)

    def test_item_types_extracted(self) -> None:
        c = parse_contract(VALID)
        kinds = [i.kind for i in c.items]
        self.assertEqual(sorted(kinds), ["judge", "test", "trace"])

    def test_trace_body_preserved(self) -> None:
        c = parse_contract(VALID)
        trace_items = [i for i in c.items if i.kind == "trace"]
        self.assertEqual(len(trace_items), 1)
        self.assertIn("diagnostic_completed", trace_items[0].body)

    def test_negotiating_status(self) -> None:
        c = parse_contract(NEGOTIATING)
        self.assertEqual(c.status, "NEGOTIATING")

    def test_no_status_line_rejected(self) -> None:
        with self.assertRaises(ContractSchemaError):
            parse_contract("# Sprint Y\n\n## Done means\n- [test] x\n")

    def test_pure_judge_contract_rejected(self) -> None:
        # Spec §6.2: contracts must have ≥50% test/trace items.
        with self.assertRaises(ContractSchemaError):
            parse_contract(ONLY_JUDGE)

    def test_unknown_item_kind_rejected(self) -> None:
        bad = "# X\n\n## Done means\n- [vibes] x\n\n## Status: AGREED\n"
        with self.assertRaises(ContractSchemaError):
            parse_contract(bad)

    def test_no_done_items_rejected(self) -> None:
        bad = "# X\n\n## Done means\n\n## Status: AGREED\n"
        with self.assertRaises(ContractSchemaError):
            parse_contract(bad)


class TestParseContractFile(unittest.TestCase):
    def test_round_trip_from_file(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
            fh.write(VALID)
            path = fh.name
        c = Contract.from_file(path)
        self.assertEqual(c.status, "AGREED")
        self.assertEqual(len(c.items), 3)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_contract_schema.py
```

Expected: ImportError / ModuleNotFoundError on `contract_schema`.

- [ ] **Step 3: Implement `harness/lib/contract_schema.py`**

```python
"""Parse and validate sprint contract.md files.

Schema (per spec §4.5):
- Markdown document
- "## Done means" section with checklist items, each prefixed by [test], [trace], or [judge]
- "## Status: AGREED | NEGOTIATING" line
- Contracts with no test/trace items are rejected (spec §6.2: "Vague criteria → vague critique")
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


VALID_KINDS = ("test", "trace", "judge")
VALID_STATUSES = ("AGREED", "NEGOTIATING")

_DONE_MEANS_HEADING = re.compile(r"^##\s+Done means\s*$", re.IGNORECASE)
_NEXT_HEADING = re.compile(r"^##\s+\S")
_ITEM_LINE = re.compile(r"^-\s*\[(?P<kind>[a-z]+)\]\s*(?P<body>.+?)\s*$")
_STATUS_LINE = re.compile(r"^##\s+Status:\s*(?P<status>\S+)\s*$", re.IGNORECASE)


class ContractSchemaError(ValueError):
    """Raised when a contract.md violates the schema."""


@dataclass(frozen=True)
class ContractItem:
    kind: str   # one of VALID_KINDS
    body: str   # everything after the `[kind]` tag


@dataclass(frozen=True)
class Contract:
    items: tuple[ContractItem, ...]
    status: str
    raw: str = field(default="", repr=False)

    @classmethod
    def from_file(cls, path: str | Path) -> "Contract":
        with open(path) as fh:
            return parse_contract(fh.read())

    def items_by_kind(self, kind: str) -> tuple[ContractItem, ...]:
        return tuple(i for i in self.items if i.kind == kind)


def parse_contract(text: str) -> Contract:
    lines = text.splitlines()
    items = _extract_done_items(lines)
    status = _extract_status(lines)
    _validate(items, status)
    return Contract(items=tuple(items), status=status, raw=text)


def _extract_done_items(lines: list[str]) -> list[ContractItem]:
    in_done = False
    items: list[ContractItem] = []
    for ln in lines:
        if _DONE_MEANS_HEADING.match(ln):
            in_done = True
            continue
        if in_done and _NEXT_HEADING.match(ln):
            in_done = False
        if not in_done:
            continue
        m = _ITEM_LINE.match(ln)
        if m:
            items.append(ContractItem(kind=m.group("kind"), body=m.group("body")))
    return items


def _extract_status(lines: list[str]) -> str:
    for ln in lines:
        m = _STATUS_LINE.match(ln)
        if m:
            return m.group("status").upper()
    raise ContractSchemaError("contract is missing a '## Status:' line")


def _validate(items: Iterable[ContractItem], status: str) -> None:
    items = tuple(items)
    if status not in VALID_STATUSES:
        raise ContractSchemaError(
            f"status must be one of {VALID_STATUSES}, got {status!r}"
        )
    if not items:
        raise ContractSchemaError("contract has no items under '## Done means'")
    for it in items:
        if it.kind not in VALID_KINDS:
            raise ContractSchemaError(
                f"unknown item kind: [{it.kind}] — expected one of {VALID_KINDS}"
            )
    # Spec §6.2: ≥50% test/trace required.
    rigorous = sum(1 for i in items if i.kind in ("test", "trace"))
    if rigorous * 2 < len(items):
        raise ContractSchemaError(
            "contract must have at least 50% [test] or [trace] items "
            "(spec §6.2 — pure-judge contracts produce vague critiques)"
        )
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_contract_schema.py
```

Expected: `OK` — 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/contract_schema.py harness/test/test_contract_schema.py
git commit -m "feat(lib): contract.md parser + schema validator"
```

---

## Task 3: Trace-item scanner

A small DSL evaluating `[trace]` body lines against a `trace.jsonl` produced by `scripted_player.py`. Two rule forms cover spec needs:

1. `events where <field>=<value> [and <field>=<value> ...] count <op> <int>` — counts events matching all conjunctive equalities.
2. `events where <field>=<value> ... must exist` — sugar for `count >= 1`.

No regex, no jq dependency, no jsonpath. Anything fancier is rejected so contracts stay parseable.

**Files:**
- Create: `harness/lib/scan_contract_trace.py`
- Create: `harness/test/test_scan_contract_trace.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_scan_contract_trace.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/scan_contract_trace.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from scan_contract_trace import (  # noqa: E402
    parse_trace_rule,
    evaluate_rule,
    scan_trace_file,
    TraceRuleError,
    TraceResult,
)

SAMPLE_EVENTS = [
    {"ev": "day_started", "day": 1, "t": {"d": 1, "h": 0.0}},
    {"ev": "diagnostic_completed", "id": "diag_psych_eval", "t": {"d": 1, "h": 9.5}},
    {"ev": "diagnostic_completed", "id": "diag_noop", "t": {"d": 1, "h": 12.0}},
    {"ev": "day_started", "day": 2, "t": {"d": 2, "h": 0.0}},
    {"ev": "overskudd_changed", "client": "elling", "v": 42.0, "t": {"d": 2, "h": 0.0}},
]


class TestParseTraceRule(unittest.TestCase):
    def test_count_ge_rule(self) -> None:
        r = parse_trace_rule("events where ev=diagnostic_completed count >= 1")
        self.assertEqual(r.predicates, {"ev": "diagnostic_completed"})
        self.assertEqual(r.op, ">=")
        self.assertEqual(r.value, 1)

    def test_conjunctive_predicates(self) -> None:
        r = parse_trace_rule("events where ev=diagnostic_completed and id=diag_noop count >= 1")
        self.assertEqual(r.predicates, {"ev": "diagnostic_completed", "id": "diag_noop"})

    def test_must_exist_sugar(self) -> None:
        r = parse_trace_rule("events where ev=day_started and day=2 must exist")
        self.assertEqual(r.op, ">=")
        self.assertEqual(r.value, 1)

    def test_unknown_op_rejected(self) -> None:
        with self.assertRaises(TraceRuleError):
            parse_trace_rule("events where ev=x count ~~ 3")

    def test_missing_count_or_must_rejected(self) -> None:
        with self.assertRaises(TraceRuleError):
            parse_trace_rule("events where ev=x")


class TestEvaluateRule(unittest.TestCase):
    def test_count_ge_pass(self) -> None:
        rule = parse_trace_rule("events where ev=diagnostic_completed count >= 1")
        res = evaluate_rule(rule, SAMPLE_EVENTS)
        self.assertTrue(res.passed)
        self.assertEqual(res.actual_count, 2)

    def test_count_eq_fail(self) -> None:
        rule = parse_trace_rule("events where ev=diagnostic_completed count == 3")
        res = evaluate_rule(rule, SAMPLE_EVENTS)
        self.assertFalse(res.passed)
        self.assertEqual(res.actual_count, 2)

    def test_conjunctive_predicate(self) -> None:
        rule = parse_trace_rule(
            "events where ev=diagnostic_completed and id=diag_noop must exist"
        )
        res = evaluate_rule(rule, SAMPLE_EVENTS)
        self.assertTrue(res.passed)
        self.assertEqual(res.actual_count, 1)


class TestScanTraceFile(unittest.TestCase):
    def _write(self, events: list[dict]) -> str:
        f = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
        for e in events:
            f.write(json.dumps(e) + "\n")
        f.close()
        return f.name

    def test_all_rules_pass(self) -> None:
        path = self._write(SAMPLE_EVENTS)
        rules_text = [
            "events where ev=day_started count >= 2",
            "events where ev=diagnostic_completed and id=diag_noop must exist",
        ]
        results = scan_trace_file(path, rules_text)
        self.assertTrue(all(r.passed for r in results))

    def test_one_rule_fails(self) -> None:
        path = self._write(SAMPLE_EVENTS)
        rules_text = [
            "events where ev=day_started count >= 5",   # only 2 in sample
        ]
        results = scan_trace_file(path, rules_text)
        self.assertFalse(results[0].passed)
        self.assertEqual(results[0].actual_count, 2)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_scan_contract_trace.py
```

Expected: ImportError.

- [ ] **Step 3: Implement `harness/lib/scan_contract_trace.py`**

```python
"""Trace-rule DSL + evaluator.

Rule grammar (regex below):
    "events where <k>=<v> [and <k>=<v> ...] count <op> <int>"
    "events where <k>=<v> [and <k>=<v> ...] must exist"

Where <op> ∈ {==, !=, >, >=, <, <=}.

Values compare as strings, except integer-looking values which compare both ways
(matches "day=2" against either int 2 or string "2" in the trace).
"""
from __future__ import annotations
import json
import re
from dataclasses import dataclass
from typing import Iterable


_OP_PATTERN = r"==|!=|>=|<=|>|<"
_RULE_RE = re.compile(
    r"""^\s*events\s+where\s+
        (?P<preds>[a-zA-Z0-9_]+\s*=\s*\S+(?:\s+and\s+[a-zA-Z0-9_]+\s*=\s*\S+)*)
        \s+(?:count\s+(?P<op>""" + _OP_PATTERN + r""")\s+(?P<val>\d+)|must\s+exist)\s*$""",
    re.VERBOSE,
)
_PRED_RE = re.compile(r"([a-zA-Z0-9_]+)\s*=\s*(\S+)")


class TraceRuleError(ValueError):
    """Raised when a trace rule does not parse."""


@dataclass(frozen=True)
class TraceRule:
    predicates: dict
    op: str       # one of ==, !=, >, >=, <, <=
    value: int
    raw: str


@dataclass(frozen=True)
class TraceResult:
    rule: TraceRule
    passed: bool
    actual_count: int
    message: str


def parse_trace_rule(line: str) -> TraceRule:
    m = _RULE_RE.match(line.strip())
    if not m:
        raise TraceRuleError(f"could not parse trace rule: {line!r}")
    preds = dict(_PRED_RE.findall(m.group("preds")))
    if not preds:
        raise TraceRuleError(f"trace rule has no predicates: {line!r}")
    if m.group("op") is not None:
        op = m.group("op")
        val = int(m.group("val"))
    else:
        op = ">="
        val = 1
    return TraceRule(predicates=preds, op=op, value=val, raw=line.strip())


def _predicate_matches(event: dict, key: str, expected: str) -> bool:
    if key not in event:
        return False
    actual = event[key]
    if isinstance(actual, bool):
        return str(actual).lower() == expected.lower()
    if isinstance(actual, (int, float)):
        try:
            return float(actual) == float(expected)
        except ValueError:
            return False
    return str(actual) == expected


def _all_match(event: dict, preds: dict) -> bool:
    return all(_predicate_matches(event, k, v) for k, v in preds.items())


def _compare(actual: int, op: str, expected: int) -> bool:
    return {
        "==": actual == expected,
        "!=": actual != expected,
        ">":  actual >  expected,
        ">=": actual >= expected,
        "<":  actual <  expected,
        "<=": actual <= expected,
    }[op]


def evaluate_rule(rule: TraceRule, events: Iterable[dict]) -> TraceResult:
    count = sum(1 for ev in events if _all_match(ev, rule.predicates))
    passed = _compare(count, rule.op, rule.value)
    return TraceResult(
        rule=rule,
        passed=passed,
        actual_count=count,
        message=f"count={count}, expected {rule.op} {rule.value}",
    )


def scan_trace_file(path: str, rules_text: list[str]) -> list[TraceResult]:
    rules = [parse_trace_rule(r) for r in rules_text]
    events: list[dict] = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue   # tolerate malformed lines; trace_schema covers schema errors elsewhere
    return [evaluate_rule(r, events) for r in rules]
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_scan_contract_trace.py
```

Expected: `OK` — 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/scan_contract_trace.py harness/test/test_scan_contract_trace.py
git commit -m "feat(lib): trace-rule DSL + scan_contract_trace evaluator"
```

---

## Task 4: Touch-surface allowlist enforcer

`check_touch.py` is invoked by the pre-commit hook installed into each worktree. It compares the staged file list against an allowlist of newline-separated globs supplied via `HARNESS_TOUCH_SURFACE_FILE` (a path) and exits non-zero if any staged file falls outside the allowlist.

(Originally drafted in bash with `shopt -s globstar`. Pivoted to Python during implementation to drop the bash 4+ dependency — macOS still ships bash 3.2 by default and we don't want every contributor to install Homebrew bash.)

**Files:**
- Create: `harness/lib/check_touch.py`
- Create: `harness/test/test_check_touch.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_check_touch.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/check_touch.sh — invoked as a subprocess against a temp git repo."""
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_check_touch.py
```

Expected: FAIL — script does not exist (subprocess returns non-zero from python3, output mentions missing file).

- [ ] **Step 3: Implement `harness/lib/check_touch.py`**

```python
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
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x harness/lib/check_touch.py
```

- [ ] **Step 5: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_check_touch.py
```

Expected: `OK` — 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add harness/lib/check_touch.py harness/test/test_check_touch.py
git commit -m "feat(lib): touch-surface allowlist enforcer for pre-commit hook"
```

---

## Task 5: Placeholder-rejecter for staged content

Spec §6.3: "Writes 'TODO' / 'stub' placeholders → Hook blocks. Half-finished implementations are the talk's killer." `check_no_placeholders.sh` scans staged hunks (not whole files — comments in untouched code stay intact) for forbidden patterns.

**Forbidden patterns:**
- `TODO`, `FIXME`, `XXX`, `HACK` (case-sensitive — these are the bug-flag idioms)
- A `.gd` function whose body is literally `pass` followed by nothing else (catches GDScript stubs)
- A Python function whose body is literally `pass`, `...`, or `raise NotImplementedError`
- The bare token `stub` in code lines (case-insensitive, word-boundary)

Comments and documentation are intentionally NOT exempt — a `# TODO` in production code is exactly what we want to block.

**Files:**
- Create: `harness/lib/check_no_placeholders.sh`
- Create: `harness/test/test_check_no_placeholders.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_check_no_placeholders.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_check_no_placeholders.py
```

Expected: FAIL — script missing.

- [ ] **Step 3: Implement `harness/lib/check_no_placeholders.sh`**

```bash
#!/usr/bin/env bash
# Pre-commit guard: reject staged content containing TODO/FIXME/stub/empty-body
# placeholders — half-finished implementations are forbidden (spec §6.3).
#
# Scans only the *added/modified hunks* via `git diff --cached -U0`, not whole files,
# so legitimate unchanged code is never touched.
#
# Exit codes:
#   0 — clean
#   1 — at least one forbidden pattern found; report on stderr

set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "check_no_placeholders: not inside a git work tree" >&2
    exit 2
fi

# Pull staged hunks. `-U0` minimizes surrounding context.
diff=$(git diff --cached -U0)
if [ -z "$diff" ]; then
    exit 0
fi

# Iterate added lines (those starting with '+', but not the '+++' file header).
added=$(printf '%s\n' "$diff" | awk '/^\+\+\+ /{next} /^\+/{print substr($0,2)}')

if [ -z "$added" ]; then
    exit 0
fi

violations=""

# Forbidden literal tokens (case-sensitive).
while IFS= read -r line; do
    case "$line" in
        *TODO*|*FIXME*|*XXX*|*HACK*)
            violations+=$'\n'"  placeholder token: $line"
            ;;
    esac
done <<< "$added"

# Word 'stub' anywhere, case-insensitive.
if printf '%s\n' "$added" | grep -iqE '(^|[^a-zA-Z_])stub([^a-zA-Z_]|$)'; then
    matched=$(printf '%s\n' "$added" | grep -iE '(^|[^a-zA-Z_])stub([^a-zA-Z_]|$)')
    violations+=$'\n'"  'stub' token found in:"$'\n'"$(printf '    %s\n' "$matched")"
fi

# Python raise NotImplementedError (anywhere in added lines).
if printf '%s\n' "$added" | grep -qE 'raise[[:space:]]+NotImplementedError'; then
    violations+=$'\n'"  Python raise NotImplementedError in added lines"
fi

# Python function with pass-only body OR ellipsis-only body.
# We scan the cached file contents of every staged .py file for `def foo(...):\n    (pass|...)` immediately followed by end-of-file or another def/blank.
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in *.py)
        body=$(git show ":$f" 2>/dev/null || true)
        if [ -z "$body" ]; then continue; fi
        if printf '%s\n' "$body" | python3 -c '
import sys, re
src = sys.stdin.read()
# def ...():\n<indent>(pass|...)\n  followed by newline-or-EOF
if re.search(r"^def\s+\w+\s*\([^)]*\)[^:]*:\s*\n(?:\s*[\"\x27].*[\"\x27]\s*\n)?(\s+)(?:pass|\.\.\.)\s*$", src, re.MULTILINE):
    sys.exit(0)
sys.exit(1)
'; then
            violations+=$'\n'"  python placeholder body in $f"
        fi
    ;; esac
done < <(git diff --cached --name-only)

# GDScript function with pass-only body. `func foo() -> X:\n\tpass\n` (and no body lines beyond it).
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in *.gd)
        body=$(git show ":$f" 2>/dev/null || true)
        if [ -z "$body" ]; then continue; fi
        if printf '%s\n' "$body" | python3 -c '
import sys, re
src = sys.stdin.read()
if re.search(r"^func\s+\w+\s*\([^)]*\)[^:]*:\s*\n(?:\s*#[^\n]*\n)?\s+pass\s*$", src, re.MULTILINE):
    sys.exit(0)
sys.exit(1)
'; then
            violations+=$'\n'"  gdscript placeholder body in $f"
        fi
    ;; esac
done < <(git diff --cached --name-only)

if [ -n "$violations" ]; then
    echo "check_no_placeholders: forbidden patterns in staged content:" >&2
    printf '%s\n' "$violations" >&2
    exit 1
fi

exit 0
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x harness/lib/check_no_placeholders.sh
```

- [ ] **Step 5: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_check_no_placeholders.py
```

Expected: `OK` — 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add harness/lib/check_no_placeholders.sh harness/test/test_check_no_placeholders.py
git commit -m "feat(lib): placeholder enforcer rejecting TODO/stub/pass-body"
```

---

## Task 6: Worktree pre-commit hook installer

Installs a pre-commit hook into a worktree's `.git` that chains the two guards plus a fast `git diff --check` whitespace pass.

**Files:**
- Create: `harness/lib/install_worktree_hooks.sh`
- Create: `harness/test/test_install_worktree_hooks.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_install_worktree_hooks.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_install_worktree_hooks.py
```

Expected: FAIL — installer missing.

- [ ] **Step 3: Implement `harness/lib/install_worktree_hooks.sh`**

```bash
#!/usr/bin/env bash
# Install the harness pre-commit hook into the given worktree.
#
# Usage:
#   install_worktree_hooks.sh <worktree-path> <touch-surface-allowlist-path>
#
# The installed hook is a thin trampoline that:
#   1. Runs `git diff --check` (whitespace sanity)
#   2. Sources HARNESS_TOUCH_SURFACE_FILE from the env it sets
#   3. Invokes check_touch.sh and check_no_placeholders.sh from this repo

set -euo pipefail

WORKTREE="${1:?usage: install_worktree_hooks.sh <worktree-path> <allowlist>}"
ALLOWLIST="${2:?usage: install_worktree_hooks.sh <worktree-path> <allowlist>}"

if [ ! -d "$WORKTREE/.git" ] && [ ! -f "$WORKTREE/.git" ]; then
    echo "install_worktree_hooks: $WORKTREE is not a git checkout" >&2
    exit 2
fi

# Resolve absolute paths so the hook works regardless of cwd.
ALLOWLIST_ABS=$(cd "$(dirname "$ALLOWLIST")" && pwd)/$(basename "$ALLOWLIST")
HARNESS_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# `git rev-parse --git-path hooks/pre-commit` resolves the right path whether
# WORKTREE is a primary checkout or a linked worktree (which has a `.git` file
# pointing into the main repo's `.git/worktrees/<name>/`).
HOOK_PATH=$(git -C "$WORKTREE" rev-parse --git-path hooks/pre-commit)
HOOK_DIR=$(dirname "$HOOK_PATH")
mkdir -p "$HOOK_DIR"

cat > "$HOOK_PATH" <<HOOK
#!/usr/bin/env bash
# Auto-generated by harness/lib/install_worktree_hooks.sh — do not edit.
set -euo pipefail

export HARNESS_TOUCH_SURFACE_FILE="${ALLOWLIST_ABS}"

# 1. Whitespace sanity.
git diff --check --cached || { echo "pre-commit: whitespace check failed" >&2; exit 1; }

# 2. Touch-surface allowlist.
python3 "${HARNESS_LIB}/check_touch.py"

# 3. Placeholder / stub rejection.
bash "${HARNESS_LIB}/check_no_placeholders.sh"
HOOK

chmod +x "$HOOK_PATH"
echo "installed pre-commit hook: $HOOK_PATH"
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x harness/lib/install_worktree_hooks.sh
```

- [ ] **Step 5: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_install_worktree_hooks.py
```

Expected: `OK` — 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add harness/lib/install_worktree_hooks.sh harness/test/test_install_worktree_hooks.py
git commit -m "feat(lib): install_worktree_hooks installs pre-commit guard chain"
```

---

## Task 7: Worktree creator

`worktree_up.sh` wraps `git worktree add`, branches from `main`, installs hooks, and links the run-dir into the worktree so the generator can write sentinels under `harness/runs/<id>/sprint_<N>/` from inside the worktree.

**Files:**
- Create: `harness/lib/worktree_up.sh`

(No new tests — covered by Task 11's end-to-end smoke. The script's three concrete responsibilities — worktree create, hook install, run-dir symlink — are each independently testable already.)

- [ ] **Step 1: Write `harness/lib/worktree_up.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x harness/lib/worktree_up.sh
```

- [ ] **Step 3: Manual smoke**

```bash
# In the main repo, dry-run with a fake run-id.
mkdir -p harness/runs/SMOKE-WT/sprint_1
echo "features/economy/**" > /tmp/touch-smoke.allow
bash harness/lib/worktree_up.sh SMOKE-WT 1 /tmp/touch-smoke.allow
ls .worktrees/harness/SMOKE-WT/sprint_1
ls -la .worktrees/harness/SMOKE-WT/sprint_1/harness/runs/SMOKE-WT
git worktree remove --force .worktrees/harness/SMOKE-WT/sprint_1
git branch -D harness/SMOKE-WT/sprint_1
rm -rf harness/runs/SMOKE-WT
```

Expected: prints the absolute worktree path; the listed symlink resolves back to `harness/runs/SMOKE-WT`; cleanup commands succeed.

**Note on `--force`:** the Godot 4.5 editor (and headless imports) auto-generate `.gd.uid` / `.tres.import` sidecars on first access. Linked worktrees inherit these as untracked files, which makes plain `git worktree remove` fail. `--force` is the documented way around it.

**Note on shared hooks (Plan 5 territory):** git's linked-worktree design routes `.git/hooks/` to the *primary* repo, not per-worktree. The Plan 3 generator only runs one sprint at a time, so the shared hook is fine. Plan 5's multi-sprint orchestrator should set `git config extensions.worktreeConfig true` once on the primary repo, then `git config --worktree core.hooksPath <per-worktree-dir>` inside each new worktree before invoking `install_worktree_hooks.sh`.

- [ ] **Step 4: Commit**

```bash
git add harness/lib/worktree_up.sh
git commit -m "feat(lib): worktree_up creates branch + worktree + hooks + run symlink"
```

---

## Task 8: Sprint dir scaffolder

`init_sprint.sh` populates `harness/runs/<run-id>/sprint_<N>/` with a contract template, a `meta.json`, the touch-surface allowlist, and an empty generator session log.

**Files:**
- Create: `harness/lib/init_sprint.sh`
- Create: `harness/test/test_init_sprint.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_init_sprint.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/init_sprint.sh."""
from __future__ import annotations
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (Path(__file__).parent.parent / "lib" / "init_sprint.sh").resolve()


class InitSprintHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        # init_sprint resolves paths relative to a git toplevel.
        subprocess.run(["git", "-C", self.tmp, "init", "-q"], check=True)

    def tearDown(self) -> None:
        subprocess.run(["rm", "-rf", self.tmp], check=False)

    def _run(self, *extra: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(SCRIPT), *extra],
            cwd=self.tmp, capture_output=True, text=True,
        )

    def test_creates_sprint_dir(self) -> None:
        goal = Path(self.tmp) / "goal.md"
        goal.write_text("Add a noop diagnostic\n")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("features/economy/**\n")
        r = self._run(
            "--run-id", "RUN1",
            "--sprint", "1",
            "--goal-file", str(goal),
            "--touch-surface", str(touch),
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        sprint_dir = Path(self.tmp) / "harness/runs/RUN1/sprint_1"
        self.assertTrue(sprint_dir.exists())
        self.assertTrue((sprint_dir / "contract.md").exists())
        self.assertTrue((sprint_dir / "meta.json").exists())
        self.assertTrue((sprint_dir / "touch_surface.allow").exists())
        # generator_session.jsonl created empty so tee can append.
        self.assertTrue((sprint_dir / "generator_session.jsonl").exists())

    def test_meta_records_inputs(self) -> None:
        goal = Path(self.tmp) / "goal.md"
        goal.write_text("Goal text")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("features/**\n")
        self._run(
            "--run-id", "RUN2", "--sprint", "3",
            "--goal-file", str(goal), "--touch-surface", str(touch),
        )
        meta = json.loads((Path(self.tmp) / "harness/runs/RUN2/sprint_3/meta.json").read_text())
        self.assertEqual(meta["run_id"], "RUN2")
        self.assertEqual(meta["sprint"], 3)
        self.assertIn("created_at", meta)
        self.assertIn("base_sha", meta)
        self.assertEqual(meta["touch_surface"], "harness/runs/RUN2/sprint_3/touch_surface.allow")

    def test_contract_template_includes_goal(self) -> None:
        goal = Path(self.tmp) / "g.md"
        goal.write_text("My sprint goal here.\n")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("**\n")
        self._run(
            "--run-id", "RUN3", "--sprint", "1",
            "--goal-file", str(goal), "--touch-surface", str(touch),
        )
        contract = (Path(self.tmp) / "harness/runs/RUN3/sprint_1/contract.md").read_text()
        self.assertIn("My sprint goal here.", contract)
        self.assertIn("## Status: NEGOTIATING", contract)

    def test_idempotent_when_dir_exists(self) -> None:
        goal = Path(self.tmp) / "g.md"
        goal.write_text("Goal")
        touch = Path(self.tmp) / "touch.allow"
        touch.write_text("**\n")
        a = self._run("--run-id", "RX", "--sprint", "1",
                      "--goal-file", str(goal), "--touch-surface", str(touch))
        self.assertEqual(a.returncode, 0)
        # Second invocation must not overwrite contract.md if it has been edited.
        contract = Path(self.tmp) / "harness/runs/RX/sprint_1/contract.md"
        contract.write_text("# Custom contract\n\n## Done means\n- [test] x\n- [trace] events where ev=x must exist\n\n## Status: AGREED\n")
        b = self._run("--run-id", "RX", "--sprint", "1",
                      "--goal-file", str(goal), "--touch-surface", str(touch))
        self.assertEqual(b.returncode, 0)
        self.assertEqual(contract.read_text(), "# Custom contract\n\n## Done means\n- [test] x\n- [trace] events where ev=x must exist\n\n## Status: AGREED\n")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_init_sprint.py
```

Expected: FAIL — script missing.

- [ ] **Step 3: Implement `harness/lib/init_sprint.sh`**

```bash
#!/usr/bin/env bash
# Scaffold a sprint run directory under harness/runs/<run-id>/sprint_<N>/.
#
# Usage:
#   init_sprint.sh --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path>
#
# Creates:
#   contract.md              — template using the goal-file body, Status: NEGOTIATING
#   meta.json                — run metadata (run id, sprint, created_at, base SHA)
#   touch_surface.allow      — copy of the supplied allowlist
#   generator_session.jsonl  — empty file for tee'd subprocess output

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GOAL_FILE=""
TOUCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)        RUN_ID="$2"; shift 2 ;;
        --sprint)        SPRINT_N="$2"; shift 2 ;;
        --goal-file)     GOAL_FILE="$2"; shift 2 ;;
        --touch-surface) TOUCH="$2"; shift 2 ;;
        *) echo "init_sprint: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$RUN_ID" ];    then echo "init_sprint: missing --run-id" >&2;        exit 2; fi
if [ -z "$SPRINT_N" ];  then echo "init_sprint: missing --sprint" >&2;        exit 2; fi
if [ -z "$GOAL_FILE" ]; then echo "init_sprint: missing --goal-file" >&2;     exit 2; fi
if [ -z "$TOUCH" ];     then echo "init_sprint: missing --touch-surface" >&2; exit 2; fi

if [ ! -f "$GOAL_FILE" ]; then echo "init_sprint: goal-file not found: $GOAL_FILE" >&2; exit 2; fi
if [ ! -f "$TOUCH" ];     then echo "init_sprint: touch-surface not found: $TOUCH" >&2; exit 2; fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
mkdir -p "$SPRINT_DIR"

# touch_surface.allow — verbatim copy
cp "$TOUCH" "${SPRINT_DIR}/touch_surface.allow"

# generator_session.jsonl — empty placeholder
[ -f "${SPRINT_DIR}/generator_session.jsonl" ] || : > "${SPRINT_DIR}/generator_session.jsonl"

# meta.json — write only if missing (idempotency for resume)
META="${SPRINT_DIR}/meta.json"
if [ ! -f "$META" ]; then
    BASE_SHA=$(git rev-parse --verify HEAD 2>/dev/null || echo "uncommitted")
    CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "$META" <<JSON
{
  "run_id": "${RUN_ID}",
  "sprint": ${SPRINT_N},
  "created_at": "${CREATED_AT}",
  "base_sha": "${BASE_SHA}",
  "touch_surface": "harness/runs/${RUN_ID}/sprint_${SPRINT_N}/touch_surface.allow",
  "goal_file": "harness/runs/${RUN_ID}/sprint_${SPRINT_N}/goal.md"
}
JSON
fi

# goal.md — verbatim copy (idempotent)
[ -f "${SPRINT_DIR}/goal.md" ] || cp "$GOAL_FILE" "${SPRINT_DIR}/goal.md"

# contract.md — write template only if missing.
CONTRACT="${SPRINT_DIR}/contract.md"
if [ ! -f "$CONTRACT" ]; then
    GOAL_BODY=$(cat "$GOAL_FILE")
    cat > "$CONTRACT" <<MD
# Sprint ${SPRINT_N} Contract

> Generator drafts this, then operator (or Plan 4 evaluator) edits + flips Status.

## Sprint goal

${GOAL_BODY}

## Done means

- [test] <fill in: which .gd test must pass, exact path::test_name>
- [trace] <fill in: trace rule, e.g. "events where ev=diagnostic_completed and id=X count >= 1">

## Rubric coverage

- Axis ?: primary
- Axis ?: touched

## Forbidden side-effects

- <baseline expectations that must continue to hold>

## Status: NEGOTIATING
MD
fi

echo "$SPRINT_DIR"
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x harness/lib/init_sprint.sh
```

- [ ] **Step 5: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_init_sprint.py
```

Expected: `OK` — 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add harness/lib/init_sprint.sh harness/test/test_init_sprint.py
git commit -m "feat(lib): init_sprint scaffolds sprint dir + contract template"
```

---

## Task 9: Sprint smoke driver

`sprint_smoke.sh` is the generator's self-check command. It runs the Plan 1 scripted player against a sprint-supplied action plan, then runs the trace-rule scan from Task 3 against the generated `trace.jsonl`. Exits 0 if every `[trace]` rule in the contract passes; non-zero otherwise.

**Files:**
- Create: `harness/lib/sprint_smoke.sh`

(Tests covered indirectly by the end-to-end smoke in Task 11. The script is thin glue over Plan 1's scripted_player + Task 3's scanner, both of which already have unit tests.)

- [ ] **Step 1: Write `harness/lib/sprint_smoke.sh`**

```bash
#!/usr/bin/env bash
# Run a scripted playtest + scan its trace against the contract's [trace] rules.
#
# Usage:
#   sprint_smoke.sh --run-id <id> --sprint <N> --plan <action-plan.json> \
#                   [--godot <godot-binary>] [--reveal-hidden]
#
# Resolves the contract from harness/runs/<run-id>/sprint_<N>/contract.md and
# extracts every "[trace] events where ... count ... N | must exist" line, then
# evaluates each rule against the trace produced by the playtest. Exits 0 iff
# every rule passes.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
PLAN=""
GODOT="${GODOT_BIN:-}"
REVEAL_FLAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)        RUN_ID="$2"; shift 2 ;;
        --sprint)        SPRINT_N="$2"; shift 2 ;;
        --plan)          PLAN="$2"; shift 2 ;;
        --godot)         GODOT="$2"; shift 2 ;;
        --reveal-hidden) REVEAL_FLAG="--reveal-hidden"; shift ;;
        *) echo "sprint_smoke: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$RUN_ID" ];   then echo "sprint_smoke: missing --run-id" >&2; exit 2; fi
if [ -z "$SPRINT_N" ]; then echo "sprint_smoke: missing --sprint" >&2; exit 2; fi
if [ -z "$PLAN" ];     then echo "sprint_smoke: missing --plan" >&2;   exit 2; fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
CONTRACT="${SPRINT_DIR}/contract.md"
COMMS_DIR="${SPRINT_DIR}/comms"
TRACE_OUT="${SPRINT_DIR}/trace.jsonl"

if [ ! -f "$CONTRACT" ]; then echo "sprint_smoke: no contract.md at $CONTRACT" >&2; exit 2; fi
if [ ! -f "$PLAN" ];     then echo "sprint_smoke: no plan at $PLAN" >&2; exit 2; fi

# Resolve Godot binary if not supplied.
if [ -z "$GODOT" ]; then
    for candidate in \
        "$HOME/Applications/Godot/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot"; do
        if [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
    done
    if [ -z "$GODOT" ] && command -v godot &>/dev/null; then GODOT=godot; fi
fi
if [ -z "$GODOT" ]; then echo "sprint_smoke: cannot find Godot binary" >&2; exit 2; fi

mkdir -p "$COMMS_DIR"

# Run the scripted player from Plan 1.
python3 "${REPO_ROOT}/harness/lib/scripted_player.py" \
    --godot "$GODOT" \
    --project "$REPO_ROOT" \
    --plan "$PLAN" \
    --comms-dir "$COMMS_DIR" \
    --trace-out "$TRACE_OUT" \
    $REVEAL_FLAG

# Evaluate every [trace] rule from contract.md against the trace.
python3 - "$CONTRACT" "$TRACE_OUT" <<'PY'
import sys, re
sys.path.insert(0, "harness/lib")
from contract_schema import parse_contract
from scan_contract_trace import scan_trace_file

contract_path, trace_path = sys.argv[1], sys.argv[2]
with open(contract_path) as fh:
    contract = parse_contract(fh.read())

trace_items = [i for i in contract.items if i.kind == "trace"]
if not trace_items:
    print("sprint_smoke: no [trace] items in contract — nothing to verify")
    sys.exit(0)

rules = [i.body for i in trace_items]
results = scan_trace_file(trace_path, rules)
fails = [r for r in results if not r.passed]
for r in results:
    status = "PASS" if r.passed else "FAIL"
    print(f"  [{status}] {r.rule.raw} — {r.message}")
if fails:
    print(f"sprint_smoke: {len(fails)}/{len(results)} trace rules failed", file=sys.stderr)
    sys.exit(1)
print(f"sprint_smoke: {len(results)} trace rules passed")
PY
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x harness/lib/sprint_smoke.sh
```

- [ ] **Step 3: Commit**

```bash
git add harness/lib/sprint_smoke.sh
git commit -m "feat(lib): sprint_smoke runs scripted player + evaluates trace rules"
```

---

## Task 10: Generator system prompt

The persona doc Sonnet 4.6 loads as `--append-system-prompt`. Talk-derived rules: vague-criteria reject, no self-grading, no half-built code, TDD-first. Anchored against the rubric.

**Files:**
- Create: `harness/prompts/generator.md`

- [ ] **Step 1: Write `harness/prompts/generator.md`**

```markdown
# Generator system prompt

You are the **generator agent** for the Lifelines adversarial harness. Your one job: take a sprint goal and a touch-surface allowlist, ship the smallest, sharpest change that satisfies the contract — and write nothing the evaluator could call "stub", "TODO", or "looks done but isn't".

## Sources of truth (read these every sprint, fresh)

1. `harness/runs/<run-id>/sprint_<N>/goal.md` — what you are building.
2. `harness/runs/<run-id>/sprint_<N>/contract.md` — the executable definition of done. The `## Status:` line must read `AGREED` before you write any production code. If it says `NEGOTIATING`, propose edits in-place and stop. Do not implement against an unagreed contract.
3. `docs/rubric/vision.md` — what Lifelines is and is NOT. Re-read in full each sprint; the project's vocabulary is precise.
4. `docs/rubric/rubric.md` — the 7-axis scoring system that the evaluator (Plan 4 — currently a human operator) will apply. The contract's `## Rubric coverage` section tells you which axes this sprint must move; do not silently regress any other axis.
5. `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` — the project's prototype design spec.

## Workspace

You operate inside a git worktree. Your CWD is the worktree root. Everything you `git add` must match the touch-surface allowlist at `harness/runs/<run-id>/sprint_<N>/touch_surface.allow`; a pre-commit hook rejects anything outside it.

**Forbidden, hook-enforced**: TODO, FIXME, XXX, HACK, the word "stub", GDScript `pass`-body functions, Python `pass`-or-`...`-body functions, `raise NotImplementedError`. If you find yourself about to write any of these, the design is wrong — stop and rethink the smallest implementable next step.

**Off-limits regardless of allowlist**: `autoload/event_bus.gd` (signal stability), `project.godot`'s `[autoload]` block (autoload order), `docs/rubric/` (you do not author your own rubric), `harness/` (you do not modify the harness from within it).

## Tools

Read, Edit, Write, Bash. Inside the worktree only. No web fetch. No agent spawning. No `git push`. No edits to `.git/hooks/`. No bypassing pre-commit (`--no-verify` is banned).

## Per-sprint loop

1. **Read context**: `goal.md`, `contract.md`, `vision.md`, `rubric.md`, the relevant slice of `docs/superpowers/specs/2026-05-18-economy-prototype-design.md`.
2. **Check contract status**. If `NEGOTIATING`, propose minimal edits to `contract.md` (sharper test or trace rule, narrower scope, rubric coverage you can actually move) and STOP. Otherwise proceed.
3. **Plan in checklist** (in `harness/runs/<run-id>/sprint_<N>/plan.md`): bite-sized steps that each end in a commit. Reject any step you cannot describe in 1–2 sentences.
4. **Loop until contract is satisfied**:
   - Write the failing test FIRST (every `[test]` item in the contract gets a real test before any implementation).
   - Run the test from CWD: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://test/... -gexit`.
   - Verify it FAILS for the right reason.
   - Implement the smallest change that makes it pass.
   - Re-run, verify GREEN.
   - For every `[trace]` item, write or update the action plan JSON the contract references, then run `bash harness/lib/sprint_smoke.sh --run-id <id> --sprint <N> --plan <plan-path>`. All trace rules must pass.
   - `git add` only files inside the touch-surface allowlist. Commit with a Conventional Commit message (`feat(...)`, `test(...)`, `fix(...)`).
5. **Final self-check**: re-read the contract. Every `[test]` and `[trace]` item must be demonstrably satisfied. If a `[judge]` item exists, write `harness/runs/<run-id>/sprint_<N>/freeplay_notes.md` with concrete trace citations the human evaluator can verify — do NOT grade yourself.
6. **Signal ready**: `touch harness/runs/<run-id>/sprint_<N>/ready`.

## Anti-sycophancy (you have to internalize this)

You are not paid to ship the sprint. You are paid to ship the smallest verified slice that satisfies the contract. If you cannot satisfy the contract honestly inside the touch surface, write a short note in `harness/runs/<run-id>/sprint_<N>/blocker.md` explaining what's missing — naming specific contract items and what would unblock them — and `touch ... /ready` anyway. The evaluator will mark the sprint REJECT or PIVOT and you will be re-run with a fresh contract. This is the correct outcome. Faking PASS by softening tests, deleting `[trace]` rules, or hand-waving `[judge]` items poisons the harness; do not do it.

## What a good final state looks like

- Every commit on the sprint branch passes pre-commit hooks (no TODO/stub/`pass`-body slips through).
- `bash harness/lib/sprint_smoke.sh ...` exits 0 and prints every `[trace]` rule as `[PASS]`.
- All `[test]` items run green via the local GUT command from the contract.
- `harness/runs/<run-id>/sprint_<N>/ready` exists.
- The diff against `main` is bounded by the touch surface. Verify with `git diff --name-only main...HEAD`.

When you're done, stop. Do not summarize what you built — the evaluator will read the diff.
```

- [ ] **Step 2: Commit**

```bash
git add harness/prompts/generator.md
git commit -m "feat(harness): generator system prompt (TDD, anti-sycophancy, contract-locked)"
```

---

## Task 11: Generator launcher + end-to-end dry-run smoke

`run_generator.sh` is the operator-facing entry point. It composes Tasks 7–10: scaffold sprint dir, create worktree, spawn `claude -p`, poll for `ready`, read verdict. To keep the test deterministic and unbound from API access, the smoke uses `GENERATOR_LIVE=0` (the default) to substitute a dry-run shim that produces a known-good sprint result; `GENERATOR_LIVE=1` invokes the real `claude` CLI.

**Files:**
- Create: `harness/run_generator.sh`
- Create: `harness/test/smoke_generator.sh`

- [ ] **Step 1: Write `harness/run_generator.sh`**

```bash
#!/usr/bin/env bash
# Operator-facing generator launcher.
#
# Usage:
#   ./harness/run_generator.sh \
#       --run-id <id> \
#       --sprint <N> \
#       --goal-file <path-to-goal.md> \
#       --touch-surface <path-to-allowlist> \
#       [--ready-timeout <seconds>]   # default 1800
#
# Effect:
#   1. Scaffold sprint dir via init_sprint.sh.
#   2. Create worktree via worktree_up.sh.
#   3. Spawn the generator subprocess (claude -p in real mode, or a recorded
#      shim in dry-run mode controlled by GENERATOR_LIVE=1).
#   4. Poll for the `ready` sentinel; on appearance, report verdict by reading
#      the sprint's trace.jsonl + contract.md (re-uses sprint_smoke logic).
#   5. Print the worktree path so the operator can review the diff or
#      cherry-pick manually.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GOAL_FILE=""
TOUCH=""
TIMEOUT_S="${HARNESS_READY_TIMEOUT:-1800}"

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)         RUN_ID="$2"; shift 2 ;;
        --sprint)         SPRINT_N="$2"; shift 2 ;;
        --goal-file)      GOAL_FILE="$2"; shift 2 ;;
        --touch-surface)  TOUCH="$2"; shift 2 ;;
        --ready-timeout)  TIMEOUT_S="$2"; shift 2 ;;
        *) echo "run_generator: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$RUN_ID" ];    then echo "run_generator: missing --run-id" >&2;        exit 2; fi
if [ -z "$SPRINT_N" ];  then echo "run_generator: missing --sprint" >&2;        exit 2; fi
if [ -z "$GOAL_FILE" ]; then echo "run_generator: missing --goal-file" >&2;     exit 2; fi
if [ -z "$TOUCH" ];     then echo "run_generator: missing --touch-surface" >&2; exit 2; fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR_REL="harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
SPRINT_DIR_ABS="${REPO_ROOT}/${SPRINT_DIR_REL}"
READY_FILE="${SPRINT_DIR_ABS}/ready"

echo "[run_generator] scaffolding sprint dir…"
bash "${REPO_ROOT}/harness/lib/init_sprint.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --goal-file "$GOAL_FILE" --touch-surface "$TOUCH"

echo "[run_generator] creating worktree…"
WORKTREE_ABS=$(bash "${REPO_ROOT}/harness/lib/worktree_up.sh" "$RUN_ID" "$SPRINT_N" \
    "${SPRINT_DIR_ABS}/touch_surface.allow")
echo "[run_generator] worktree: $WORKTREE_ABS"

# Make sure no stale sentinel survives a previous run.
rm -f "$READY_FILE" "${SPRINT_DIR_ABS}/blocker.md"

# Build the subprocess command.
SYSTEM_PROMPT="${REPO_ROOT}/harness/prompts/generator.md"
USER_PROMPT_FILE="${SPRINT_DIR_ABS}/goal.md"
SESSION_LOG="${SPRINT_DIR_ABS}/generator_session.jsonl"

if [ "${GENERATOR_LIVE:-0}" = "1" ]; then
    if ! command -v claude >/dev/null 2>&1; then
        echo "run_generator: GENERATOR_LIVE=1 but \`claude\` CLI not found" >&2
        exit 2
    fi
    # Real generator: claude -p, Sonnet 4.6, system prompt = generator.md.
    # The user prompt is the rendered sprint context.
    USER_PROMPT="Sprint ${SPRINT_N} for run ${RUN_ID}.
Read in this order:
  1. ${SPRINT_DIR_REL}/goal.md
  2. ${SPRINT_DIR_REL}/contract.md
  3. docs/rubric/vision.md
  4. docs/rubric/rubric.md
Then proceed per the system prompt's per-sprint loop. Stop when ${SPRINT_DIR_REL}/ready exists."

    (
        cd "$WORKTREE_ABS"
        claude -p "$USER_PROMPT" \
            --model claude-sonnet-4-6 \
            --append-system-prompt "$(cat "$SYSTEM_PROMPT")" \
            --output-format stream-json \
            --permission-mode acceptEdits \
            2>&1 | tee -a "$SESSION_LOG"
    ) &
    GEN_PID=$!
elif [ -n "${GENERATOR_SHIM:-}" ]; then
    # Dry-run / smoke shim: a script that simulates the generator's effect on disk.
    "$GENERATOR_SHIM" "$WORKTREE_ABS" "$SPRINT_DIR_ABS" >> "$SESSION_LOG" 2>&1 &
    GEN_PID=$!
else
    echo "run_generator: must set GENERATOR_LIVE=1 (real run) or GENERATOR_SHIM=<path> (dry-run)" >&2
    exit 2
fi

echo "[run_generator] generator PID $GEN_PID; awaiting $READY_FILE (timeout ${TIMEOUT_S}s)…"

deadline=$(( $(date +%s) + TIMEOUT_S ))
while [ ! -f "$READY_FILE" ]; do
    if [ $(date +%s) -ge $deadline ]; then
        echo "[run_generator] TIMEOUT: no ready sentinel after ${TIMEOUT_S}s; killing generator" >&2
        kill -TERM "$GEN_PID" 2>/dev/null || true
        wait "$GEN_PID" 2>/dev/null || true
        exit 3
    fi
    if ! kill -0 "$GEN_PID" 2>/dev/null; then
        echo "[run_generator] generator exited before writing ready sentinel" >&2
        exit 4
    fi
    sleep 2
done

# Allow the subprocess to settle then capture exit.
wait "$GEN_PID" 2>/dev/null || true
echo "[run_generator] ready sentinel observed; producing verdict…"

# Verdict: blocker.md → BLOCKED; else run sprint_smoke for [trace] items.
if [ -f "${SPRINT_DIR_ABS}/blocker.md" ]; then
    echo "[run_generator] BLOCKED — see ${SPRINT_DIR_REL}/blocker.md"
    cat "${SPRINT_DIR_ABS}/blocker.md"
    echo
    echo "[run_generator] worktree: $WORKTREE_ABS"
    exit 10
fi

# Trace verdict — only valid when the contract supplies an action plan path.
# Convention: contract.md may include a line "## Action plan: <relative path>"
PLAN_PATH=$(awk '/^##[[:space:]]+Action plan:/{print $4}' "${SPRINT_DIR_ABS}/contract.md" || true)
if [ -n "$PLAN_PATH" ]; then
    if [ "${PLAN_PATH:0:1}" != "/" ]; then PLAN_PATH="${REPO_ROOT}/${PLAN_PATH}"; fi
    if bash "${REPO_ROOT}/harness/lib/sprint_smoke.sh" \
        --run-id "$RUN_ID" --sprint "$SPRINT_N" --plan "$PLAN_PATH"; then
        echo "[run_generator] PASS"
        echo "[run_generator] worktree: $WORKTREE_ABS"
        exit 0
    else
        echo "[run_generator] FAIL — trace rules unsatisfied"
        echo "[run_generator] worktree: $WORKTREE_ABS"
        exit 11
    fi
else
    echo "[run_generator] ready observed; no action plan declared in contract — operator must grade manually"
    echo "[run_generator] worktree: $WORKTREE_ABS"
    exit 0
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x harness/run_generator.sh
```

- [ ] **Step 3: Write `harness/test/smoke_generator.sh`**

A dry-run smoke that does NOT require Claude API access. The "generator shim" is a bash script bundled inline that simulates a generator's effect: writes a tiny test under `test/`, writes a tiny `.gd` file under the touch surface, drops a `ready` sentinel.

```bash
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
git -C "$WORKTREE" log --oneline | grep -q 'feat(smoke)' \
    || { echo "smoke: shim commit not on branch"; exit 1; }

# Cleanup.
git worktree remove --force "$WORKTREE"
git branch -D "harness/${RUN_ID}/sprint_${SPRINT_N}"
rm -rf "harness/runs/${RUN_ID}"
rm -rf "$WORKDIR"

echo "[smoke_generator] PASS"
```

- [ ] **Step 4: Make smoke executable**

```bash
chmod +x harness/test/smoke_generator.sh
```

- [ ] **Step 5: Run the smoke**

```bash
./harness/test/smoke_generator.sh
```

Expected: prints `[smoke_generator] PASS` and exits 0. If your local `main` branch is dirty, the worktree creation will use HEAD; this is OK for the smoke.

- [ ] **Step 6: Run the full harness test sweep**

```bash
python3 -m unittest discover -s harness/test -p "test_*.py" -v
```

Expected: every Python unittest under `harness/test/` passes.

- [ ] **Step 7: Commit**

```bash
git add harness/run_generator.sh harness/test/smoke_generator.sh
git commit -m "feat(harness): run_generator orchestrator + dry-run smoke"
```

---

## Task 12: README finalize + status flip

**Files:**
- Modify: `harness/README.md`

- [ ] **Step 1: Update Plan 3 status row to done**

In the Status table, replace the Plan 3 line so the table reads:

```markdown
| 1 | AgentBridge + scripted playtest | ✅ done |
| 2 | Rubric authoring (vision.md + ~70 anchor files) | ✅ done |
| 3 | Generator agent + worktree loop | ✅ done |
| 4 | Evaluator + strategy tournament | pending |
| 5 | Planner + orchestrator + report.html | pending |
| 6 | Meta-evaluation | pending |
```

- [ ] **Step 2: Append a "What's in Plan 3" section after the existing "What's in Plan 1" / "Plan 2" blocks**

```markdown
## What's in Plan 3

- `run_generator.sh` — operator-facing launcher (one sprint at a time)
- `prompts/generator.md` — Sonnet 4.6 system prompt
- `lib/contract_schema.py`, `lib/scan_contract_trace.py` — contract parsing + trace-rule DSL
- `lib/check_touch.py`, `lib/check_no_placeholders.sh` — pre-commit guards
- `lib/install_worktree_hooks.sh`, `lib/worktree_up.sh` — worktree lifecycle
- `lib/init_sprint.sh`, `lib/sprint_smoke.sh` — sprint dir + smoke driver
- `test/smoke_generator.sh` — end-to-end dry-run

Bridge from Plan 1 is unchanged; the smoke and generator both reuse `scripted_player.py`.

### Quick start (real generator run)

```bash
# Requires `claude` CLI in PATH and ANTHROPIC_API_KEY set.
GENERATOR_LIVE=1 ./harness/run_generator.sh \
  --run-id $(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 3) \
  --sprint 1 \
  --goal-file path/to/sprint_goal.md \
  --touch-surface path/to/sprint_touch.allow
```

### Quick start (dry-run smoke)

```bash
./harness/test/smoke_generator.sh
```

## What's NOT in Plan 3

LLM evaluator (the operator grades manually for now), strategy tournament, planner, orchestrator across multiple sprints, report.html. See `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11 — Plans 4–6.
```

- [ ] **Step 3: Run the harness test sweep one more time as a sanity check**

```bash
python3 -m unittest discover -s harness/test -p "test_*.py"
./harness/test/smoke_generator.sh
```

Expected: both green.

- [ ] **Step 4: Commit**

```bash
git add harness/README.md
git commit -m "docs(harness): mark Plan 3 done + protocol notes"
```

---

## Spec-coverage check (post-plan)

Self-review against `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`:

| Spec section | Covered by | Notes |
|---|---|---|
| §4.4 Generator invocation (claude -p, Sonnet 4.6, system prompt) | Tasks 10, 11 | Full. `--resume` deferred until Plan 4 needs multi-round negotiation. |
| §4.4 Workspace (worktree, branch off main) | Task 7 | Full. |
| §4.4 Tool surface (Read/Edit/Write/Bash, no spawning, no web) | Task 10 (prompt), Task 11 (launcher) | Enforced via system prompt + pre-commit hook scope. |
| §4.4 Per-sprint loop | Task 10 (prompt), Task 9 (smoke), Task 8 (sprint dir) | Loop documented in prompt; sprint_smoke implements the trace self-check at step 5. |
| §4.4 Self-evaluation banned at grade-time | Task 10 prompt | Prompt forbids; verdict computed by orchestrator from sprint_smoke, not generator. |
| §4.5 Contract shape (Done means / Rubric coverage / Forbidden / Status) | Task 2, Task 8 (template) | Full. Parser enforces ≥50% test/trace items. |
| §5.1 File-system contracts (runs/<id>/sprint_<N>/{contract,meta,ready,traces,…}) | Tasks 8, 11 | Mirrors spec paths exactly. `traces/` simplified to a single `trace.jsonl` in Plan 3 — Plan 4 will expand to the strategy-tournament fan-out. |
| §6.3 During-generation failures (touch-surface, placeholders, sentinel races) | Tasks 4, 5, 6, 11 | Pre-commit guards block touch and placeholders. Timeout in run_generator. |
| §6.3 "Writes 'TODO' / 'stub' placeholders" guard | Task 5 | Full. |
| §6.7 Anti-patterns ("Self-evaluation is a trap" / "Vague criteria → vague critique") | Task 2 (parser rejects pure-judge) + Task 10 prompt | Full. |
| §7.1 L1 unit tests | Tasks 2, 3, 4, 5, 6, 8 | Pure-Python helpers each ship a unittest. |
| §7.2 L2 smoke | Task 11 | Full dry-run smoke covers the orchestration; real-Claude run gated by `GENERATOR_LIVE=1`. |
| §4.3 Planner | Deferred | Plan 5. |
| §4.5 Evaluator (negotiation + grading) | Deferred | Plan 4. Operator plays evaluator manually in Plan 3. |
| §4.6 CLI orchestrator (multi-sprint) | Deferred | Plan 5. `run_generator.sh` is the single-sprint stand-in. |
| Strategy tournament (12 runs × seeds) | Deferred | Plan 4. |

**Gaps acknowledged:** Plan 3 ships *one* generator sprint at a time. Operator authors the contract (or accepts the template), supplies the touch surface, runs the launcher, reviews the resulting worktree, and decides whether to cherry-pick. Multi-sprint orchestration, LLM-driven contract negotiation, the strategy tournament, and `report.html` rendering are explicitly out of scope and ship in Plans 4–6.

---

**End of Plan 3.**
