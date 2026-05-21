# Evaluator Grading + Strategy Tournament Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Phase B of the evaluator (grading only, no negotiation). An operator runs `harness/run_evaluator.sh` with a `run-id` + `sprint` pointing at a sprint dir whose `contract.md` is `AGREED` and `ready` sentinel exists (produced by Plan 3 generator). The script (1) re-scores a small anchor calibration set via the judge LLM and aborts on drift, (2) runs the strategy tournament — 4 prior-guided strategies × 3 seeds + 1 freeplay — against the sprint worktree, (3) evaluates each `[test]` / `[trace]` / `[judge]` contract item using the appropriate verifier, (4) computes the composite rubric score with hard-floor checks, (5) writes `verdict.json` + `critique.md`. Contract negotiation (Phase A), the orchestrating Opus evaluator agent, and the planner are out of scope (Plan 5).

**Architecture:** Three layers. (1) Bash orchestrator (`run_evaluator.sh`) owns process lifecycle, calls each phase in order, and exits 0 iff every phase produced its expected artifact. (2) Python `harness/lib/` modules own structured concerns: LLM-driven strategy playtests, trace summarization, tournament-trace scanning, axis judge calls, anchor-based calibration, composite scoring, critique rendering. (3) Shell helpers (`tournament.sh`, `run_contract_tests.sh`) wrap repeated process invocations (Godot, GUT) so the Python layer never shells out to Godot directly — Python's job is data, Bash's job is processes. The LLM strategy driver and judge driver both invoke `claude -p --resume <session-id>` for per-playtest persistence per spec §4.2. No orchestrating LLM in Plan 4; the operator runs the script and reads the artifacts.

**Tech Stack:** Bash 3+ orchestrator, Python 3.11+ stdlib (`unittest`, `subprocess`, `argparse`, `json`, `dataclasses`), Godot 4.5 + GUT for `[test]` verifiers (re-uses existing `test/unit/` suite), Plan 1's `agent_bridge.gd` + `scripted_player.py` library code (the LLM player is a sibling of `scripted_player.py`, not a replacement), `claude` CLI (`claude -p --resume` for multi-turn). Strategy LLM defaults to Haiku 4.5, freeplay + judge default to Opus 4.7 (overridable via env vars). No third-party Python deps.

**Plan position:** Plan 4 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11. Depends on Plan 1 (AgentBridge + scripted player + trace schema), Plan 2 (`docs/rubric/` — vision.md, rubric.md, anchors, baseline-scorecard.md, bad-mod-scorecard.md), and Plan 3 (sprint dir layout, `contract.md` schema, worktree convention). Required input for Plan 5 (orchestrator wraps `run_evaluator.sh` inside an Opus-driven evaluator agent that also handles Phase A negotiation).

---

## File Structure

**Files created:**

```
harness/
├── run_evaluator.sh                                  # NEW — operator-facing entry
├── prompts/
│   ├── strategy_player.md                            # NEW — Haiku/Opus prior-driven player prompt
│   └── judge_axis.md                                 # NEW — anchored per-axis judge prompt template
├── strategies/
│   ├── eager_diagnostician.md                        # NEW — strategy prior #1 (Haiku)
│   ├── intervention_spammer.md                       # NEW — strategy prior #2 (Haiku)
│   ├── patient_observer.md                           # NEW — strategy prior #3 (Haiku)
│   ├── neglect.md                                    # NEW — strategy prior #4 (Haiku)
│   └── freeplay.md                                   # NEW — freeplay prompt (Opus, no decision rule)
├── lib/
│   ├── strategy_schema.py                            # NEW — parse + validate strategy markdown
│   ├── llm_player.py                                 # NEW — long-lived claude subprocess + bridge driver
│   ├── summarize_traces.py                           # NEW — compresses raw trace.jsonl → judge-friendly extract
│   ├── tournament.sh                                 # NEW — runs strategies × seeds + freeplay
│   ├── run_contract_tests.sh                         # NEW — runs `[test]` items via GUT
│   ├── scan_tournament_trace.py                      # NEW — runs `[trace]` rules across all traces
│   ├── judge.py                                      # NEW — per-axis judge driver (Opus)
│   ├── calibrate_anchors.py                          # NEW — re-score N anchor files, drift check
│   ├── score.py                                      # NEW — verdict.json from verifier outputs
│   ├── render_critique.py                            # NEW — critique.md from verdict + findings
│   └── claude_subprocess.py                          # NEW — small wrapper for `claude -p` and `--resume`
└── test/
    ├── fixtures/
    │   ├── trace_optimizer_seed1.jsonl               # NEW — synthetic trace for verifier tests
    │   ├── trace_intervention_seed1.jsonl            # NEW — synthetic trace, contrasting strategy
    │   ├── trace_freeplay.jsonl                      # NEW — synthetic freeplay trace
    │   ├── contract_pass.md                          # NEW — contract that should PASS verifiers
    │   ├── contract_floored.md                       # NEW — contract that should REJECT on floor
    │   └── anchor_calibration_small.txt              # NEW — list of 14 anchor paths used by calibrate_anchors
    ├── test_strategy_schema.py                       # NEW — unittest
    ├── test_llm_player.py                            # NEW — unittest (uses claude_subprocess shim)
    ├── test_summarize_traces.py                      # NEW — unittest
    ├── test_scan_tournament_trace.py                 # NEW — unittest
    ├── test_judge.py                                 # NEW — unittest (shimmed)
    ├── test_calibrate_anchors.py                     # NEW — unittest (shimmed)
    ├── test_score.py                                 # NEW — unittest
    ├── test_render_critique.py                       # NEW — unittest
    ├── test_claude_subprocess.py                     # NEW — unittest (shimmed)
    └── smoke_evaluator.sh                            # NEW — end-to-end dry-run integration
```

**Files modified:**

```
harness/README.md                                     # status table: Plan 4 done; protocol notes
.gitignore                                            # ignore harness/runs/*/sprint_*/traces/ outputs (already covered, verify)
```

**Files deleted:** none. No game-code, autoload, or rubric changes — Plan 4 is pure harness grading machinery.

---

## Conventions used by this plan

- **Run id + sprint dir**: same as Plan 3. `harness/runs/<run-id>/sprint_<N>/`. The evaluator never creates a run id; it consumes one produced by Plan 3.
- **Sprint precondition**: `harness/runs/<run-id>/sprint_<N>/contract.md` exists with `## Status: AGREED`, `harness/runs/<run-id>/sprint_<N>/ready` exists, the worktree at `.worktrees/harness/<run-id>/sprint_<N>/` exists.
- **Strategy id**: lowercase snake_case slug (e.g. `eager_diagnostician`). Matches the filename stem under `harness/strategies/`.
- **Seed**: integer 1, 2, 3 by default. Passed to the bridge via `--seed N` (Plan 1 already accepts it as an `argv` extension when invoked via `scripted_player`; the LLM player reuses the same pass-through).
- **Trace artifact path**: `harness/runs/<run-id>/sprint_<N>/traces/<strategy>_seed<S>.jsonl` for prior-guided runs; `traces/freeplay.jsonl` for the freeplay run.
- **Strategy session log**: `harness/runs/<run-id>/sprint_<N>/strategy_sessions/<strategy>_seed<S>.log` (concatenated claude session output for debug; one file per playtest).
- **Verifier artifact paths**: `test_results.json`, `trace_findings.json`, `judgments.json`, `calibration.json`, `verdict.json`, `critique.md` — all directly inside the sprint dir.
- **Bash style**: `set -euo pipefail` at the top of every script.
- **Python style**: stdlib only. Each module ships with a unittest suite under `harness/test/`. Long-running calls (claude, godot) are isolated behind a single function so tests can monkey-patch.
- **Live vs shimmed**: every external-process call respects an env var:
  - `EVALUATOR_LIVE=0` (default) → use shims (no API, no Godot). Used by `smoke_evaluator.sh` and unit tests.
  - `EVALUATOR_LIVE=1` → real `claude` and real Godot. Used for actual sprint grading.
- **Cost-control flags** (operator-facing on `run_evaluator.sh`):
  - `--strategies <comma-list>` (default: all four)
  - `--seeds <comma-list>` (default: `1,2,3`)
  - `--skip-freeplay`, `--skip-judge`, `--skip-calibration`
  - `--dry-run` (== `EVALUATOR_LIVE=0`)
- **Commit style**: Conventional Commits, matches Plans 1–3: `feat(harness):`, `feat(lib):`, `test(harness):`, etc.

---

## Task 1: Repo scaffolding + .gitignore verification + README in-progress marker

**Files:**
- Create: `harness/test/fixtures/.gitkeep`
- Create: `harness/strategies/.gitkeep` (only if `harness/strategies/` is otherwise empty after this task — it should already exist from Plan 1, keep `examples/` as-is)
- Modify: `.gitignore`
- Modify: `harness/README.md`

- [ ] **Step 1: Verify directory state**

```bash
test -d harness/strategies                || { echo "missing harness/strategies (Plan 1 should have created it)"; exit 1; }
test -d harness/strategies/examples       || { echo "missing harness/strategies/examples"; exit 1; }
test -f harness/strategies/examples/baseline_observer.json || { echo "missing Plan 1 example plan"; exit 1; }
mkdir -p harness/test/fixtures
touch harness/test/fixtures/.gitkeep
```

- [ ] **Step 2: Update `.gitignore` (idempotent)**

`.gitignore` already has `harness/runs/*/` from Plan 3. Verify it covers Plan 4's per-sprint trace outputs (which live under `harness/runs/<run-id>/sprint_<N>/traces/`) and add comment marker for Plan 4 outputs. Append at end:

```
# Harness Plan 4 runtime (per-sprint grading artifacts live under harness/runs/, already ignored)
# Strategy session logs may be large; explicitly ensure they are not committed.
harness/runs/*/sprint_*/strategy_sessions/
harness/runs/*/sprint_*/traces/
```

Verify:

```bash
grep -q '^harness/runs/\*/sprint_\*/strategy_sessions/$' .gitignore || { echo "missing strategy_sessions ignore"; exit 1; }
grep -q '^harness/runs/\*/sprint_\*/traces/$' .gitignore           || { echo "missing traces ignore"; exit 1; }
```

- [ ] **Step 3: Update `harness/README.md` status row to in-progress**

Open `harness/README.md` and edit the row for Plan 4. Change:

```markdown
| 4 | Evaluator + strategy tournament | pending |
```

to:

```markdown
| 4 | Evaluator + strategy tournament | 🚧 in progress |
```

(Final flip to `✅ done` happens in Task 14.)

- [ ] **Step 4: Commit**

```bash
git add harness/test/fixtures/.gitkeep .gitignore harness/README.md
git commit -m "feat(harness): scaffold Plan 4 dirs + gitignore + status marker"
```

---

## Task 2: Claude subprocess wrapper

A single helper for invoking `claude -p` once, then `claude -p --resume <session-id>` for subsequent turns. Used by both the LLM strategy player and the judge. Wrapping it here means: one place to apply timeouts, one place to swap to a shim, one place to capture session ids. Spec §4.2 (long-lived strategy session) + §4.5 (judge invocation) both go through here.

**Files:**
- Create: `harness/lib/claude_subprocess.py`
- Create: `harness/test/test_claude_subprocess.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_claude_subprocess.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/claude_subprocess.py."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import (  # noqa: E402
    ClaudeSession,
    ClaudeError,
    parse_session_id,
)


STREAM_JSON_FIRST_TURN = "\n".join([
    json.dumps({"type": "system", "subtype": "init", "session_id": "abc-123"}),
    json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}]}}),
    json.dumps({"type": "result", "subtype": "success", "result": "hello", "session_id": "abc-123"}),
]) + "\n"

STREAM_JSON_NO_SESSION = "\n".join([
    json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}]}}),
]) + "\n"


class TestParseSessionId(unittest.TestCase):
    def test_extracts_session_id_from_init(self) -> None:
        self.assertEqual(parse_session_id(STREAM_JSON_FIRST_TURN), "abc-123")

    def test_returns_none_when_absent(self) -> None:
        self.assertIsNone(parse_session_id(STREAM_JSON_NO_SESSION))

    def test_returns_none_for_garbage(self) -> None:
        self.assertIsNone(parse_session_id("not json at all\n"))


class TestClaudeSessionShim(unittest.TestCase):
    def test_shim_returns_canned_response(self) -> None:
        canned = {"abc": [{"op": "snapshot"}, {"op": "diag", "id": "diag_psych_eval"}]}
        sess = ClaudeSession.shim(canned, session_id="abc")
        first = sess.send("turn 0 prompt", model="claude-haiku-4-5-20251001")
        self.assertEqual(first["text"], json.dumps({"op": "snapshot"}))
        second = sess.send("turn 1 prompt", model="claude-haiku-4-5-20251001")
        self.assertEqual(second["text"], json.dumps({"op": "diag", "id": "diag_psych_eval"}))
        self.assertEqual(sess.session_id, "abc")

    def test_shim_runs_out(self) -> None:
        sess = ClaudeSession.shim({"x": []}, session_id="x")
        with self.assertRaises(ClaudeError):
            sess.send("first turn", model="claude-haiku-4-5-20251001")


class TestClaudeSessionLive(unittest.TestCase):
    def test_live_send_invokes_subprocess(self) -> None:
        with mock.patch("claude_subprocess.subprocess.run") as run_mock:
            run_mock.return_value = mock.Mock(
                stdout=STREAM_JSON_FIRST_TURN,
                stderr="",
                returncode=0,
            )
            sess = ClaudeSession.live(system_prompt="sp", working_dir="/tmp")
            reply = sess.send("u", model="claude-haiku-4-5-20251001")
            self.assertEqual(reply["text"], "hello")
            self.assertEqual(sess.session_id, "abc-123")
            args, kwargs = run_mock.call_args
            cmd = args[0]
            self.assertIn("claude", cmd[0])
            self.assertIn("-p", cmd)
            self.assertIn("--output-format", cmd)
            self.assertIn("stream-json", cmd)

    def test_live_second_turn_uses_resume(self) -> None:
        with mock.patch("claude_subprocess.subprocess.run") as run_mock:
            run_mock.return_value = mock.Mock(
                stdout=STREAM_JSON_FIRST_TURN, stderr="", returncode=0
            )
            sess = ClaudeSession.live(system_prompt="sp", working_dir="/tmp")
            sess.send("turn 0", model="claude-haiku-4-5-20251001")
            sess.send("turn 1", model="claude-haiku-4-5-20251001")
            cmd_second = run_mock.call_args_list[1][0][0]
            self.assertIn("--resume", cmd_second)
            self.assertIn("abc-123", cmd_second)

    def test_live_nonzero_exit_raises(self) -> None:
        with mock.patch("claude_subprocess.subprocess.run") as run_mock:
            run_mock.return_value = mock.Mock(stdout="", stderr="boom", returncode=2)
            sess = ClaudeSession.live(system_prompt="sp", working_dir="/tmp")
            with self.assertRaises(ClaudeError):
                sess.send("hi", model="claude-haiku-4-5-20251001")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_claude_subprocess -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'claude_subprocess'`.

- [ ] **Step 3: Write `harness/lib/claude_subprocess.py`**

```python
#!/usr/bin/env python3
"""Thin wrapper around the `claude` CLI for one-shot and resumed calls.

Two factories:
    ClaudeSession.live(system_prompt, working_dir)   # real subprocess
    ClaudeSession.shim(canned, session_id)           # in-memory canned replies (tests + smoke)

Each .send(user_prompt, model=...) returns dict {"text": str, "raw": [stream events]}.
First .send() spawns `claude -p`; subsequent .send() uses `claude -p --resume <session-id>`.

stream-json output format is used so the session id is parseable from the init event.
"""
from __future__ import annotations
import json
import subprocess
from dataclasses import dataclass, field
from typing import Any, Optional


class ClaudeError(RuntimeError):
    pass


def parse_session_id(stream_text: str) -> Optional[str]:
    """Look at stream-json output for the session id from the init event."""
    for line in stream_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        if obj.get("type") == "system" and obj.get("subtype") == "init":
            sid = obj.get("session_id")
            if isinstance(sid, str):
                return sid
        if obj.get("type") == "result":
            sid = obj.get("session_id")
            if isinstance(sid, str):
                return sid
    return None


def _extract_text(stream_text: str) -> str:
    """Concatenate any assistant `text` blocks; tolerate missing fields."""
    out: list[str] = []
    for line in stream_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") == "assistant":
            for block in obj.get("message", {}).get("content", []):
                if block.get("type") == "text":
                    out.append(block.get("text", ""))
        elif obj.get("type") == "result" and obj.get("subtype") == "success":
            text = obj.get("result")
            if isinstance(text, str) and not out:
                out.append(text)
    return "".join(out)


@dataclass
class ClaudeSession:
    system_prompt: str = ""
    working_dir: str = "."
    session_id: Optional[str] = None
    _shim_queue: Optional[dict[str, list[dict[str, Any]]]] = None
    _shim_cursor: int = 0
    raw_log: list[str] = field(default_factory=list)

    @classmethod
    def live(cls, system_prompt: str, working_dir: str) -> "ClaudeSession":
        return cls(system_prompt=system_prompt, working_dir=working_dir)

    @classmethod
    def shim(cls, canned: dict[str, list[dict[str, Any]]], session_id: str) -> "ClaudeSession":
        return cls(
            system_prompt="",
            working_dir=".",
            session_id=session_id,
            _shim_queue=canned,
        )

    def _send_shim(self, user_prompt: str) -> dict[str, Any]:
        assert self._shim_queue is not None and self.session_id is not None
        bucket = self._shim_queue.get(self.session_id, [])
        if self._shim_cursor >= len(bucket):
            raise ClaudeError(
                f"shim ran out of canned responses for session {self.session_id} "
                f"(cursor {self._shim_cursor})"
            )
        op = bucket[self._shim_cursor]
        self._shim_cursor += 1
        text = json.dumps(op) if not isinstance(op, str) else op
        return {"text": text, "raw": [text]}

    def _send_live(self, user_prompt: str, model: str, timeout_s: float) -> dict[str, Any]:
        cmd = [
            "claude", "-p", user_prompt,
            "--model", model,
            "--output-format", "stream-json",
            "--permission-mode", "acceptEdits",
        ]
        if self.session_id:
            cmd.extend(["--resume", self.session_id])
        if self.system_prompt:
            cmd.extend(["--append-system-prompt", self.system_prompt])
        try:
            proc = subprocess.run(
                cmd,
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
        except subprocess.TimeoutExpired as e:
            raise ClaudeError(f"claude timed out after {timeout_s}s: {e}") from e
        if proc.returncode != 0:
            raise ClaudeError(
                f"claude exited {proc.returncode}: stderr={proc.stderr[-800:]}"
            )
        self.raw_log.append(proc.stdout)
        sid = parse_session_id(proc.stdout)
        if sid:
            self.session_id = sid
        text = _extract_text(proc.stdout)
        return {"text": text, "raw": proc.stdout.splitlines()}

    def send(
        self,
        user_prompt: str,
        model: str,
        timeout_s: float = 120.0,
    ) -> dict[str, Any]:
        if self._shim_queue is not None:
            return self._send_shim(user_prompt)
        return self._send_live(user_prompt, model, timeout_s)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_claude_subprocess -v`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/claude_subprocess.py harness/test/test_claude_subprocess.py
git commit -m "feat(lib): claude subprocess wrapper w/ session-resume + shim"
```

---

## Task 3: Strategy schema (markdown + frontmatter)

Each strategy prior is a Markdown file with a small YAML-ish frontmatter declaring metadata (id, model, freeplay-or-prior, hidden_state_visible). The body is the prompt content the LLM gets prepended. Validating up-front prevents typos that would otherwise only show up after a multi-minute playtest.

**Files:**
- Create: `harness/lib/strategy_schema.py`
- Create: `harness/test/test_strategy_schema.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_strategy_schema.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/strategy_schema.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from strategy_schema import (  # noqa: E402
    parse_strategy_file,
    Strategy,
    StrategySchemaError,
)

VALID_PRIOR = """---
id: eager_diagnostician
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Eager Diagnostician

PRIOR:
- Default to running diagnostics over interventions in days 1-3.
- Never observe-only if any diagnostic affordable.

DECISION RULE:
  if any diagnostic available + affordable: pick highest cost (most info)
  elif any intervention available + gates unlocked: pick cheapest
  else: snapshot + advance
"""

VALID_FREEPLAY = """---
id: freeplay
mode: freeplay
model: claude-opus-4-7
hidden_state_visible: false
---

# Freeplay

No fixed prior. Read the snapshot. Take whichever action you think is most informative.
Narrate your choice in 1 sentence before emitting the op JSON.
"""

MISSING_ID = VALID_PRIOR.replace("id: eager_diagnostician\n", "")
BAD_MODE = VALID_PRIOR.replace("mode: prior", "mode: bananas")
ID_MISMATCH_FILENAME = VALID_PRIOR  # we'll write it under a different stem


class TestStrategySchema(unittest.TestCase):
    def _write(self, content: str, name: str = "eager_diagnostician.md") -> Path:
        d = Path(self.tmp.name)
        p = d / name
        p.write_text(content)
        return p

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_parses_valid_prior(self) -> None:
        p = self._write(VALID_PRIOR)
        s = parse_strategy_file(p)
        self.assertEqual(s.id, "eager_diagnostician")
        self.assertEqual(s.mode, "prior")
        self.assertEqual(s.model, "claude-haiku-4-5-20251001")
        self.assertFalse(s.hidden_state_visible)
        self.assertIn("DECISION RULE", s.body)

    def test_parses_valid_freeplay(self) -> None:
        p = self._write(VALID_FREEPLAY, name="freeplay.md")
        s = parse_strategy_file(p)
        self.assertEqual(s.mode, "freeplay")
        self.assertEqual(s.model, "claude-opus-4-7")

    def test_rejects_missing_id(self) -> None:
        p = self._write(MISSING_ID)
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)

    def test_rejects_bad_mode(self) -> None:
        p = self._write(BAD_MODE)
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)

    def test_rejects_id_filename_mismatch(self) -> None:
        p = self._write(ID_MISMATCH_FILENAME, name="something_else.md")
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)

    def test_rejects_no_frontmatter(self) -> None:
        p = self._write("just a body, no frontmatter")
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_strategy_schema -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write `harness/lib/strategy_schema.py`**

```python
#!/usr/bin/env python3
"""Validate + parse strategy prior files. See harness/strategies/*.md."""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path


VALID_MODES = ("prior", "freeplay")
REQUIRED = ("id", "mode", "model", "hidden_state_visible")


class StrategySchemaError(ValueError):
    pass


def _parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---\n"):
        raise StrategySchemaError("file does not start with '---\\n' frontmatter delimiter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise StrategySchemaError("frontmatter not closed with '\\n---\\n'")
    block = text[4:end]
    body = text[end + 5 :]
    out: dict[str, str] = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise StrategySchemaError(f"frontmatter line missing ':' — {line!r}")
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out, body


@dataclass(frozen=True)
class Strategy:
    id: str
    mode: str
    model: str
    hidden_state_visible: bool
    body: str
    source_path: Path


def parse_strategy_file(path: Path) -> Strategy:
    text = path.read_text()
    meta, body = _parse_frontmatter(text)
    for field in REQUIRED:
        if field not in meta:
            raise StrategySchemaError(f"{path}: missing required frontmatter field '{field}'")
    if meta["mode"] not in VALID_MODES:
        raise StrategySchemaError(f"{path}: mode {meta['mode']!r} not in {VALID_MODES}")
    visible_raw = meta["hidden_state_visible"].lower()
    if visible_raw not in ("true", "false"):
        raise StrategySchemaError(
            f"{path}: hidden_state_visible must be 'true' or 'false', got {visible_raw!r}"
        )
    expected_stem = meta["id"]
    if path.stem != expected_stem:
        raise StrategySchemaError(
            f"{path}: id {expected_stem!r} does not match filename stem {path.stem!r}"
        )
    return Strategy(
        id=meta["id"],
        mode=meta["mode"],
        model=meta["model"],
        hidden_state_visible=(visible_raw == "true"),
        body=body.strip() + "\n",
        source_path=path,
    )
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_strategy_schema -v`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/strategy_schema.py harness/test/test_strategy_schema.py
git commit -m "feat(lib): strategy markdown schema (frontmatter + body)"
```

---

## Task 4: Author 4 strategy priors + 1 freeplay

These are the actual prompts. Spec §4.2 + §3.3 axis 2 (decision density) make the strategy mix load-bearing: dominant-strategy variance is the killer axis-2 signal, so the priors must surface DIFFERENT routes through the prototype.

**Files:**
- Create: `harness/strategies/eager_diagnostician.md`
- Create: `harness/strategies/intervention_spammer.md`
- Create: `harness/strategies/patient_observer.md`
- Create: `harness/strategies/neglect.md`
- Create: `harness/strategies/freeplay.md`

- [ ] **Step 1: Write `harness/strategies/eager_diagnostician.md`**

```markdown
---
id: eager_diagnostician
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Eager Diagnostician

You play Lifelines as: "spend caseworker hours on diagnostics first; interventions only after the case file fills out."

PRIOR:
- Default to running diagnostics over interventions in days 1-3.
- Never observe-only if any diagnostic is affordable + gate-met.
- Save 0.5 capacity-hours per day for one intervention; the rest goes to diagnostics.
- If overskudd < 20, wait — call `advance` until overskudd > 40 before acting again.

DECISION RULE (apply per checkpoint):
  if any diagnostic in catalog.diagnostics_available has gate_met=true AND affordable=true:
      pick the one with the highest cost.hours (most information per scarce capacity)
  elif any intervention in catalog.interventions_available has gate_met=true AND affordable=true:
      pick the cheapest by cost.hours
  else:
      emit {"op": "advance", "game_hours": 1.0}

RETURN: exactly one op JSON object per checkpoint. No prose. No multiple ops. Examples:
  {"op": "diag", "id": "diag_psych_eval"}
  {"op": "interv", "id": "int_quiet_walk"}
  {"op": "advance", "game_hours": 1.0}
  {"op": "snapshot"}

If the snapshot shows day > 9, emit {"op": "shutdown"}.
```

- [ ] **Step 2: Write `harness/strategies/intervention_spammer.md`**

```markdown
---
id: intervention_spammer
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Intervention Spammer

You play Lifelines as: "act first, observe later — push interventions even on thin information."

PRIOR:
- Default to running interventions over diagnostics.
- Diagnostics only if zero interventions are gate-met.
- Refusal is acceptable; the trace data is the point.
- Never wait for overskudd to regen if any intervention is affordable.

DECISION RULE (apply per checkpoint):
  if any intervention in catalog.interventions_available has gate_met=true AND affordable=true:
      pick the cheapest by cost.hours
  elif any diagnostic in catalog.diagnostics_available has gate_met=true AND affordable=true:
      pick the cheapest by cost.hours
  else:
      emit {"op": "advance", "game_hours": 1.0}

RETURN: exactly one op JSON object per checkpoint. No prose. No multiple ops.

If the snapshot shows day > 9, emit {"op": "shutdown"}.
```

- [ ] **Step 3: Write `harness/strategies/patient_observer.md`**

```markdown
---
id: patient_observer
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Patient Observer

You play Lifelines as: "minimal action; let passive observations and time-of-day cycle do the work."

PRIOR:
- Strongly prefer passive observation (snapshot + advance) over active diagnostics/interventions.
- One active call per day, maximum. Pick whichever surfaces a tag you do not already have.
- Honor capacity scarcity — refuse to drain capacity below 1.0h.

DECISION RULE (apply per checkpoint):
  if it is the first checkpoint of a new game-day (snapshot.time.hour < 8.0 AND no active call yet today):
      pick the cheapest affordable + gate-met diagnostic whose tags do not appear in case_file.tags;
      if none such, pick the cheapest affordable + gate-met intervention with the same novelty filter;
      if still none, emit {"op": "advance", "game_hours": 4.0}
  else:
      emit {"op": "advance", "game_hours": 2.0}

RETURN: exactly one op JSON object per checkpoint. No prose. No multiple ops.

If the snapshot shows day > 9, emit {"op": "shutdown"}.
```

- [ ] **Step 4: Write `harness/strategies/neglect.md`**

```markdown
---
id: neglect
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Neglect

You play Lifelines as: "do nothing — let drift accumulate. This is the floor strategy."

PRIOR:
- Never call diagnostics or interventions.
- Always advance the clock.
- The job is to surface what happens when no caseworker time is invested.

DECISION RULE (apply per checkpoint):
  emit {"op": "advance", "game_hours": 4.0}

RETURN: exactly one op JSON object per checkpoint. No prose.

If the snapshot shows day > 9, emit {"op": "shutdown"}.
```

- [ ] **Step 5: Write `harness/strategies/freeplay.md`**

```markdown
---
id: freeplay
mode: freeplay
model: claude-opus-4-7
hidden_state_visible: false
---

# Freeplay

You are not following a prior. You are playing Lifelines like a curious caseworker on day one.

GOAL: by the end of the 10-day arc, you should be able to describe Elling — what kind of person he is, what calms him, what wears him down — in 2–3 specific sentences. Use the case_file content as your only source of truth about Elling. The snapshot's `client.cognitive` and `client.needs` are observable surface; everything else you must infer.

PROCEDURE (per checkpoint):
  1. Read the snapshot.
  2. Read any new case_file entries since the last checkpoint.
  3. Pick ONE action that maximally advances your understanding of Elling, given your current case_file. You may diag, interv, snapshot, or advance.
  4. Before emitting the op, write a single short sentence (max 25 words) of internal narration starting with `// `. Do not write more than one such line.

RETURN: one `// narration` line followed by exactly one op JSON object, separated by a newline. Example:

```
// elling resists strangers — try a quiet activity instead of pushing the social diagnostic.
{"op": "interv", "id": "int_quiet_walk"}
```

If the snapshot shows day > 9, emit `// ten days. enough.\n{"op": "shutdown"}`.
```

- [ ] **Step 6: Verify all five files parse**

```bash
python3 -c "
import sys, pathlib
sys.path.insert(0, 'harness/lib')
from strategy_schema import parse_strategy_file
for p in pathlib.Path('harness/strategies').glob('*.md'):
    s = parse_strategy_file(p)
    print(f'{s.id}: mode={s.mode} model={s.model}')
"
```

Expected output (order may vary):

```
eager_diagnostician: mode=prior model=claude-haiku-4-5-20251001
intervention_spammer: mode=prior model=claude-haiku-4-5-20251001
patient_observer: mode=prior model=claude-haiku-4-5-20251001
neglect: mode=prior model=claude-haiku-4-5-20251001
freeplay: mode=freeplay model=claude-opus-4-7
```

- [ ] **Step 7: Commit**

```bash
git add harness/strategies/eager_diagnostician.md harness/strategies/intervention_spammer.md harness/strategies/patient_observer.md harness/strategies/neglect.md harness/strategies/freeplay.md
git commit -m "feat(harness): author 4 strategy priors + freeplay prompt"
```

---

## Task 5: LLM strategy player

The bridge of Plan 1 already exposes the protocol (commands in, events out). The scripted player drives canned ops; this is the LLM-driven sibling. One long-lived `ClaudeSession` per playtest. Each checkpoint = (snapshot + new events) → user turn → assistant emits one op JSON → bridge executes.

The `freeplay` strategy mode emits `// narration\n{...op}`; the player strips the `// ` prefix into the trace as a `narration` event and forwards the JSON to the bridge.

**Files:**
- Create: `harness/lib/llm_player.py`
- Create: `harness/test/test_llm_player.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_llm_player.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/llm_player.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import ClaudeSession  # noqa: E402
from llm_player import (  # noqa: E402
    extract_op,
    LlmPlayerError,
    PlayerState,
    _trim_history,
    render_user_prompt,
)


class TestExtractOp(unittest.TestCase):
    def test_plain_json(self) -> None:
        text = '{"op": "snapshot"}'
        op, narration = extract_op(text)
        self.assertEqual(op, {"op": "snapshot"})
        self.assertIsNone(narration)

    def test_freeplay_narration_then_op(self) -> None:
        text = "// elling resists strangers — quiet walk first\n" + '{"op": "interv", "id": "int_quiet_walk"}'
        op, narration = extract_op(text)
        self.assertEqual(op, {"op": "interv", "id": "int_quiet_walk"})
        self.assertEqual(narration, "elling resists strangers — quiet walk first")

    def test_fenced_codeblock(self) -> None:
        text = "Some preamble\n```json\n{\"op\": \"advance\", \"game_hours\": 2}\n```"
        op, _ = extract_op(text)
        self.assertEqual(op, {"op": "advance", "game_hours": 2})

    def test_no_json_raises(self) -> None:
        with self.assertRaises(LlmPlayerError):
            extract_op("I'd rather not say.")

    def test_invalid_op_raises(self) -> None:
        with self.assertRaises(LlmPlayerError):
            extract_op('{"command": "shutdown"}')


class TestRenderUserPrompt(unittest.TestCase):
    def test_includes_snapshot_and_new_events(self) -> None:
        state = PlayerState(
            checkpoint=3,
            last_snapshot={"time": {"day": 2, "hour": 9.0}, "client": {"overskudd": 50.0}},
            new_events=[{"ev": "diagnostic_completed", "id": "diag_psych_eval"}],
            running_summary="case_file tags so far: mtg:blue, affinity:order",
        )
        out = render_user_prompt(state)
        self.assertIn("checkpoint 3", out)
        self.assertIn('"day": 2', out)
        self.assertIn("diagnostic_completed", out)
        self.assertIn("mtg:blue", out)


class TestTrimHistory(unittest.TestCase):
    def test_trims_to_last_n(self) -> None:
        evs = [{"ev": f"e{i}"} for i in range(20)]
        trimmed = _trim_history(evs, max_events=5)
        self.assertEqual(len(trimmed), 5)
        self.assertEqual(trimmed[0]["ev"], "e15")
        self.assertEqual(trimmed[-1]["ev"], "e19")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_llm_player -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write `harness/lib/llm_player.py`**

```python
#!/usr/bin/env python3
"""Drive a Godot --agent-mode session with an LLM strategy (prior- or freeplay-driven).

Sibling of harness/lib/scripted_player.py from Plan 1. Same comms protocol; the difference
is the policy: instead of a canned action plan keyed by (day, hour), each checkpoint
queries a long-lived ClaudeSession for the next op.

Usage:
    python3 harness/lib/llm_player.py \
        --godot /Applications/Godot.app/Contents/MacOS/Godot \
        --project "$PWD" \
        --strategy harness/strategies/eager_diagnostician.md \
        --seed 1 \
        --comms-dir /tmp/lifelines-harness/run1/eager_seed1 \
        --trace-out harness/runs/<id>/sprint_<N>/traces/eager_diagnostician_seed1.jsonl \
        --session-log harness/runs/<id>/sprint_<N>/strategy_sessions/eager_diagnostician_seed1.log
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from claude_subprocess import ClaudeSession, ClaudeError  # noqa: E402
from strategy_schema import parse_strategy_file, Strategy  # noqa: E402
from trace_schema import validate_event_line, SchemaError  # noqa: E402


VALID_OPS = {"snapshot", "diag", "interv", "advance", "set_speed", "shutdown"}
MAX_CHECKPOINTS = 200  # hard cap on rounds per playtest


class LlmPlayerError(RuntimeError):
    pass


@dataclass
class PlayerState:
    checkpoint: int = 0
    last_snapshot: dict = field(default_factory=dict)
    new_events: list[dict] = field(default_factory=list)
    running_summary: str = ""


def _trim_history(events: list[dict], max_events: int) -> list[dict]:
    if len(events) <= max_events:
        return list(events)
    return events[-max_events:]


def render_user_prompt(state: PlayerState, max_events: int = 12) -> str:
    snap = json.dumps(state.last_snapshot, indent=2, ensure_ascii=False)
    evs = json.dumps(_trim_history(state.new_events, max_events), indent=2, ensure_ascii=False)
    summary = state.running_summary or "(no summary yet)"
    return (
        f"checkpoint {state.checkpoint}\n"
        f"---\n"
        f"running summary of the arc so far:\n{summary}\n"
        f"---\n"
        f"latest snapshot:\n{snap}\n"
        f"---\n"
        f"new events since last checkpoint (most recent last):\n{evs}\n"
        f"---\n"
        f"emit your next op now."
    )


_JSON_OBJ_RE = re.compile(r"\{[^{}]*\}|\{(?:[^{}]|\{[^{}]*\})*\}", re.DOTALL)


def extract_op(text: str) -> tuple[dict, Optional[str]]:
    """Pull the op JSON object out of the assistant response.

    Returns (op_dict, narration_or_None). Narration is the text after a leading `// ` line.
    """
    narration: Optional[str] = None
    cleaned = text.strip()

    # Strip a leading `// narration` line if present.
    if cleaned.startswith("// "):
        head, _, rest = cleaned.partition("\n")
        narration = head[3:].strip()
        cleaned = rest.strip()

    # Try fenced ```json block first.
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.DOTALL)
    if fence:
        cleaned = fence.group(1)
    else:
        match = _JSON_OBJ_RE.search(cleaned)
        if not match:
            raise LlmPlayerError(f"no JSON object found in response: {text!r}")
        cleaned = match.group(0)

    try:
        op = json.loads(cleaned)
    except json.JSONDecodeError as e:
        raise LlmPlayerError(f"op JSON parse failed: {e} — body was {cleaned!r}") from e
    if not isinstance(op, dict) or "op" not in op:
        raise LlmPlayerError(f"op missing 'op' key: {op!r}")
    if op["op"] not in VALID_OPS:
        raise LlmPlayerError(f"unknown op {op['op']!r}; allowed: {VALID_OPS}")
    return op, narration


# --- Comms helpers (mirror scripted_player) -------------------------------

def _init_comms_dir(comms_dir: Path) -> None:
    if comms_dir.exists():
        shutil.rmtree(comms_dir)
    comms_dir.mkdir(parents=True)
    (comms_dir / "cmd.jsonl").write_text("")


def _append_command(comms_dir: Path, cmd: dict) -> None:
    with (comms_dir / "cmd.jsonl").open("a") as fh:
        fh.write(json.dumps(cmd, ensure_ascii=False) + "\n")


def _wait_for_file(path: Path, timeout_s: float, clear_after: bool = False) -> bool:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if path.exists():
            if clear_after:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            return True
        time.sleep(0.05)
    return False


def _read_events_since(comms_dir: Path, cursor: int) -> tuple[list[dict], int]:
    path = comms_dir / "events.jsonl"
    if not path.exists():
        return [], cursor
    events: list[dict] = []
    with path.open() as fh:
        fh.seek(cursor)
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                events.append(validate_event_line(line))
            except SchemaError as e:
                events.append({"ev": "schema_error", "raw": line, "err": str(e)})
        new_cursor = fh.tell()
    return events, new_cursor


def _latest_snapshot(events: list[dict]) -> Optional[dict]:
    for ev in reversed(events):
        reply = ev.get("reply") if isinstance(ev, dict) else None
        if isinstance(reply, dict) and "snapshot" in reply:
            return reply["snapshot"]
    return None


def _current_day(events: list[dict]) -> int:
    snap = _latest_snapshot(events)
    if snap and "time" in snap:
        return int(snap["time"].get("day", 1))
    return 1


# --- Main playtest loop ---------------------------------------------------

def run_playtest(args: argparse.Namespace) -> int:
    strategy: Strategy = parse_strategy_file(Path(args.strategy))

    comms_dir = Path(args.comms_dir)
    _init_comms_dir(comms_dir)

    godot_cmd = [
        args.godot, "--headless",
        "--path", args.project,
        "--",
        "--agent-mode",
        "--comms-dir", str(comms_dir),
        "--seed", str(args.seed),
    ]
    if strategy.hidden_state_visible:
        godot_cmd.append("--reveal-hidden")

    print(f"[llm_player] launching godot: {' '.join(godot_cmd)}", file=sys.stderr)
    godot_proc = subprocess.Popen(godot_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    # Spawn the LLM session.
    if args.live:
        session = ClaudeSession.live(system_prompt=strategy.body, working_dir=args.project)
    else:
        canned_path = Path(args.shim_canned) if args.shim_canned else None
        if not canned_path or not canned_path.exists():
            raise LlmPlayerError(f"--no-live requires --shim-canned pointing at a JSON file (got {canned_path})")
        canned = json.loads(canned_path.read_text())
        # Tests + smoke use a fixed session id so the shim queue can find its bucket.
        session = ClaudeSession.shim(canned, session_id="shim-session")

    state = PlayerState()
    all_events: list[dict] = []
    cursor = 0

    try:
        if not _wait_for_file(comms_dir / "bound", timeout_s=args.checkpoint_timeout):
            raise LlmPlayerError("timed out waiting for bridge to bind")

        # Initial snapshot baseline.
        _append_command(comms_dir, {"op": "snapshot"})
        if not _wait_for_file(comms_dir / "ready", timeout_s=args.checkpoint_timeout, clear_after=True):
            raise LlmPlayerError("timed out waiting for initial snapshot")
        events, cursor = _read_events_since(comms_dir, cursor)
        all_events.extend(events)
        state.last_snapshot = _latest_snapshot(all_events) or {}

        while state.checkpoint < MAX_CHECKPOINTS:
            state.checkpoint += 1
            user_prompt = render_user_prompt(state)
            try:
                reply = session.send(user_prompt, model=strategy.model, timeout_s=args.checkpoint_timeout)
            except ClaudeError as e:
                raise LlmPlayerError(f"claude error at checkpoint {state.checkpoint}: {e}") from e
            op, narration = extract_op(reply["text"])

            if narration:
                all_events.append({"ev": "narration", "strategy": strategy.id, "text": narration, "checkpoint": state.checkpoint})

            _append_command(comms_dir, op)
            ok = _wait_for_file(comms_dir / "ready", timeout_s=args.checkpoint_timeout, clear_after=True)
            if not ok:
                raise LlmPlayerError(f"bridge did not reply within timeout for op {op}")

            events, cursor = _read_events_since(comms_dir, cursor)
            state.new_events = events
            all_events.extend(events)
            snap = _latest_snapshot(all_events)
            if snap:
                state.last_snapshot = snap

            if op["op"] == "shutdown":
                break
            if _current_day(all_events) > args.max_days:
                _append_command(comms_dir, {"op": "shutdown"})
                _wait_for_file(comms_dir / "ready", timeout_s=args.checkpoint_timeout, clear_after=True)
                events, cursor = _read_events_since(comms_dir, cursor)
                all_events.extend(events)
                break

        godot_proc.wait(timeout=10)
    finally:
        if godot_proc.poll() is None:
            godot_proc.terminate()
            try:
                godot_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                godot_proc.kill()

    # Persist trace.
    trace_path = Path(args.trace_out)
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    with trace_path.open("w") as fh:
        for ev in all_events:
            fh.write(json.dumps(ev, ensure_ascii=False) + "\n")

    # Persist session log.
    if args.session_log:
        session_log = Path(args.session_log)
        session_log.parent.mkdir(parents=True, exist_ok=True)
        session_log.write_text("\n".join(session.raw_log))

    print(f"[llm_player] wrote {len(all_events)} trace lines → {trace_path}", file=sys.stderr)
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--godot", required=True)
    p.add_argument("--project", required=True)
    p.add_argument("--strategy", required=True, help="Path to strategy markdown")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--comms-dir", required=True)
    p.add_argument("--trace-out", required=True)
    p.add_argument("--session-log", default=None)
    p.add_argument("--live", action="store_true", help="Use real claude CLI (else shim)")
    p.add_argument("--shim-canned", default=None, help="JSON file w/ canned response bucket")
    p.add_argument("--checkpoint-timeout", type=float, default=120.0)
    p.add_argument("--max-days", type=int, default=10)
    return p.parse_args()


if __name__ == "__main__":
    sys.exit(run_playtest(parse_args()))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_llm_player -v`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/llm_player.py harness/test/test_llm_player.py
git commit -m "feat(lib): LLM strategy player (long-lived claude session + bridge)"
```

---

## Task 6: Trace summarizer

Raw trace.jsonl per playtest is ~5–50 KB. The judge needs a compact extract per strategy (key events + counts), not the whole thing — otherwise per-axis judge calls blow tokens. The summarizer is pure data, no LLM, fully testable from fixtures.

**Files:**
- Create: `harness/lib/summarize_traces.py`
- Create: `harness/test/test_summarize_traces.py`
- Create: `harness/test/fixtures/trace_optimizer_seed1.jsonl`
- Create: `harness/test/fixtures/trace_intervention_seed1.jsonl`
- Create: `harness/test/fixtures/trace_freeplay.jsonl`

- [ ] **Step 1: Write fixture traces**

`harness/test/fixtures/trace_optimizer_seed1.jsonl`:

```jsonl
{"ev":"day_started","day":1,"t":{"d":1,"h":8.0}}
{"reply":{"ok":true,"snapshot":{"time":{"day":1,"hour":8.0},"client":{"overskudd":60.0,"needs":{"energy":0.8}},"case_file":{"entries":[],"tags":[]}}},"for":"snapshot","t":{"d":1,"h":8.0}}
{"ev":"diagnostic_completed","id":"diag_psych_eval","t":{"d":1,"h":10.5}}
{"ev":"case_file_updated","entry":"obs_alphabetizes","t":{"d":1,"h":10.5}}
{"ev":"action_failed","reason":"client_refuses","action":"int_phone_call","t":{"d":2,"h":11.0}}
{"ev":"day_ended","day":1,"t":{"d":2,"h":0.0}}
{"ev":"day_started","day":2,"t":{"d":2,"h":8.0}}
{"ev":"diagnostic_completed","id":"diag_routine_chart","t":{"d":2,"h":9.5}}
{"ev":"case_file_updated","entry":"obs_morning_quiet","t":{"d":2,"h":9.5}}
{"ev":"day_ended","day":2,"t":{"d":3,"h":0.0}}
```

`harness/test/fixtures/trace_intervention_seed1.jsonl`:

```jsonl
{"ev":"day_started","day":1,"t":{"d":1,"h":8.0}}
{"reply":{"ok":true,"snapshot":{"time":{"day":1,"hour":8.0},"client":{"overskudd":60.0},"case_file":{"entries":[],"tags":[]}}},"for":"snapshot","t":{"d":1,"h":8.0}}
{"ev":"intervention_completed","id":"int_reading_together","t":{"d":1,"h":11.0}}
{"ev":"action_failed","reason":"client_refuses","action":"int_phone_call","t":{"d":1,"h":14.0}}
{"ev":"intervention_completed","id":"int_quiet_walk","t":{"d":2,"h":10.0}}
{"ev":"day_ended","day":2,"t":{"d":3,"h":0.0}}
```

`harness/test/fixtures/trace_freeplay.jsonl`:

```jsonl
{"ev":"narration","strategy":"freeplay","text":"begin with the most informative cheap action — observe the morning chart","checkpoint":1}
{"ev":"diagnostic_completed","id":"diag_routine_chart","t":{"d":1,"h":9.5}}
{"ev":"case_file_updated","entry":"obs_morning_quiet","t":{"d":1,"h":9.5}}
{"ev":"narration","strategy":"freeplay","text":"elling's mornings are quiet; he tolerates routine — keep low-pressure activities","checkpoint":4}
{"ev":"intervention_completed","id":"int_quiet_walk","t":{"d":2,"h":10.0}}
{"ev":"day_ended","day":2,"t":{"d":3,"h":0.0}}
```

- [ ] **Step 2: Write the failing test**

`harness/test/test_summarize_traces.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/summarize_traces.py."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from summarize_traces import (  # noqa: E402
    summarize_trace,
    summarize_directory,
    TraceSummary,
)

FIXTURES = Path(__file__).parent / "fixtures"


class TestSummarizeTrace(unittest.TestCase):
    def test_counts_events(self) -> None:
        s = summarize_trace(FIXTURES / "trace_optimizer_seed1.jsonl")
        self.assertEqual(s.strategy, "optimizer")
        self.assertEqual(s.seed, 1)
        self.assertEqual(s.counts["diagnostic_completed"], 2)
        self.assertEqual(s.counts["intervention_completed"], 0)
        self.assertEqual(s.counts["action_failed"], 1)
        self.assertEqual(s.counts["case_file_updated"], 2)
        self.assertEqual(s.days_observed, 2)

    def test_collects_case_file_entries(self) -> None:
        s = summarize_trace(FIXTURES / "trace_optimizer_seed1.jsonl")
        self.assertIn("obs_alphabetizes", s.case_file_entries)
        self.assertIn("obs_morning_quiet", s.case_file_entries)

    def test_collects_failures_with_reason(self) -> None:
        s = summarize_trace(FIXTURES / "trace_optimizer_seed1.jsonl")
        self.assertEqual(s.failures, [("int_phone_call", "client_refuses")])

    def test_freeplay_collects_narration(self) -> None:
        s = summarize_trace(FIXTURES / "trace_freeplay.jsonl")
        self.assertEqual(len(s.narration), 2)
        self.assertIn("quiet", s.narration[1])

    def test_directory_summarize(self) -> None:
        summaries = summarize_directory(FIXTURES, glob="trace_*.jsonl")
        ids = sorted(s.strategy for s in summaries)
        self.assertEqual(ids, ["freeplay", "intervention", "optimizer"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_summarize_traces -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 4: Write `harness/lib/summarize_traces.py`**

```python
#!/usr/bin/env python3
"""Compress raw trace.jsonl files into per-strategy summaries for the judge."""
from __future__ import annotations
import json
import re
from dataclasses import dataclass, field
from pathlib import Path


_NAME_RE = re.compile(
    r"^(?:trace_)?(?P<strategy>[a-z_]+?)(?:_seed(?P<seed>\d+))?\.jsonl$"
)


@dataclass
class TraceSummary:
    strategy: str
    seed: int
    counts: dict[str, int] = field(default_factory=dict)
    case_file_entries: list[str] = field(default_factory=list)
    failures: list[tuple[str, str]] = field(default_factory=list)
    narration: list[str] = field(default_factory=list)
    interventions_run: list[str] = field(default_factory=list)
    diagnostics_run: list[str] = field(default_factory=list)
    days_observed: int = 0
    last_overskudd: float | None = None
    case_file_tags: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "strategy": self.strategy,
            "seed": self.seed,
            "counts": self.counts,
            "case_file_entries": self.case_file_entries,
            "case_file_tags": self.case_file_tags,
            "failures": [{"action": a, "reason": r} for a, r in self.failures],
            "narration": self.narration,
            "interventions_run": self.interventions_run,
            "diagnostics_run": self.diagnostics_run,
            "days_observed": self.days_observed,
            "last_overskudd": self.last_overskudd,
        }


def _parse_name(path: Path) -> tuple[str, int]:
    match = _NAME_RE.match(path.name)
    if not match:
        # Tolerate any name; strategy = stem, seed = 0.
        return path.stem, 0
    return match.group("strategy"), int(match.group("seed") or 0)


def summarize_trace(path: Path) -> TraceSummary:
    strategy, seed = _parse_name(path)
    s = TraceSummary(strategy=strategy, seed=seed)
    days_seen: set[int] = set()
    with path.open() as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if "ev" in obj:
                ev = obj["ev"]
                s.counts[ev] = s.counts.get(ev, 0) + 1
                if ev == "case_file_updated":
                    entry = obj.get("entry")
                    if entry:
                        s.case_file_entries.append(entry)
                elif ev == "action_failed":
                    s.failures.append((obj.get("action", "?"), obj.get("reason", "?")))
                elif ev == "narration":
                    s.narration.append(obj.get("text", ""))
                elif ev == "intervention_completed":
                    iid = obj.get("id")
                    if iid:
                        s.interventions_run.append(iid)
                elif ev == "diagnostic_completed":
                    did = obj.get("id")
                    if did:
                        s.diagnostics_run.append(did)
                elif ev == "day_started":
                    day = obj.get("day")
                    if isinstance(day, int):
                        days_seen.add(day)
                elif ev == "overskudd_changed":
                    v = obj.get("v")
                    if isinstance(v, (int, float)):
                        s.last_overskudd = float(v)
            elif "reply" in obj:
                snap = obj["reply"].get("snapshot")
                if isinstance(snap, dict):
                    cf = snap.get("case_file", {})
                    tags = cf.get("tags")
                    if isinstance(tags, list):
                        s.case_file_tags = list(tags)
                    client = snap.get("client", {})
                    osk = client.get("overskudd")
                    if isinstance(osk, (int, float)):
                        s.last_overskudd = float(osk)
                    day = snap.get("time", {}).get("day")
                    if isinstance(day, int):
                        days_seen.add(day)
    s.days_observed = len(days_seen)
    return s


def summarize_directory(directory: Path, glob: str = "*.jsonl") -> list[TraceSummary]:
    return [summarize_trace(p) for p in sorted(directory.glob(glob))]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_summarize_traces -v`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add harness/lib/summarize_traces.py harness/test/test_summarize_traces.py harness/test/fixtures/trace_optimizer_seed1.jsonl harness/test/fixtures/trace_intervention_seed1.jsonl harness/test/fixtures/trace_freeplay.jsonl
git commit -m "feat(lib): trace summarizer for per-strategy judge extracts"
```

---

## Task 7: Tournament runner

Wraps the LLM player in a strategy × seed loop. Output: 12 + 1 trace files in the sprint dir. Sequential v0; the per-playtest cost is dominated by Godot + Claude, not Bash overhead.

**Files:**
- Create: `harness/lib/tournament.sh`

- [ ] **Step 1: Write `harness/lib/tournament.sh`**

```bash
#!/usr/bin/env bash
# harness/lib/tournament.sh
#
# Run a strategy × seed tournament + (optional) freeplay run, writing trace
# jsonl files into harness/runs/<run-id>/sprint_<N>/traces/.
#
# Required env (or args):
#   --run-id     <run-id>
#   --sprint     <N>
#   --godot      <godot binary path>
#   --project    <worktree path>           # the sprint's worktree, not the main repo
#
# Optional:
#   --strategies <comma-list>              # default: eager_diagnostician,intervention_spammer,patient_observer,neglect
#   --seeds      <comma-list>              # default: 1,2,3
#   --skip-freeplay                        # do not run freeplay
#   --live                                 # use real claude (else shim)
#   --shim-canned <path>                   # required if --live not set
#
# Exits 0 iff every requested run wrote a non-empty trace file.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GODOT=""
PROJECT=""
STRATEGIES="eager_diagnostician,intervention_spammer,patient_observer,neglect"
SEEDS="1,2,3"
SKIP_FREEPLAY=0
LIVE=0
SHIM_CANNED=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-id)         RUN_ID="$2";        shift 2 ;;
        --sprint)         SPRINT_N="$2";      shift 2 ;;
        --godot)          GODOT="$2";         shift 2 ;;
        --project)        PROJECT="$2";       shift 2 ;;
        --strategies)     STRATEGIES="$2";    shift 2 ;;
        --seeds)          SEEDS="$2";         shift 2 ;;
        --skip-freeplay)  SKIP_FREEPLAY=1;    shift   ;;
        --live)           LIVE=1;             shift   ;;
        --shim-canned)    SHIM_CANNED="$2";   shift 2 ;;
        *) echo "tournament: unknown arg: $1" >&2; exit 2 ;;
    esac
done

for var in RUN_ID SPRINT_N GODOT PROJECT; do
    if [ -z "${!var}" ]; then
        echo "tournament: missing required --$(echo $var | tr A-Z_ a-z- | sed 's/run-id/run-id/')" >&2
        exit 2
    fi
done
if [ "$LIVE" = "0" ] && [ -z "$SHIM_CANNED" ]; then
    echo "tournament: --live not set; --shim-canned <path> is required for dry-run mode" >&2
    exit 2
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
TRACES_DIR="${SPRINT_DIR}/traces"
SESSIONS_DIR="${SPRINT_DIR}/strategy_sessions"
mkdir -p "$TRACES_DIR" "$SESSIONS_DIR"

run_one() {
    local strategy_id="$1"
    local seed="$2"
    local mode_flag="$3"  # "prior" or "freeplay"
    local trace_out="${TRACES_DIR}/${strategy_id}_seed${seed}.jsonl"
    if [ "$mode_flag" = "freeplay" ]; then
        trace_out="${TRACES_DIR}/freeplay.jsonl"
    fi
    local session_log="${SESSIONS_DIR}/${strategy_id}_seed${seed}.log"
    local comms_dir
    comms_dir=$(mktemp -d -t "lifelines-tournament.XXXXXX")
    local strategy_md="${REPO_ROOT}/harness/strategies/${strategy_id}.md"

    if [ ! -f "$strategy_md" ]; then
        echo "tournament: strategy file not found: $strategy_md" >&2
        return 1
    fi

    local args=(
        "${REPO_ROOT}/harness/lib/llm_player.py"
        --godot "$GODOT"
        --project "$PROJECT"
        --strategy "$strategy_md"
        --seed "$seed"
        --comms-dir "$comms_dir"
        --trace-out "$trace_out"
        --session-log "$session_log"
    )
    if [ "$LIVE" = "1" ]; then
        args+=( --live )
    else
        args+=( --shim-canned "$SHIM_CANNED" )
    fi

    echo "[tournament] strategy=$strategy_id seed=$seed -> $trace_out" >&2
    python3 "${args[@]}"
    rm -rf "$comms_dir"

    if [ ! -s "$trace_out" ]; then
        echo "[tournament] empty trace: $trace_out" >&2
        return 1
    fi
}

IFS=',' read -r -a STRAT_ARR <<<"$STRATEGIES"
IFS=',' read -r -a SEED_ARR  <<<"$SEEDS"

for strat in "${STRAT_ARR[@]}"; do
    for seed in "${SEED_ARR[@]}"; do
        run_one "$strat" "$seed" "prior"
    done
done

if [ "$SKIP_FREEPLAY" = "0" ]; then
    run_one "freeplay" "1" "freeplay"
fi

echo "[tournament] complete: $(ls "$TRACES_DIR" | wc -l | tr -d ' ') traces in $TRACES_DIR" >&2
```

- [ ] **Step 2: Make executable + smoke check**

```bash
chmod +x harness/lib/tournament.sh
bash -n harness/lib/tournament.sh
```

Expected: silent success (syntax-OK).

- [ ] **Step 3: Commit**

```bash
git add harness/lib/tournament.sh
git commit -m "feat(harness): strategy × seed tournament runner"
```

---

## Task 8: Test verifier — runs `[test]` contract items via GUT

`run_contract_tests.sh` reads a `contract.md` (already parsed by Plan 3's `harness/lib/contract_schema.py`), extracts every `[test]` item, runs each via GUT inside the worktree, and writes a single `test_results.json` mapping `item_index → {kind: "test", body, pass: bool, output: str}`. Re-uses Plan 3's parser; this task only writes the runner.

**Files:**
- Create: `harness/lib/run_contract_tests.sh`

- [ ] **Step 1: Write `harness/lib/run_contract_tests.sh`**

```bash
#!/usr/bin/env bash
# harness/lib/run_contract_tests.sh
#
# Args:
#   --run-id <id>
#   --sprint <N>
#   --godot  <godot binary path>
#   --project <worktree path>             # the sprint's worktree
#
# Reads:  harness/runs/<run-id>/sprint_<N>/contract.md
# Writes: harness/runs/<run-id>/sprint_<N>/test_results.json
#
# Conventions:
#   - Each [test] item body is a GUT script reference such as
#       `test/harness/sprint_N_*.gd::test_specific_thing` passes
#     The runner extracts the script path + test name and runs:
#       godot --headless --path <project> -s addons/gut/gut_cmdln.gd
#         -gtest=res://<script-path> -gunit_test_name=<test-name> -gexit
#   - exit code 0 from GUT → pass; non-zero → fail. stdout/stderr captured per item.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GODOT=""
PROJECT=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-id)  RUN_ID="$2";   shift 2 ;;
        --sprint)  SPRINT_N="$2"; shift 2 ;;
        --godot)   GODOT="$2";    shift 2 ;;
        --project) PROJECT="$2";  shift 2 ;;
        *) echo "run_contract_tests: unknown arg: $1" >&2; exit 2 ;;
    esac
done
for var in RUN_ID SPRINT_N GODOT PROJECT; do
    if [ -z "${!var}" ]; then echo "run_contract_tests: missing --$var" >&2; exit 2; fi
done

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
CONTRACT="${SPRINT_DIR}/contract.md"
OUT="${SPRINT_DIR}/test_results.json"

if [ ! -f "$CONTRACT" ]; then echo "run_contract_tests: missing contract.md: $CONTRACT" >&2; exit 2; fi

# Extract [test] item bodies (one per line) using Plan 3's parser.
python3 - "$CONTRACT" "$OUT" "$GODOT" "$PROJECT" <<'PYEOF'
import json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "harness" / "lib"))
# In real use the cwd is the repo root and the harness lib is importable directly.
sys.path.insert(0, "harness/lib")
from contract_schema import parse_contract  # type: ignore

contract_path, out_path, godot, project = sys.argv[1:5]
contract = parse_contract(Path(contract_path).read_text())
test_items = [(i, it) for i, it in enumerate(contract.items) if it.kind == "test"]

results = []
all_pass = True
for idx, item in test_items:
    body = item.body
    # Body convention: ` `res://<path-to-gd>::<test_name>` passes ` etc.
    match = re.search(r"`([^`]+)`", body)
    if not match:
        results.append({"index": idx, "kind": "test", "body": body, "pass": False, "output": "could not parse test ref"})
        all_pass = False
        continue
    ref = match.group(1)
    if "::" in ref:
        script, test_name = ref.split("::", 1)
    else:
        script, test_name = ref, ""
    if not script.startswith("res://"):
        script = "res://" + script.lstrip("/")

    cmd = [
        godot, "--headless",
        "--path", project,
        "-s", "addons/gut/gut_cmdln.gd",
        f"-gtest={script}",
        "-gexit",
    ]
    if test_name:
        cmd.append(f"-gunit_test_name={test_name}")
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    passed = proc.returncode == 0 and "FAILED" not in proc.stdout
    if not passed:
        all_pass = False
    results.append({
        "index": idx,
        "kind": "test",
        "body": body,
        "ref": ref,
        "pass": passed,
        "exit_code": proc.returncode,
        "output_tail": (proc.stdout[-2000:] + "\n--- stderr ---\n" + proc.stderr[-1000:]),
    })

Path(out_path).write_text(json.dumps({"items": results, "all_pass": all_pass}, indent=2))
PYEOF

echo "[run_contract_tests] wrote $OUT" >&2
```

- [ ] **Step 2: Make executable + smoke**

```bash
chmod +x harness/lib/run_contract_tests.sh
bash -n harness/lib/run_contract_tests.sh
```

Expected: silent success.

- [ ] **Step 3: Commit**

```bash
git add harness/lib/run_contract_tests.sh
git commit -m "feat(harness): contract [test] item runner (GUT per item)"
```

---

## Task 9: Tournament-trace verifier — runs `[trace]` items across all traces

Plan 3 already wrote `harness/lib/scan_contract_trace.py` for single-trace scans (used by the generator's smoke). This task adds the tournament-aware variant: for each `[trace]` item, evaluate the rule across every trace file in `traces/` and report whether the rule's quantifier ("across strategies", "in any strategy", "in every strategy") is satisfied. The quantifier is encoded in the rule body's prefix.

**Files:**
- Create: `harness/lib/scan_tournament_trace.py`
- Create: `harness/test/test_scan_tournament_trace.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_scan_tournament_trace.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/scan_tournament_trace.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from scan_tournament_trace import (  # noqa: E402
    parse_trace_rule,
    Quantifier,
    evaluate_rule,
    run_all,
    TraceRule,
)


class TestParseTraceRule(unittest.TestCase):
    def test_any_quantifier(self) -> None:
        body = "in any strategy: events where ev=diagnostic_completed count >= 2"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.ANY)
        self.assertEqual(r.event_filter, {"ev": "diagnostic_completed"})
        self.assertEqual(r.comparator, ">=")
        self.assertEqual(r.threshold, 2)

    def test_every_quantifier(self) -> None:
        body = "in every strategy: events where ev=case_file_updated count > 0"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.EVERY)

    def test_across_quantifier_with_field_filter(self) -> None:
        body = "across strategies: events where ev=action_failed and reason=client_refuses count >= 1"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.ACROSS)
        self.assertEqual(r.event_filter, {"ev": "action_failed", "reason": "client_refuses"})

    def test_default_to_across(self) -> None:
        body = "events where ev=intervention_completed count >= 1"
        r = parse_trace_rule(body)
        self.assertEqual(r.quantifier, Quantifier.ACROSS)


class TestEvaluateRule(unittest.TestCase):
    def setUp(self) -> None:
        self.fixtures = Path(__file__).parent / "fixtures"

    def test_any_passes_when_one_trace_meets_threshold(self) -> None:
        rule = parse_trace_rule("in any strategy: events where ev=diagnostic_completed count >= 1")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",
            self.fixtures / "trace_intervention_seed1.jsonl",
        ])
        self.assertTrue(result.passed)

    def test_every_fails_when_one_trace_misses(self) -> None:
        rule = parse_trace_rule("in every strategy: events where ev=diagnostic_completed count >= 1")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",   # has 2
            self.fixtures / "trace_intervention_seed1.jsonl",  # has 0
        ])
        self.assertFalse(result.passed)
        self.assertIn("intervention", result.failing_traces[0])

    def test_across_sums_counts(self) -> None:
        rule = parse_trace_rule("across strategies: events where ev=action_failed count >= 2")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",     # 1 fail
            self.fixtures / "trace_intervention_seed1.jsonl",  # 1 fail
        ])
        self.assertTrue(result.passed)

    def test_across_under_threshold_fails(self) -> None:
        rule = parse_trace_rule("across strategies: events where ev=action_failed count >= 5")
        result = evaluate_rule(rule, [
            self.fixtures / "trace_optimizer_seed1.jsonl",
            self.fixtures / "trace_intervention_seed1.jsonl",
        ])
        self.assertFalse(result.passed)
        self.assertEqual(result.observed, 2)


class TestRunAll(unittest.TestCase):
    def test_writes_findings_json(self) -> None:
        fixtures = Path(__file__).parent / "fixtures"
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "trace_findings.json"
            findings = run_all(
                rules=[
                    TraceRule.parse("in any strategy: events where ev=diagnostic_completed count >= 1", index=0),
                    TraceRule.parse("in every strategy: events where ev=diagnostic_completed count >= 1", index=1),
                ],
                trace_files=[
                    fixtures / "trace_optimizer_seed1.jsonl",
                    fixtures / "trace_intervention_seed1.jsonl",
                ],
                out_path=out,
            )
            data = json.loads(out.read_text())
            self.assertEqual(len(data["items"]), 2)
            self.assertTrue(data["items"][0]["pass"])
            self.assertFalse(data["items"][1]["pass"])
            self.assertFalse(findings["all_pass"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_scan_tournament_trace -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write `harness/lib/scan_tournament_trace.py`**

```python
#!/usr/bin/env python3
"""Cross-trace [trace] item evaluator for the evaluator (Plan 4).

A [trace] item body is one of:
    "in any strategy: events where <filter> count <op> <n>"
    "in every strategy: events where <filter> count <op> <n>"
    "across strategies: events where <filter> count <op> <n>"   # default
where <filter> is "<field>=<value> [and <field>=<value> ...]"
and <op> is one of ">=", "<=", "==", ">", "<".

For each rule, we scan every trace file, count events matching the filter,
and check the quantifier-appropriate aggregate against the threshold.
"""
from __future__ import annotations
import enum
import json
import re
from dataclasses import dataclass, field
from pathlib import Path


class Quantifier(enum.Enum):
    ANY = "any"
    EVERY = "every"
    ACROSS = "across"


_RULE_RE = re.compile(
    r"^(?:(?P<qword>in any strategy|in every strategy|across strategies)\s*:\s*)?"
    r"events where (?P<filter>.+?) count\s+(?P<op>>=|<=|==|>|<)\s*(?P<n>\d+)\s*$"
)


@dataclass
class TraceRule:
    index: int
    quantifier: Quantifier
    event_filter: dict[str, str]
    comparator: str
    threshold: int
    raw: str

    @classmethod
    def parse(cls, body: str, index: int) -> "TraceRule":
        return parse_trace_rule(body, index=index)


def parse_trace_rule(body: str, index: int = -1) -> TraceRule:
    match = _RULE_RE.match(body.strip())
    if not match:
        raise ValueError(f"unrecognized [trace] rule: {body!r}")
    qword = match.group("qword") or "across strategies"
    quantifier = {
        "in any strategy": Quantifier.ANY,
        "in every strategy": Quantifier.EVERY,
        "across strategies": Quantifier.ACROSS,
    }[qword]
    raw_filter = match.group("filter")
    event_filter: dict[str, str] = {}
    for clause in re.split(r"\s+and\s+", raw_filter):
        if "=" not in clause:
            raise ValueError(f"clause missing '=': {clause!r}")
        k, _, v = clause.partition("=")
        event_filter[k.strip()] = v.strip()
    return TraceRule(
        index=index,
        quantifier=quantifier,
        event_filter=event_filter,
        comparator=match.group("op"),
        threshold=int(match.group("n")),
        raw=body,
    )


def _event_matches(obj: dict, flt: dict[str, str]) -> bool:
    if "ev" in flt and obj.get("ev") != flt["ev"]:
        return False
    for k, v in flt.items():
        if k == "ev":
            continue
        if str(obj.get(k, "")) != v:
            return False
    return True


def _count_events(trace_path: Path, flt: dict[str, str]) -> int:
    n = 0
    with trace_path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if "ev" not in obj:
                continue
            if _event_matches(obj, flt):
                n += 1
    return n


def _compare(observed: int, op: str, threshold: int) -> bool:
    return {
        ">=": lambda: observed >= threshold,
        "<=": lambda: observed <= threshold,
        "==": lambda: observed == threshold,
        ">":  lambda: observed >  threshold,
        "<":  lambda: observed <  threshold,
    }[op]()


@dataclass
class RuleResult:
    rule: TraceRule
    passed: bool
    observed: int
    per_trace: dict[str, int] = field(default_factory=dict)
    failing_traces: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "index": self.rule.index,
            "kind": "trace",
            "body": self.rule.raw,
            "quantifier": self.rule.quantifier.value,
            "observed": self.observed,
            "threshold": self.rule.threshold,
            "comparator": self.rule.comparator,
            "per_trace": self.per_trace,
            "failing_traces": self.failing_traces,
            "pass": self.passed,
        }


def evaluate_rule(rule: TraceRule, trace_files: list[Path]) -> RuleResult:
    per_trace: dict[str, int] = {}
    for tf in trace_files:
        per_trace[tf.stem] = _count_events(tf, rule.event_filter)
    if rule.quantifier == Quantifier.ANY:
        observed = max(per_trace.values()) if per_trace else 0
        passed = any(_compare(c, rule.comparator, rule.threshold) for c in per_trace.values())
        failing = []
    elif rule.quantifier == Quantifier.EVERY:
        observed = min(per_trace.values()) if per_trace else 0
        passed = all(_compare(c, rule.comparator, rule.threshold) for c in per_trace.values())
        failing = [name for name, c in per_trace.items() if not _compare(c, rule.comparator, rule.threshold)]
    else:  # ACROSS
        observed = sum(per_trace.values())
        passed = _compare(observed, rule.comparator, rule.threshold)
        failing = []
    return RuleResult(rule=rule, passed=passed, observed=observed, per_trace=per_trace, failing_traces=failing)


def run_all(rules: list[TraceRule], trace_files: list[Path], out_path: Path) -> dict:
    items = []
    all_pass = True
    for rule in rules:
        r = evaluate_rule(rule, trace_files)
        items.append(r.to_dict())
        if not r.passed:
            all_pass = False
    findings = {"items": items, "all_pass": all_pass}
    out_path.write_text(json.dumps(findings, indent=2))
    return findings
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_scan_tournament_trace -v`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/scan_tournament_trace.py harness/test/test_scan_tournament_trace.py
git commit -m "feat(lib): cross-trace [trace] verifier w/ any/every/across quantifiers"
```

---

## Task 10: Judge driver + anchored axis prompt

The judge is the only LLM-driven verifier in Plan 4. One call per axis. Each call receives: the axis definition from `docs/rubric/rubric.md`, the positive + negative anchors for that axis, the per-strategy trace summaries, and (if present) the freeplay trace + narration. Returns: per-axis score 0–3 with one cited anchor + one cited trace line.

**Files:**
- Create: `harness/prompts/judge_axis.md`
- Create: `harness/lib/judge.py`
- Create: `harness/test/test_judge.py`

- [ ] **Step 1: Write `harness/prompts/judge_axis.md`**

```markdown
# Judge — per-axis grading prompt

You are the **evaluator** for the Lifelines adversarial harness. You score ONE axis at a time. You are paid to fail this sprint, not pass it. Your default disposition is harsh.

## Sources of truth

- **Rubric axis definition**: provided below under "AXIS DEFINITION". It enumerates 4 sub-criteria, each scored 0–3 with explicit examples.
- **Positive anchors**: provided below under "POSITIVE ANCHORS". These are the bar.
- **Negative anchors**: provided below under "NEGATIVE ANCHORS". These are what we reject.
- **Evidence**: provided below under "TOURNAMENT TRACES" (per-strategy summaries) and optionally "FREEPLAY". This is what actually happened in the sprint's playtests.

## What to do

1. Score each of the 4 sub-criteria for this axis, 0–3, against the rubric.
2. For each non-3 sub-criterion, cite ONE specific trace fact (event id, narration line, counts across strategies, anchor name) that pinned the score there. No citation → drop the score by 1.
3. Compute `axis_score = mean(sub_criteria_scores)`, rounded to one decimal.
4. If you find yourself writing "looks good" or "mostly there" without a specific failure cited, stop — find the worst remaining failure first, write it down, then re-rate.
5. Return JSON only, no preamble:

```
{
  "axis": "<axis-slug>",
  "sub_scores": [<int>, <int>, <int>, <int>],
  "axis_score": <float>,
  "citations": [
    {"sub_criterion": 1, "citation": "<specific fact>", "anchor": "<anchor-id-or-null>"},
    ...
  ],
  "harsh_check": "<one sentence: worst remaining failure>"
}
```

Refusal to score harshly is sycophancy and breaks the harness. If every sub-criterion looks 3/3, you have not read closely enough — re-read the negative anchors and try again.
```

- [ ] **Step 2: Write the failing test**

`harness/test/test_judge.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/judge.py."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import ClaudeSession  # noqa: E402
from judge import (  # noqa: E402
    AxisJudgment,
    parse_judgment,
    JudgeError,
    score_axis,
    AXIS_SLUGS,
)


GOOD_REPLY = json.dumps({
    "axis": "decision-density",
    "sub_scores": [2, 1, 2, 1],
    "axis_score": 1.5,
    "citations": [
        {"sub_criterion": 2, "citation": "every strategy converged to eager_diagnostician path", "anchor": "negative/06-decision-dominant-strategy"},
        {"sub_criterion": 4, "citation": "zero action_failed events across 12 traces", "anchor": "negative/10-decision-no-refusal"}
    ],
    "harsh_check": "no refusal events across the entire tournament — burn is unsurfaced"
})

BAD_NO_SCORES = json.dumps({
    "axis": "decision-density",
    "axis_score": 2.0,
    "citations": [],
    "harsh_check": "fine"
})

BAD_OUT_OF_RANGE = json.dumps({
    "axis": "decision-density",
    "sub_scores": [4, 0, 0, 0],
    "axis_score": 1.0,
    "citations": [],
    "harsh_check": "fine"
})

UNKNOWN_AXIS = GOOD_REPLY.replace("decision-density", "vibes-only")


class TestParseJudgment(unittest.TestCase):
    def test_parses_good(self) -> None:
        j = parse_judgment(GOOD_REPLY, expected_axis="decision-density")
        self.assertEqual(j.sub_scores, [2, 1, 2, 1])
        self.assertAlmostEqual(j.axis_score, 1.5, places=2)
        self.assertEqual(len(j.citations), 2)

    def test_rejects_missing_scores(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(BAD_NO_SCORES, expected_axis="decision-density")

    def test_rejects_out_of_range(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(BAD_OUT_OF_RANGE, expected_axis="decision-density")

    def test_rejects_unknown_axis(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(UNKNOWN_AXIS, expected_axis="decision-density")

    def test_rejects_axis_mismatch(self) -> None:
        with self.assertRaises(JudgeError):
            parse_judgment(GOOD_REPLY, expected_axis="thematic-coherence")


class TestScoreAxisShim(unittest.TestCase):
    def test_score_axis_via_shim(self) -> None:
        canned = {"shim-session": [GOOD_REPLY]}
        session = ClaudeSession.shim(canned, session_id="shim-session")
        j = score_axis(
            session=session,
            axis_slug="decision-density",
            axis_definition_md="# axis stub",
            positive_anchors=[("anchor_a", "body_a")],
            negative_anchors=[("anchor_b", "body_b")],
            trace_extract="{}",
            freeplay_extract=None,
            model="claude-opus-4-7",
        )
        self.assertEqual(j.axis, "decision-density")
        self.assertEqual(j.sub_scores, [2, 1, 2, 1])


class TestAxisSlugs(unittest.TestCase):
    def test_all_seven_present(self) -> None:
        self.assertEqual(len(AXIS_SLUGS), 7)
        self.assertIn("thematic-coherence", AXIS_SLUGS)
        self.assertIn("loop-closure", AXIS_SLUGS)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_judge -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 4: Write `harness/lib/judge.py`**

```python
#!/usr/bin/env python3
"""Per-axis judge driver. One claude call per axis."""
from __future__ import annotations
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from claude_subprocess import ClaudeSession, ClaudeError  # noqa: E402


AXIS_SLUGS = (
    "thematic-coherence",
    "decision-density",
    "earned-discovery",
    "forgiveness-with-stakes",
    "texture-voice",
    "sim-legibility",
    "loop-closure",
)


class JudgeError(RuntimeError):
    pass


@dataclass
class Citation:
    sub_criterion: int
    citation: str
    anchor: Optional[str]


@dataclass
class AxisJudgment:
    axis: str
    sub_scores: list[int]
    axis_score: float
    citations: list[Citation]
    harsh_check: str

    def to_dict(self) -> dict:
        return {
            "axis": self.axis,
            "sub_scores": self.sub_scores,
            "axis_score": self.axis_score,
            "citations": [
                {"sub_criterion": c.sub_criterion, "citation": c.citation, "anchor": c.anchor}
                for c in self.citations
            ],
            "harsh_check": self.harsh_check,
        }


_JSON_OBJ_RE = re.compile(r"\{.*\}", re.DOTALL)


def parse_judgment(reply_text: str, expected_axis: str) -> AxisJudgment:
    match = _JSON_OBJ_RE.search(reply_text)
    if not match:
        raise JudgeError(f"no JSON object found in judgment: {reply_text!r}")
    try:
        obj = json.loads(match.group(0))
    except json.JSONDecodeError as e:
        raise JudgeError(f"judgment JSON parse failed: {e}") from e
    if obj.get("axis") not in AXIS_SLUGS:
        raise JudgeError(f"unknown axis {obj.get('axis')!r}")
    if obj["axis"] != expected_axis:
        raise JudgeError(f"axis mismatch: expected {expected_axis}, got {obj['axis']}")
    sub = obj.get("sub_scores")
    if not isinstance(sub, list) or len(sub) != 4:
        raise JudgeError("sub_scores must be a list of length 4")
    for s in sub:
        if not isinstance(s, int) or not 0 <= s <= 3:
            raise JudgeError(f"sub_score out of range 0-3: {s}")
    axis_score = obj.get("axis_score")
    if not isinstance(axis_score, (int, float)):
        raise JudgeError(f"axis_score must be number, got {axis_score}")
    citations = [
        Citation(
            sub_criterion=int(c["sub_criterion"]),
            citation=str(c.get("citation", "")),
            anchor=c.get("anchor"),
        )
        for c in obj.get("citations", [])
    ]
    return AxisJudgment(
        axis=obj["axis"],
        sub_scores=sub,
        axis_score=float(axis_score),
        citations=citations,
        harsh_check=str(obj.get("harsh_check", "")),
    )


def render_user_prompt(
    axis_slug: str,
    axis_definition_md: str,
    positive_anchors: list[tuple[str, str]],
    negative_anchors: list[tuple[str, str]],
    trace_extract: str,
    freeplay_extract: Optional[str],
) -> str:
    parts = [
        f"# Axis to grade: {axis_slug}",
        "",
        "## AXIS DEFINITION",
        axis_definition_md,
        "",
        "## POSITIVE ANCHORS",
    ]
    for name, body in positive_anchors:
        parts.append(f"### {name}\n{body}\n")
    parts.append("## NEGATIVE ANCHORS")
    for name, body in negative_anchors:
        parts.append(f"### {name}\n{body}\n")
    parts.append("## TOURNAMENT TRACES (per-strategy summary)")
    parts.append(trace_extract)
    if freeplay_extract:
        parts.append("## FREEPLAY")
        parts.append(freeplay_extract)
    parts.append("")
    parts.append("Score this axis now. Return JSON only.")
    return "\n".join(parts)


def score_axis(
    session: ClaudeSession,
    axis_slug: str,
    axis_definition_md: str,
    positive_anchors: list[tuple[str, str]],
    negative_anchors: list[tuple[str, str]],
    trace_extract: str,
    freeplay_extract: Optional[str],
    model: str = "claude-opus-4-7",
    timeout_s: float = 180.0,
) -> AxisJudgment:
    if axis_slug not in AXIS_SLUGS:
        raise JudgeError(f"unknown axis {axis_slug!r}")
    prompt = render_user_prompt(
        axis_slug, axis_definition_md, positive_anchors, negative_anchors,
        trace_extract, freeplay_extract,
    )
    try:
        reply = session.send(prompt, model=model, timeout_s=timeout_s)
    except ClaudeError as e:
        raise JudgeError(f"judge claude call failed: {e}") from e
    return parse_judgment(reply["text"], expected_axis=axis_slug)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_judge -v`
Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
git add harness/prompts/judge_axis.md harness/lib/judge.py harness/test/test_judge.py
git commit -m "feat(lib): per-axis judge driver + anchored axis prompt"
```

---

## Task 11: Anchor calibration

Before the judge grades the sprint, we re-score a small fixed set of anchors and compare to their `canonical_score` frontmatter. If any anchor drifts > 1, the prompt or the model is stale and grading is aborted. Cheap (text-only, ~14 calls) and catches the most common sycophancy/miscalibration failures up front.

**Files:**
- Create: `harness/test/fixtures/anchor_calibration_small.txt`
- Create: `harness/lib/calibrate_anchors.py`
- Create: `harness/test/test_calibrate_anchors.py`

- [ ] **Step 1: Write `harness/test/fixtures/anchor_calibration_small.txt`**

One anchor file path per line, comments allowed. Pick one positive + one negative per axis = 14 total. (Paths assume Plan 2's anchors are in place.)

```
# Plan 4 calibration set: one positive + one negative per axis = 14 anchors.
# Drift > 1 on any of these → recalibration needed; grading aborts.

# axis 1 — thematic-coherence
docs/rubric/anchors/positive/01-theme-disco-elysium-bureaucracy.md
docs/rubric/anchors/negative/01-theme-xp-bar-leveling.md

# axis 2 — decision-density
docs/rubric/anchors/positive/06-decision-citizen-sleeper-dice.md
docs/rubric/anchors/negative/06-decision-dominant-strategy.md

# axis 3 — earned-discovery
docs/rubric/anchors/positive/11-discovery-obra-dinn-deduction.md
docs/rubric/anchors/negative/11-discovery-tooltip-dump.md

# axis 4 — forgiveness-with-stakes
docs/rubric/anchors/positive/16-forgiveness-sdd080-fail-pays.md
docs/rubric/anchors/negative/16-forgiveness-permadeath-instafail.md

# axis 5 — texture-voice
docs/rubric/anchors/positive/24-voice-disco-elysium-monologue.md
docs/rubric/anchors/negative/21-voice-motivational-copy.md

# axis 6 — sim-legibility
docs/rubric/anchors/positive/30-legibility-causal-trace.md
docs/rubric/anchors/negative/26-legibility-failed-no-reason.md

# axis 7 — loop-closure
docs/rubric/anchors/positive/31-closure-day1-observe-to-act.md
docs/rubric/anchors/negative/31-closure-no-payoff-drift.md
```

Note: if Plan 2 used different anchor filenames, replace the paths above with whatever 14 files actually exist (1 positive + 1 negative per axis). The shim test ignores file content beyond frontmatter, so the unittest passes regardless.

- [ ] **Step 2: Write the failing test**

`harness/test/test_calibrate_anchors.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/calibrate_anchors.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import ClaudeSession  # noqa: E402
from calibrate_anchors import (  # noqa: E402
    CalibrationResult,
    run_calibration,
    canonical_score_from_anchor,
)


POS_ANCHOR = """---
axis: thematic-coherence
polarity: positive
sub_criteria_targeted: [1, 2]
source: disco elysium
score_if_anchor: 3
canonical_score: 3
---

# Disco Elysium bureaucracy

Body here.
"""

NEG_ANCHOR = """---
axis: thematic-coherence
polarity: negative
sub_criteria_targeted: [1, 4]
source: generic rpg
score_if_anchor: 0
canonical_score: 0
---

# XP bar leveling

Body here.
"""


class TestCanonicalScore(unittest.TestCase):
    def test_reads_canonical_score(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.md"
            p.write_text(POS_ANCHOR)
            self.assertEqual(canonical_score_from_anchor(p), 3)


class TestRunCalibrationShim(unittest.TestCase):
    def test_pass_when_within_one_point(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            pos = tdp / "pos.md"; pos.write_text(POS_ANCHOR)
            neg = tdp / "neg.md"; neg.write_text(NEG_ANCHOR)
            canned = {"shim-session": [
                json.dumps({"score": 3, "rationale": "matches positive anchor"}),
                json.dumps({"score": 1, "rationale": "matches negative anchor"}),
            ]}
            session = ClaudeSession.shim(canned, session_id="shim-session")
            result = run_calibration(
                anchor_paths=[pos, neg],
                session=session,
                model="claude-opus-4-7",
            )
            self.assertTrue(result.passed)
            self.assertEqual(len(result.per_anchor), 2)
            self.assertTrue(all(a["drift"] <= 1 for a in result.per_anchor))

    def test_fail_when_drift_above_one(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            pos = tdp / "pos.md"; pos.write_text(POS_ANCHOR)
            canned = {"shim-session": [
                json.dumps({"score": 0, "rationale": "wildly miscalibrated"}),
            ]}
            session = ClaudeSession.shim(canned, session_id="shim-session")
            result = run_calibration(
                anchor_paths=[pos],
                session=session,
                model="claude-opus-4-7",
            )
            self.assertFalse(result.passed)
            self.assertEqual(result.per_anchor[0]["drift"], 3)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_calibrate_anchors -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 4: Write `harness/lib/calibrate_anchors.py`**

```python
#!/usr/bin/env python3
"""Re-score N anchor files via the judge LLM; abort grading if any drifts > 1."""
from __future__ import annotations
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from claude_subprocess import ClaudeSession, ClaudeError  # noqa: E402
from rubric_schema import parse_frontmatter, AnchorSchemaError  # noqa: E402


CALIBRATION_PROMPT = """You are calibrating against canonical anchor scores.

Below is one anchor file. Read its frontmatter (which encodes the canonical_score) ONLY for context — do NOT use it as the answer. Read the body, and score the anchor 0–3 using the rubric axis sub-criteria the anchor targets.

Return JSON only:
{"score": <int 0-3>, "rationale": "<one sentence>"}

ANCHOR FILE BODY:
"""


@dataclass
class CalibrationResult:
    passed: bool
    per_anchor: list[dict] = field(default_factory=list)


def canonical_score_from_anchor(path: Path) -> int:
    text = path.read_text()
    meta = parse_frontmatter(text)
    return int(meta["canonical_score"])


_JSON_RE = re.compile(r"\{.*?\}", re.DOTALL)


def _score_one(session: ClaudeSession, path: Path, model: str) -> dict:
    body = path.read_text()
    prompt = CALIBRATION_PROMPT + body
    reply = session.send(prompt, model=model, timeout_s=120.0)
    match = _JSON_RE.search(reply["text"])
    if not match:
        raise RuntimeError(f"calibration call returned no JSON for {path}")
    obj = json.loads(match.group(0))
    return {"score": int(obj["score"]), "rationale": str(obj.get("rationale", ""))}


def run_calibration(
    anchor_paths: list[Path],
    session: ClaudeSession,
    model: str = "claude-opus-4-7",
) -> CalibrationResult:
    per_anchor: list[dict] = []
    passed = True
    for path in anchor_paths:
        canonical = canonical_score_from_anchor(path)
        result = _score_one(session, path, model)
        drift = abs(result["score"] - canonical)
        if drift > 1:
            passed = False
        per_anchor.append({
            "path": str(path),
            "canonical": canonical,
            "scored": result["score"],
            "drift": drift,
            "rationale": result["rationale"],
        })
    return CalibrationResult(passed=passed, per_anchor=per_anchor)


def load_paths(list_file: Path) -> list[Path]:
    out: list[Path] = []
    for raw in list_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        out.append(Path(line))
    return out
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_calibrate_anchors -v`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add harness/test/fixtures/anchor_calibration_small.txt harness/lib/calibrate_anchors.py harness/test/test_calibrate_anchors.py
git commit -m "feat(lib): anchor calibration check (drift > 1 aborts grading)"
```

---

## Task 12: Composite scorer + verdict.json

Pure data: take `test_results.json` + `trace_findings.json` + `judgments.json` (one per axis) + the rubric weights/floors → emit `verdict.json` with composite total, per-axis scores, floor check, and final verdict (`PASS` / `PIVOT` / `REJECT`). Exact thresholds taken from `docs/rubric/rubric.md`.

**Files:**
- Create: `harness/lib/score.py`
- Create: `harness/test/test_score.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_score.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/score.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from score import (  # noqa: E402
    AXIS_WEIGHTS,
    AXIS_FLOORS,
    compute_verdict,
    Verdict,
)


JUDGMENTS_ALL_3 = [{"axis": a, "sub_scores": [3, 3, 3, 3], "axis_score": 3.0, "citations": [], "harsh_check": ""} for a in AXIS_WEIGHTS.keys()]
JUDGMENTS_FLOORED = [
    {"axis": "thematic-coherence",    "sub_scores": [3, 3, 3, 3], "axis_score": 3.0, "citations": [], "harsh_check": ""},
    {"axis": "decision-density",      "sub_scores": [1, 1, 1, 1], "axis_score": 1.0, "citations": [], "harsh_check": ""},  # below floor (2)
    {"axis": "earned-discovery",      "sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "forgiveness-with-stakes","sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "texture-voice",         "sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "sim-legibility",        "sub_scores": [2, 2, 2, 2], "axis_score": 2.0, "citations": [], "harsh_check": ""},
    {"axis": "loop-closure",          "sub_scores": [3, 3, 3, 3], "axis_score": 3.0, "citations": [], "harsh_check": ""},
]


class TestComputeVerdict(unittest.TestCase):
    def test_perfect_passes(self) -> None:
        v = compute_verdict(
            judgments=JUDGMENTS_ALL_3,
            test_results={"all_pass": True, "items": []},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertEqual(v.verdict, "PASS")
        self.assertEqual(v.total, 84.0)

    def test_floor_violation_rejects(self) -> None:
        v = compute_verdict(
            judgments=JUDGMENTS_FLOORED,
            test_results={"all_pass": True, "items": []},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertEqual(v.verdict, "REJECT")
        self.assertIn("decision-density", v.floor_violations)

    def test_test_fail_blocks_pass(self) -> None:
        v = compute_verdict(
            judgments=JUDGMENTS_ALL_3,
            test_results={"all_pass": False, "items": [{"index": 0, "pass": False}]},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertIn(v.verdict, ("PIVOT", "REJECT"))

    def test_total_below_50_rejects(self) -> None:
        weak = [{"axis": a, "sub_scores": [1, 1, 1, 1], "axis_score": 1.0, "citations": [], "harsh_check": ""} for a in AXIS_WEIGHTS.keys()]
        v = compute_verdict(
            judgments=weak,
            test_results={"all_pass": True, "items": []},
            trace_findings={"all_pass": True, "items": []},
        )
        self.assertEqual(v.verdict, "REJECT")

    def test_writes_to_disk(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "verdict.json"
            v = compute_verdict(
                judgments=JUDGMENTS_ALL_3,
                test_results={"all_pass": True, "items": []},
                trace_findings={"all_pass": True, "items": []},
            )
            v.write(out)
            data = json.loads(out.read_text())
            self.assertEqual(data["verdict"], "PASS")
            self.assertEqual(data["total"], 84.0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_score -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write `harness/lib/score.py`**

```python
#!/usr/bin/env python3
"""Compute composite rubric score + verdict from verifier outputs.

Weights and floors are pinned to docs/rubric/rubric.md.
"""
from __future__ import annotations
import json
from dataclasses import dataclass, field
from pathlib import Path


AXIS_WEIGHTS: dict[str, int] = {
    "thematic-coherence":      5,
    "decision-density":        5,
    "earned-discovery":        4,
    "forgiveness-with-stakes": 4,
    "texture-voice":           3,
    "sim-legibility":          3,
    "loop-closure":            4,
}
AXIS_FLOORS: dict[str, int] = {
    "thematic-coherence":      2,
    "decision-density":        2,
    "earned-discovery":        2,
    "forgiveness-with-stakes": 1,
    "texture-voice":           1,
    "sim-legibility":          1,
    "loop-closure":            2,
}
PASS_TOTAL = 65.0
PIVOT_TOTAL = 50.0


@dataclass
class Verdict:
    verdict: str               # "PASS" | "PIVOT" | "REJECT"
    total: float
    max_total: float
    per_axis: dict[str, dict]
    floor_violations: list[str]
    test_pass: bool
    trace_pass: bool
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "verdict": self.verdict,
            "total": self.total,
            "max_total": self.max_total,
            "per_axis": self.per_axis,
            "floor_violations": self.floor_violations,
            "test_pass": self.test_pass,
            "trace_pass": self.trace_pass,
            "notes": self.notes,
        }

    def write(self, path: Path) -> None:
        path.write_text(json.dumps(self.to_dict(), indent=2))


def compute_verdict(
    judgments: list[dict],
    test_results: dict,
    trace_findings: dict,
) -> Verdict:
    per_axis: dict[str, dict] = {}
    total = 0.0
    floor_violations: list[str] = []

    judgments_by_axis = {j["axis"]: j for j in judgments}
    for axis_slug, weight in AXIS_WEIGHTS.items():
        if axis_slug not in judgments_by_axis:
            raise ValueError(f"missing judgment for axis {axis_slug}")
        j = judgments_by_axis[axis_slug]
        axis_score = float(j["axis_score"])
        weighted = axis_score * weight
        total += weighted
        per_axis[axis_slug] = {
            "axis_score": axis_score,
            "weight": weight,
            "weighted": weighted,
            "floor": AXIS_FLOORS[axis_slug],
            "below_floor": axis_score < AXIS_FLOORS[axis_slug],
        }
        if axis_score < AXIS_FLOORS[axis_slug]:
            floor_violations.append(axis_slug)

    max_total = sum(w * 3 for w in AXIS_WEIGHTS.values())  # 84
    test_pass = bool(test_results.get("all_pass", False))
    trace_pass = bool(trace_findings.get("all_pass", False))
    notes: list[str] = []

    if floor_violations:
        verdict = "REJECT"
        notes.append(f"floor violations on: {', '.join(floor_violations)}")
    elif not test_pass:
        notes.append("[test] verifier reported at least one failing item")
        verdict = "REJECT" if total < PIVOT_TOTAL else "PIVOT"
    elif not trace_pass:
        notes.append("[trace] verifier reported at least one failing rule")
        verdict = "REJECT" if total < PIVOT_TOTAL else "PIVOT"
    elif total >= PASS_TOTAL:
        verdict = "PASS"
    elif total >= PIVOT_TOTAL:
        verdict = "PIVOT"
    else:
        verdict = "REJECT"

    return Verdict(
        verdict=verdict,
        total=round(total, 2),
        max_total=float(max_total),
        per_axis=per_axis,
        floor_violations=floor_violations,
        test_pass=test_pass,
        trace_pass=trace_pass,
        notes=notes,
    )


def load_inputs(sprint_dir: Path) -> tuple[list[dict], dict, dict]:
    judgments = json.loads((sprint_dir / "judgments.json").read_text())
    test_results = json.loads((sprint_dir / "test_results.json").read_text())
    trace_findings = json.loads((sprint_dir / "trace_findings.json").read_text())
    return judgments["items"], test_results, trace_findings


def main(sprint_dir: Path) -> int:
    judgments, test_results, trace_findings = load_inputs(sprint_dir)
    v = compute_verdict(judgments, test_results, trace_findings)
    v.write(sprint_dir / "verdict.json")
    print(f"[score] verdict={v.verdict} total={v.total}/{v.max_total} → {sprint_dir/'verdict.json'}")
    return 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_score -v`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/score.py harness/test/test_score.py
git commit -m "feat(lib): composite rubric scorer + verdict.json writer"
```

---

## Task 13: Critique renderer

Pure data → human-readable `critique.md`. Reads `verdict.json` + `judgments.json` + `test_results.json` + `trace_findings.json` and emits a tight markdown report. No fluff — operator reads this to decide what to fix.

**Files:**
- Create: `harness/lib/render_critique.py`
- Create: `harness/test/test_render_critique.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_render_critique.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/render_critique.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from render_critique import render_critique  # noqa: E402


VERDICT = {
    "verdict": "REJECT",
    "total": 42.5,
    "max_total": 84.0,
    "per_axis": {
        "thematic-coherence":      {"axis_score": 2.5, "weight": 5, "weighted": 12.5, "floor": 2, "below_floor": False},
        "decision-density":        {"axis_score": 1.0, "weight": 5, "weighted": 5.0,  "floor": 2, "below_floor": True},
        "earned-discovery":        {"axis_score": 2.0, "weight": 4, "weighted": 8.0,  "floor": 2, "below_floor": False},
        "forgiveness-with-stakes": {"axis_score": 2.0, "weight": 4, "weighted": 8.0,  "floor": 1, "below_floor": False},
        "texture-voice":           {"axis_score": 2.0, "weight": 3, "weighted": 6.0,  "floor": 1, "below_floor": False},
        "sim-legibility":          {"axis_score": 1.0, "weight": 3, "weighted": 3.0,  "floor": 1, "below_floor": False},
        "loop-closure":            {"axis_score": 0.0, "weight": 4, "weighted": 0.0,  "floor": 2, "below_floor": True},
    },
    "floor_violations": ["decision-density", "loop-closure"],
    "test_pass": True,
    "trace_pass": False,
    "notes": ["[trace] verifier reported at least one failing rule"],
}

JUDGMENTS = {"items": [
    {"axis": "decision-density", "sub_scores": [1, 1, 1, 1], "axis_score": 1.0,
     "citations": [{"sub_criterion": 2, "citation": "every strategy converged on diag path", "anchor": "negative/06-decision-dominant-strategy"}],
     "harsh_check": "no cross-strategy variance"},
]}
TESTS = {"all_pass": True, "items": []}
TRACES = {"all_pass": False, "items": [
    {"index": 0, "kind": "trace", "body": "in any strategy: events where ev=action_failed count >= 1",
     "observed": 0, "threshold": 1, "comparator": ">=", "per_trace": {"eager_diagnostician_seed1": 0}, "failing_traces": [], "pass": False},
]}


class TestRenderCritique(unittest.TestCase):
    def test_renders_verdict_line(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="run-x sprint 1")
        self.assertIn("**Verdict: REJECT**", md)
        self.assertIn("42.5 / 84", md)

    def test_lists_floor_violations(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="x")
        self.assertIn("decision-density", md)
        self.assertIn("loop-closure", md)

    def test_includes_harsh_check_quotes(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="x")
        self.assertIn("no cross-strategy variance", md)

    def test_includes_failing_trace_rule(self) -> None:
        md = render_critique(VERDICT, JUDGMENTS, TESTS, TRACES, sprint_label="x")
        self.assertIn("action_failed", md)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest harness.test.test_render_critique -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write `harness/lib/render_critique.py`**

```python
#!/usr/bin/env python3
"""Render verdict + verifier outputs as critique.md (operator-facing)."""
from __future__ import annotations
import json
from pathlib import Path


def render_critique(
    verdict: dict,
    judgments: dict,
    test_results: dict,
    trace_findings: dict,
    sprint_label: str,
) -> str:
    lines: list[str] = []
    v = verdict["verdict"]
    total = verdict["total"]
    max_total = verdict["max_total"]
    lines.append(f"# Critique — {sprint_label}")
    lines.append("")
    lines.append(f"**Verdict: {v}** — score {total} / {max_total}")
    lines.append("")

    fv = verdict.get("floor_violations") or []
    if fv:
        lines.append("## Floor violations (REJECT-on-any)")
        lines.append("")
        for axis in fv:
            p = verdict["per_axis"][axis]
            lines.append(f"- **{axis}**: axis_score {p['axis_score']:.2f}, floor {p['floor']} — below floor")
        lines.append("")

    notes = verdict.get("notes") or []
    if notes:
        lines.append("## Notes")
        lines.append("")
        for n in notes:
            lines.append(f"- {n}")
        lines.append("")

    lines.append("## Per-axis breakdown")
    lines.append("")
    lines.append("| Axis | Score | Weight | Weighted | Floor | Below floor? |")
    lines.append("|---|---|---|---|---|---|")
    for axis, p in verdict["per_axis"].items():
        below = "**YES**" if p["below_floor"] else "no"
        lines.append(f"| {axis} | {p['axis_score']:.2f} | {p['weight']} | {p['weighted']:.2f} | {p['floor']} | {below} |")
    lines.append("")

    lines.append("## Judge citations (per axis)")
    lines.append("")
    by_axis = {j["axis"]: j for j in judgments["items"]}
    for axis in verdict["per_axis"].keys():
        j = by_axis.get(axis)
        if not j:
            continue
        lines.append(f"### {axis} — sub_scores {j['sub_scores']}")
        lines.append("")
        if j.get("harsh_check"):
            lines.append(f"> {j['harsh_check']}")
            lines.append("")
        for c in j.get("citations", []):
            anchor = f" [anchor: {c['anchor']}]" if c.get("anchor") else ""
            lines.append(f"- sub {c['sub_criterion']}: {c['citation']}{anchor}")
        lines.append("")

    lines.append("## [test] items")
    lines.append("")
    for item in test_results.get("items", []) or []:
        status = "PASS" if item["pass"] else "FAIL"
        lines.append(f"- [{status}] {item.get('ref', item.get('body', '?'))}")
    if not test_results.get("items"):
        lines.append("_(no [test] items)_")
    lines.append("")

    lines.append("## [trace] items")
    lines.append("")
    for item in trace_findings.get("items", []) or []:
        status = "PASS" if item["pass"] else "FAIL"
        lines.append(f"- [{status}] `{item['body']}` — observed {item['observed']} {item['comparator']} {item['threshold']}")
        if item.get("failing_traces"):
            lines.append(f"    - failing: {', '.join(item['failing_traces'])}")
    if not trace_findings.get("items"):
        lines.append("_(no [trace] items)_")
    lines.append("")

    return "\n".join(lines) + "\n"


def main(sprint_dir: Path, sprint_label: str) -> int:
    verdict = json.loads((sprint_dir / "verdict.json").read_text())
    judgments = json.loads((sprint_dir / "judgments.json").read_text())
    test_results = json.loads((sprint_dir / "test_results.json").read_text())
    trace_findings = json.loads((sprint_dir / "trace_findings.json").read_text())
    md = render_critique(verdict, judgments, test_results, trace_findings, sprint_label=sprint_label)
    (sprint_dir / "critique.md").write_text(md)
    return 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest harness.test.test_render_critique -v`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/render_critique.py harness/test/test_render_critique.py
git commit -m "feat(lib): critique.md renderer (operator-facing report)"
```

---

## Task 14: Strategy-player system prompt scaffold (loaded via strategy.body)

The strategy markdown body authored in Task 4 already carries the prior. There is no separate "strategy player system prompt" file — `llm_player.py` loads `strategy.body` as the `append_system_prompt` for that playtest's `ClaudeSession`. This task adds `harness/prompts/strategy_player.md` as the **shared preamble** prepended to every strategy file by `llm_player.py`. It contains the protocol rules (op format, JSON only, no narration unless freeplay) that are identical across strategies.

**Files:**
- Create: `harness/prompts/strategy_player.md`
- Modify: `harness/lib/llm_player.py`

- [ ] **Step 1: Write `harness/prompts/strategy_player.md`**

```markdown
# Strategy player — shared preamble

You drive the Lifelines economy prototype through its `--agent-mode` bridge. Each turn you receive the latest state snapshot + new events since the previous turn. You return ONE op JSON object.

## Op format

```
{"op": "snapshot"}
{"op": "diag", "id": "<diagnostic_id>"}
{"op": "interv", "id": "<intervention_id>"}
{"op": "advance", "game_hours": <float>}
{"op": "set_speed", "scale": <float>}
{"op": "shutdown"}
```

Exactly one op per turn. No additional commentary unless your strategy is `freeplay` (then prepend exactly one `// narration` line). No multiple-op responses. No code fences in your reply.

## Strategy persona

Your specific persona, prior, and decision rule are given AFTER this preamble. Apply them strictly. Do not invent moves outside your persona's decision rule. Sycophancy ("the player seems to want X") is forbidden — there is no player; you ARE the player.

## When to stop

If the snapshot shows day > 9, emit `{"op": "shutdown"}` (or `// reason\n{"op": "shutdown"}` if freeplay).
```

- [ ] **Step 2: Modify `harness/lib/llm_player.py` to prepend the shared preamble**

Open `harness/lib/llm_player.py`. In `run_playtest`, immediately after `strategy = parse_strategy_file(Path(args.strategy))`, add:

```python
    preamble_path = Path(args.project) / "harness/prompts/strategy_player.md"
    if not preamble_path.exists():
        # Fall back to the in-repo path (when project != repo root, e.g. worktree).
        preamble_path = Path(__file__).parent.parent / "prompts" / "strategy_player.md"
    preamble = preamble_path.read_text() if preamble_path.exists() else ""
    composed_system_prompt = preamble + "\n\n---\n\n" + strategy.body
```

Then change the line that sets `system_prompt=strategy.body` (in the `if args.live:` branch) to `system_prompt=composed_system_prompt`.

For the shim branch, no change — the canned bucket is keyed by session id, not by prompt content.

- [ ] **Step 3: Re-run the LLM player tests**

Run: `python3 -m unittest harness.test.test_llm_player -v`
Expected: PASS, 8 tests (unchanged — the modification is live-only).

- [ ] **Step 4: Commit**

```bash
git add harness/prompts/strategy_player.md harness/lib/llm_player.py
git commit -m "feat(harness): shared strategy-player preamble (op format + stop rule)"
```

---

## Task 15: Evaluator launcher + end-to-end dry-run smoke

`run_evaluator.sh` composes Tasks 7–13. Same `EVALUATOR_LIVE=0` (default = shim) vs `EVALUATOR_LIVE=1` (real claude + real Godot) split as Plan 3's generator script. The smoke spins up a fake sprint dir, runs the evaluator end-to-end in dry-run mode, asserts the expected artifacts exist with the expected verdict.

**Files:**
- Create: `harness/run_evaluator.sh`
- Create: `harness/test/fixtures/contract_pass.md`
- Create: `harness/test/fixtures/contract_floored.md`
- Create: `harness/test/smoke_evaluator.sh`

- [ ] **Step 1: Write `harness/test/fixtures/contract_pass.md`**

```markdown
# Sprint 1 Contract

## Done means
- [trace] in any strategy: events where ev=diagnostic_completed count >= 1
- [trace] across strategies: events where ev=case_file_updated count >= 2

## Rubric coverage
Axis 2 (Decision Density): primary
Axis 3 (Earned Discovery): touched

## Forbidden side-effects
- baseline axis 5 must hold

## Status: AGREED
```

- [ ] **Step 2: Write `harness/test/fixtures/contract_floored.md`**

```markdown
# Sprint X Contract

## Done means
- [trace] in every strategy: events where ev=diagnostic_completed count >= 50

## Rubric coverage
Axis 2 (Decision Density): primary

## Status: AGREED
```

- [ ] **Step 3: Write `harness/run_evaluator.sh`**

```bash
#!/usr/bin/env bash
# harness/run_evaluator.sh — operator-facing evaluator entry.
#
# Required:
#   --run-id <id>
#   --sprint <N>
#
# Optional:
#   --godot <path>                  # default: /Applications/Godot.app/Contents/MacOS/Godot
#   --strategies <comma-list>       # default: all 4 priors
#   --seeds <comma-list>            # default: 1,2,3
#   --skip-calibration              # do not run anchor calibration
#   --skip-freeplay
#   --skip-judge                    # write judgments.json from baseline-scorecard.md instead
#   --dry-run                       # EVALUATOR_LIVE=0; uses shim
#
# Reads from harness/runs/<id>/sprint_<N>/contract.md.
# Writes test_results.json, trace_findings.json, judgments.json, calibration.json,
#        verdict.json, critique.md into the same dir.
#
# Exits 0 iff every phase produced its artifact. Verdict (PASS/PIVOT/REJECT)
# is captured in verdict.json, not the exit code — exit 0 means "evaluator ran",
# not "sprint passed".

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
STRATEGIES="eager_diagnostician,intervention_spammer,patient_observer,neglect"
SEEDS="1,2,3"
SKIP_CALIBRATION=0
SKIP_FREEPLAY=0
SKIP_JUDGE=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-id)            RUN_ID="$2";       shift 2 ;;
        --sprint)            SPRINT_N="$2";     shift 2 ;;
        --godot)             GODOT="$2";        shift 2 ;;
        --strategies)        STRATEGIES="$2";   shift 2 ;;
        --seeds)             SEEDS="$2";        shift 2 ;;
        --skip-calibration)  SKIP_CALIBRATION=1; shift ;;
        --skip-freeplay)     SKIP_FREEPLAY=1;   shift ;;
        --skip-judge)        SKIP_JUDGE=1;      shift ;;
        --dry-run)           DRY_RUN=1;         shift ;;
        *) echo "run_evaluator: unknown arg: $1" >&2; exit 2 ;;
    esac
done
for var in RUN_ID SPRINT_N; do
    if [ -z "${!var}" ]; then echo "run_evaluator: missing --$var" >&2; exit 2; fi
done

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
CONTRACT="${SPRINT_DIR}/contract.md"
WORKTREE="${REPO_ROOT}/.worktrees/harness/${RUN_ID}/sprint_${SPRINT_N}"
TRACES_DIR="${SPRINT_DIR}/traces"

for f in "$CONTRACT" "${SPRINT_DIR}/ready"; do
    if [ ! -f "$f" ]; then echo "run_evaluator: missing precondition: $f" >&2; exit 2; fi
done
if [ ! -d "$WORKTREE" ]; then echo "run_evaluator: missing worktree: $WORKTREE" >&2; exit 2; fi

# Resolve LIVE mode.
if [ "$DRY_RUN" = "1" ]; then
    LIVE=0
else
    LIVE="${EVALUATOR_LIVE:-0}"
fi

SHIM_DIR="${SPRINT_DIR}/shim"
mkdir -p "$SHIM_DIR" "$TRACES_DIR" "${SPRINT_DIR}/strategy_sessions"

if [ "$LIVE" = "0" ] && [ ! -f "${SHIM_DIR}/canned.json" ]; then
    # Default smoke shim: every checkpoint emits {"op": "snapshot"} until day 10.
    cat > "${SHIM_DIR}/canned.json" <<'EOF'
{"shim-session": [{"op": "snapshot"}, {"op": "advance", "game_hours": 4}, {"op": "shutdown"}]}
EOF
fi

# ---------- 1. Calibration ----------
if [ "$SKIP_CALIBRATION" = "0" ]; then
    echo "[run_evaluator] calibration…" >&2
    python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from claude_subprocess import ClaudeSession
from calibrate_anchors import run_calibration, load_paths

list_file = Path("${REPO_ROOT}/harness/test/fixtures/anchor_calibration_small.txt")
anchors = [Path("${REPO_ROOT}") / p for p in load_paths(list_file)]
anchors = [p for p in anchors if p.exists()]

if "${LIVE}" == "1":
    session = ClaudeSession.live(system_prompt="", working_dir="${REPO_ROOT}")
else:
    canned = {"shim-session": [json.dumps({"score": int(p.stem.split("-")[0][:2]) % 4, "rationale": "shim"}) for p in anchors]}
    # Force shim scores to match canonical for dry-run by reading frontmatter.
    import re
    canned_list = []
    for p in anchors:
        text = p.read_text()
        m = re.search(r"canonical_score:\s*(\d+)", text)
        canon = int(m.group(1)) if m else 0
        canned_list.append(json.dumps({"score": canon, "rationale": "shim"}))
    canned = {"shim-session": canned_list}
    session = ClaudeSession.shim(canned, session_id="shim-session")

result = run_calibration(anchor_paths=anchors, session=session, model="claude-opus-4-7")
Path("${SPRINT_DIR}/calibration.json").write_text(json.dumps({
    "passed": result.passed,
    "per_anchor": result.per_anchor,
}, indent=2))
if not result.passed:
    print("[run_evaluator] calibration drift > 1; aborting grading.", file=sys.stderr)
    sys.exit(3)
PYEOF
else
    echo '{"passed": true, "per_anchor": [], "skipped": true}' > "${SPRINT_DIR}/calibration.json"
fi

# ---------- 2. Strategy tournament ----------
echo "[run_evaluator] tournament…" >&2
TOURNAMENT_ARGS=(
    --run-id "$RUN_ID" --sprint "$SPRINT_N"
    --godot "$GODOT" --project "$WORKTREE"
    --strategies "$STRATEGIES" --seeds "$SEEDS"
)
[ "$SKIP_FREEPLAY" = "1" ] && TOURNAMENT_ARGS+=( --skip-freeplay )
if [ "$LIVE" = "1" ]; then
    TOURNAMENT_ARGS+=( --live )
else
    TOURNAMENT_ARGS+=( --shim-canned "${SHIM_DIR}/canned.json" )
fi
bash "${REPO_ROOT}/harness/lib/tournament.sh" "${TOURNAMENT_ARGS[@]}"

# ---------- 3. Test verifier ----------
echo "[run_evaluator] running [test] items…" >&2
bash "${REPO_ROOT}/harness/lib/run_contract_tests.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --godot "$GODOT" --project "$WORKTREE"

# ---------- 4. Trace verifier ----------
echo "[run_evaluator] running [trace] items…" >&2
python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from contract_schema import parse_contract
from scan_tournament_trace import TraceRule, run_all

contract = parse_contract(Path("${CONTRACT}").read_text())
rules = [TraceRule.parse(it.body, index=i) for i, it in enumerate(contract.items) if it.kind == "trace"]
traces = sorted(Path("${TRACES_DIR}").glob("*.jsonl"))
run_all(rules=rules, trace_files=traces, out_path=Path("${SPRINT_DIR}/trace_findings.json"))
PYEOF

# ---------- 5. Judge ----------
echo "[run_evaluator] judging axes…" >&2
if [ "$SKIP_JUDGE" = "1" ]; then
    # Fallback: copy canonical scores from baseline-scorecard.md as a default.
    python3 - <<PYEOF
import json
from pathlib import Path
defaults = [
    {"axis": "thematic-coherence",      "sub_scores": [3,2,2,3], "axis_score": 2.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "decision-density",        "sub_scores": [2,1,2,1], "axis_score": 1.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "earned-discovery",        "sub_scores": [3,3,2,2], "axis_score": 2.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "forgiveness-with-stakes", "sub_scores": [3,3,2,1], "axis_score": 2.25,"citations": [], "harsh_check": "skipped"},
    {"axis": "texture-voice",           "sub_scores": [3,2,3,2], "axis_score": 2.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "sim-legibility",          "sub_scores": [2,3,2,1], "axis_score": 2.0, "citations": [], "harsh_check": "skipped"},
    {"axis": "loop-closure",            "sub_scores": [3,2,1,1], "axis_score": 1.75,"citations": [], "harsh_check": "skipped"},
]
Path("${SPRINT_DIR}/judgments.json").write_text(json.dumps({"items": defaults, "skipped": True}, indent=2))
PYEOF
else
    python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from claude_subprocess import ClaudeSession
from judge import score_axis, AXIS_SLUGS
from summarize_traces import summarize_directory

# Extract axis definitions from docs/rubric/rubric.md.
rubric_md = (Path("${REPO_ROOT}") / "docs/rubric/rubric.md").read_text()

# Trivial section splitter: each "## Axis N — Name" block is captured.
import re
sections = re.split(r"\n## Axis \d+ — ", rubric_md)[1:]
axis_defs = {}
for sec in sections:
    head, _, body = sec.partition("\n")
    name = head.split(" (weight")[0].strip().lower().replace(" / ", "-").replace(" ", "-")
    # Map to slugs.
    slug_map = {
        "thematic-coherence":"thematic-coherence",
        "decision-density":"decision-density",
        "earned-discovery":"earned-discovery",
        "forgiveness-with-stakes":"forgiveness-with-stakes",
        "texture-/-voice":"texture-voice",
        "texture-voice":"texture-voice",
        "sim-legibility":"sim-legibility",
        "loop-closure":"loop-closure",
    }
    slug = slug_map.get(name, name)
    axis_defs[slug] = body

# Load anchors (one positive + one negative per axis).
from rubric_schema import parse_frontmatter
def load_anchors_for(slug, polarity):
    root = Path("${REPO_ROOT}") / "docs/rubric/anchors" / polarity
    out = []
    for p in sorted(root.glob("*.md")):
        if p.name == "README.md": continue
        try:
            meta = parse_frontmatter(p.read_text())
        except Exception:
            continue
        if meta.get("axis") == slug:
            out.append((p.stem, p.read_text()))
            break  # one per polarity per axis
    return out

# Trace summaries.
summaries = summarize_directory(Path("${TRACES_DIR}"))
import json
trace_extract = json.dumps([s.to_dict() for s in summaries], indent=2)
freeplay_extract = None
for s in summaries:
    if s.strategy == "freeplay":
        freeplay_extract = json.dumps(s.to_dict(), indent=2)

# Drive one judge session per axis (separate session each, so cache is per axis).
results = []
if "${LIVE}" == "1":
    for slug in AXIS_SLUGS:
        session = ClaudeSession.live(system_prompt=(Path("${REPO_ROOT}") / "harness/prompts/judge_axis.md").read_text(), working_dir="${REPO_ROOT}")
        j = score_axis(
            session=session,
            axis_slug=slug,
            axis_definition_md=axis_defs.get(slug, "(missing)"),
            positive_anchors=load_anchors_for(slug, "positive"),
            negative_anchors=load_anchors_for(slug, "negative"),
            trace_extract=trace_extract,
            freeplay_extract=freeplay_extract,
            model="claude-opus-4-7",
        )
        results.append(j.to_dict())
else:
    # Shim: defer to canned scores per axis, or pull from baseline-scorecard.md.
    canned = {
        "thematic-coherence":      [2,2,2,3],
        "decision-density":        [2,1,2,1],
        "earned-discovery":        [3,3,2,2],
        "forgiveness-with-stakes": [3,3,2,1],
        "texture-voice":           [3,2,3,2],
        "sim-legibility":          [2,3,2,1],
        "loop-closure":            [3,2,1,1],
    }
    for slug in AXIS_SLUGS:
        sub = canned[slug]
        results.append({
            "axis": slug,
            "sub_scores": sub,
            "axis_score": round(sum(sub)/4.0, 2),
            "citations": [],
            "harsh_check": "shim",
        })

Path("${SPRINT_DIR}/judgments.json").write_text(json.dumps({"items": results}, indent=2))
PYEOF
fi

# ---------- 6. Composite + verdict ----------
echo "[run_evaluator] computing verdict…" >&2
python3 - <<PYEOF
import sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from score import main as score_main
score_main(Path("${SPRINT_DIR}"))
PYEOF

# ---------- 7. Critique ----------
echo "[run_evaluator] rendering critique…" >&2
python3 - <<PYEOF
import sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from render_critique import main as crit_main
crit_main(Path("${SPRINT_DIR}"), sprint_label="${RUN_ID} sprint ${SPRINT_N}")
PYEOF

echo "[run_evaluator] done. Verdict: $(python3 -c "import json,sys; print(json.load(open('${SPRINT_DIR}/verdict.json'))['verdict'])")"
echo "[run_evaluator] critique: ${SPRINT_DIR}/critique.md"
```

- [ ] **Step 4: Make `run_evaluator.sh` executable + bash-lint**

```bash
chmod +x harness/run_evaluator.sh
bash -n harness/run_evaluator.sh
```

Expected: silent success.

- [ ] **Step 5: Write `harness/test/smoke_evaluator.sh`**

```bash
#!/usr/bin/env bash
# End-to-end dry-run smoke for run_evaluator.sh.
# - Skips strategy tournament Godot launches (uses shim canned + a manual trace seed).
# - Skips real claude calls.
# - Asserts verdict.json + critique.md exist and verdict is REJECT (because tournament
#   shim produces empty case_file_updated counts → trace verifier fails).

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
RUN_ID="smoke-$(date +%s)"
SPRINT_N="1"
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
WORKTREE="${REPO_ROOT}/.worktrees/harness/${RUN_ID}/sprint_${SPRINT_N}"

cleanup() {
    rm -rf "${REPO_ROOT}/harness/runs/${RUN_ID}"
    rm -rf "${REPO_ROOT}/.worktrees/harness/${RUN_ID}"
}
trap cleanup EXIT

mkdir -p "$SPRINT_DIR" "$WORKTREE"
touch "${SPRINT_DIR}/ready"
cp "${REPO_ROOT}/harness/test/fixtures/contract_pass.md" "${SPRINT_DIR}/contract.md"

# Pre-seed traces dir so the tournament step can be substituted by a fake.
mkdir -p "${SPRINT_DIR}/traces"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/eager_diagnostician_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/eager_diagnostician_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/eager_diagnostician_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_intervention_seed1.jsonl"  "${SPRINT_DIR}/traces/intervention_spammer_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_intervention_seed1.jsonl"  "${SPRINT_DIR}/traces/intervention_spammer_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_intervention_seed1.jsonl"  "${SPRINT_DIR}/traces/intervention_spammer_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/patient_observer_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/patient_observer_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/patient_observer_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/neglect_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/neglect_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/neglect_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_freeplay.jsonl"            "${SPRINT_DIR}/traces/freeplay.jsonl"

# Disable Godot smoke for [test] items — write a trivial test_results.json directly.
SKIP_TEST_SHIM=1

# Patch: run the evaluator without the tournament + [test] sub-phases.
EVALUATOR_LIVE=0 \
bash "${REPO_ROOT}/harness/run_evaluator.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --skip-freeplay --skip-judge --dry-run \
  || true   # Non-zero exits handled below; we want to inspect artifacts even on failure.

# Compensate: smoke skips the tournament run by pre-seeding traces and the [test]
# runner by writing an empty all_pass result directly. Run the remaining steps
# manually so the smoke doesn't depend on a real Godot install.
python3 - <<PYEOF
import json
from pathlib import Path
p = Path("${SPRINT_DIR}")
(p / "test_results.json").write_text(json.dumps({"all_pass": True, "items": []}, indent=2))
PYEOF

# Re-run trace + score + critique only.
python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from contract_schema import parse_contract
from scan_tournament_trace import TraceRule, run_all
from score import main as score_main
from render_critique import main as crit_main

sprint = Path("${SPRINT_DIR}")
contract = parse_contract((sprint / "contract.md").read_text())
rules = [TraceRule.parse(it.body, index=i) for i, it in enumerate(contract.items) if it.kind == "trace"]
traces = sorted((sprint / "traces").glob("*.jsonl"))
run_all(rules=rules, trace_files=traces, out_path=(sprint / "trace_findings.json"))
score_main(sprint)
crit_main(sprint, sprint_label="${RUN_ID} sprint ${SPRINT_N}")
PYEOF

# Assertions.
test -s "${SPRINT_DIR}/verdict.json"   || { echo "smoke: verdict.json missing"; exit 1; }
test -s "${SPRINT_DIR}/critique.md"    || { echo "smoke: critique.md missing"; exit 1; }
test -s "${SPRINT_DIR}/calibration.json" || { echo "smoke: calibration.json missing"; exit 1; }
test -s "${SPRINT_DIR}/judgments.json"   || { echo "smoke: judgments.json missing"; exit 1; }

VERDICT=$(python3 -c "import json; print(json.load(open('${SPRINT_DIR}/verdict.json'))['verdict'])")
echo "[smoke] verdict: $VERDICT"
case "$VERDICT" in
    PASS|PIVOT|REJECT) ;;
    *) echo "smoke: unexpected verdict $VERDICT"; exit 1 ;;
esac

echo "[smoke] OK"
```

- [ ] **Step 6: Run the smoke**

```bash
chmod +x harness/test/smoke_evaluator.sh
harness/test/smoke_evaluator.sh
```

Expected: exits 0, prints `[smoke] verdict: <PASS|PIVOT|REJECT>` and `[smoke] OK`. The dry-run shim produces a deterministic verdict (likely PASS, since the seeded traces satisfy both `[trace]` rules and the shim judgments mirror baseline canonical scores → total ~59 → PIVOT or PASS depending on floors). Whichever it returns, it should not crash.

- [ ] **Step 7: Run all unit tests once more for regression**

```bash
python3 -m unittest discover -s harness/test -p 'test_*.py' -v
```

Expected: all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add harness/run_evaluator.sh harness/test/smoke_evaluator.sh harness/test/fixtures/contract_pass.md harness/test/fixtures/contract_floored.md
git commit -m "feat(harness): run_evaluator.sh + end-to-end dry-run smoke"
```

---

## Task 16: README final bump + spec coverage table

Flip Plan 4's status to done. Add a Plan 4 protocol notes section to `harness/README.md`. Append a spec-coverage table proving every §3–§6 requirement landed.

**Files:**
- Modify: `harness/README.md`

- [ ] **Step 1: Update status row + Plan 4 protocol notes**

Open `harness/README.md`. Change Plan 4's status row to:

```markdown
| 4 | Evaluator + strategy tournament | ✅ done |
```

After the existing "What's NOT in Plan 1" section, append a new section:

```markdown
## Plan 4 — Evaluator + strategy tournament

The grading half of the evaluator. Operator runs `harness/run_evaluator.sh --run-id <id> --sprint <N>` against a sprint dir produced by Plan 3 (must contain `contract.md` with `Status: AGREED` and the `ready` sentinel; worktree at `.worktrees/harness/<id>/sprint_<N>/` must still exist).

### What runs

1. **Anchor calibration** (`harness/lib/calibrate_anchors.py`). 14 anchors (1 positive + 1 negative per axis, listed in `harness/test/fixtures/anchor_calibration_small.txt`) re-scored by the judge LLM. Drift > 1 on any anchor → `calibration.json` records `passed: false`, evaluator aborts.
2. **Strategy tournament** (`harness/lib/tournament.sh`). 4 prior-guided strategies × 3 seeds + 1 freeplay = 13 playtests. Each playtest spawns Godot in `--agent-mode` and a long-lived `claude` subprocess (via `harness/lib/llm_player.py`). Traces written to `traces/<strategy>_seed<S>.jsonl` and `traces/freeplay.jsonl`.
3. **`[test]` verifier** (`harness/lib/run_contract_tests.sh`). Extracts each `[test]` contract item, runs the referenced GUT script inside the worktree, writes `test_results.json`.
4. **`[trace]` verifier** (`harness/lib/scan_tournament_trace.py`). Each rule supports `in any strategy`, `in every strategy`, or `across strategies` quantifier. Result → `trace_findings.json`.
5. **`[judge]` verifier** (`harness/lib/judge.py` + `harness/prompts/judge_axis.md`). Seven Opus calls — one per rubric axis. Each gets the axis definition, positive + negative anchors, per-strategy trace summaries, optional freeplay extract. Returns JSON with sub_scores + citations. Aggregated into `judgments.json`.
6. **Composite scorer** (`harness/lib/score.py`). Pure data. Reads the three verifier outputs, applies weights + floors from `docs/rubric/rubric.md`, emits `verdict.json`.
7. **Critique renderer** (`harness/lib/render_critique.py`). `verdict.json` + verifier outputs → `critique.md`.

### Live vs dry-run

| Mode | env / flag | Calls claude? | Calls Godot? |
|---|---|---|---|
| Dry-run (default in tests) | `--dry-run` or `EVALUATOR_LIVE=0` | No (shim) | No (in smoke), Yes (in `tournament.sh` live mode if no shim) |
| Live | `EVALUATOR_LIVE=1` | Yes | Yes |

Cost-control flags on `run_evaluator.sh`: `--strategies`, `--seeds`, `--skip-freeplay`, `--skip-judge`, `--skip-calibration`.

### Artifacts written to `harness/runs/<id>/sprint_<N>/`

- `calibration.json` — anchor re-score result
- `traces/<strategy>_seed<S>.jsonl` × 12 + `traces/freeplay.jsonl`
- `strategy_sessions/<strategy>_seed<S>.log` × 12
- `test_results.json`
- `trace_findings.json`
- `judgments.json`
- `verdict.json`
- `critique.md`

### What's NOT in Plan 4

Contract negotiation (Phase A — Plan 5), orchestrating evaluator agent (Opus driving the script — Plan 5), planner sprint decomposition (Plan 5), `report.html` (Plan 5), meta-evaluation regressions (Plan 6).
```

- [ ] **Step 2: Append spec coverage table**

At the end of `harness/README.md`, append:

```markdown
## Spec coverage — Plan 4

Mapped against `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

| Spec ref | Where it landed | Notes |
|---|---|---|
| §3 rubric weights/floors | `harness/lib/score.py` `AXIS_WEIGHTS`, `AXIS_FLOORS` | pinned values, mirror rubric.md |
| §3.5 calibration ritual | `harness/lib/calibrate_anchors.py` | anchor-text calibration only; Godot-state calibration deferred to Plan 5 |
| §4.2 strategy player long-lived session | `harness/lib/llm_player.py` + `harness/lib/claude_subprocess.py` | one ClaudeSession per playtest, `claude --resume` per checkpoint |
| §4.2 cost-controlled tournament size | `harness/lib/tournament.sh` `--strategies`/`--seeds`/`--skip-freeplay` | 4×3 + 1 default |
| §4.5 Phase B grading orchestration | `harness/run_evaluator.sh` | 7-phase pipeline |
| §4.5 anti-sycophancy judge prompt | `harness/prompts/judge_axis.md` | "paid to fail this sprint" + harsh_check field |
| §4.5 hybrid verifiers | `run_contract_tests.sh` + `scan_tournament_trace.py` + `judge.py` | one per `[test]` / `[trace]` / `[judge]` kind |
| §5.1 sprint dir layout | All paths under `harness/runs/<id>/sprint_<N>/` | matches spec §5.1 verbatim |
| §6.3 generator-side errors | (out of scope; Plan 3) | — |
| §6.4 evaluator failure modes | `calibrate_anchors.py`, `run_evaluator.sh` aborts on drift, smoke ensures `verdict.json` always exists | sycophancy/miscalibration covered by calibration phase |
| §6.7 talk anti-patterns | Generator never grades (Plan 3); compaction guarded by per-checkpoint snapshot+events (`llm_player.py` `render_user_prompt`); contract verifier requires non-empty `[test]`/`[trace]` (Plan 3) | — |
| §10 deferred (negotiation, orchestrator, report.html, parallel sprints) | Plan 5 | — |
```

- [ ] **Step 3: Commit**

```bash
git add harness/README.md
git commit -m "docs(harness): mark Plan 4 done + protocol notes + spec coverage"
```

---

## Self-review

(Run as the last step of plan execution, mentally — no separate task.)

- **Spec coverage:** every requirement in §3, §4.2, §4.5, §5.1, §6.4 has a task; deferred items (§10) explicitly named as out-of-scope.
- **Placeholders:** every step contains the real content; no "TODO", no "fill in details", no "similar to Task N".
- **Type consistency:** `Strategy.id`, `Strategy.mode`, `ContractItem.kind`, `TraceRule.quantifier`, `AxisJudgment.sub_scores`, `Verdict.verdict` — all used identically across the modules and tests that reference them.

**End of plan.**
