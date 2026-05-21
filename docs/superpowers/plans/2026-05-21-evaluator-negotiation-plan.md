# Evaluator Agent + Phase A Negotiation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Opus-driven evaluator agent and the contract-negotiation loop that wraps it. An operator runs `harness/run_sprint.sh` with a sprint goal + touch-surface allowlist. The script (1) creates the worktree + sprint dir, (2) seeds a `contract.md` skeleton, (3) spawns the Plan 3 generator as a long-lived `claude -p` subprocess to draft a contract, (4) spawns the Plan 5 evaluator as a long-lived `claude -p --resume` Opus subprocess to critique and edit the contract, (5) ping-pongs the two agents under a `flock`-guarded mutex on `contract.md` until both write `## Status: AGREED` consecutively or the round counter hits 5 (force-pivot), (6) on agreed, runs the Plan 4 calibration → tournament → verdict pipeline via `run_evaluator.sh`, (7) writes `verdict.json` + `critique.md` + a final `agreement.json` audit log. The planner, multi-sprint orchestration, and `report.html` remain out of scope (Plan 6 / Plan 7).

**Architecture:** Three layers, mirroring Plans 3 + 4. (1) Bash entrypoints (`run_sprint.sh`, `run_evaluator_agent.sh`) own process lifecycle: spawn, resume, kill, exit-code propagation. (2) Python `harness/lib/` modules own the negotiation state machine: per-turn polling, file-hash + status detection, round counting, mutex acquisition, contradiction detection, and seeding the initial contract from the sprint goal. (3) The two LLM agents (generator from Plan 3, evaluator new here) interact exclusively via the shared `contract.md` file under a single-writer-at-a-time discipline enforced by `flock`. There is no in-process coordination — every interaction goes through the file system, exactly as spec §5.2 + §6.2 require. The negotiation loop is a pure Python state machine driven by file events; the agents see only their turn and their working copy of the contract.

**Tech Stack:** Bash 3+ (orchestrator + agent spawn), Python 3.11+ stdlib (`unittest`, `subprocess`, `hashlib`, `fcntl`, `argparse`, `json`, `dataclasses`), Plan 3's `contract_schema.py` (parser + ≥50% test/trace validator) re-used unchanged, Plan 4's `claude_subprocess.py` (`--resume` wrapper, shim mode), Plan 4's `run_evaluator.sh` (called as a subprocess on AGREED), Plan 4's `prompts/judge_axis.md` + anchor scorecards (calibration data path), `claude` CLI (`claude -p --resume`, Opus 4.7 for evaluator, Sonnet 4.6 for generator). No third-party Python deps.

**Plan position:** Plan 5 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11 (the spec lists 9 phases; this project's plan-numbering compresses phases 4 + 5 into Plan 4 for grading and Plan 5 for the negotiating-agent wrapper around it — see Plan 4's goal text: "Contract negotiation (Phase A) ... out of scope (Plan 5)"). Depends on Plan 1 (AgentBridge), Plan 2 (rubric + anchors), Plan 3 (generator agent + worktree + `contract_schema.py`), Plan 4 (grading pipeline + claude wrapper + judge prompt). Required input for Plan 6 (planner sprint decomposition wraps `run_sprint.sh` in a multi-sprint loop with PIVOT/REJECT handling).

---

## File Structure

**Files created:**

```
harness/
├── run_sprint.sh                                  # NEW — top-level Phase A + Phase B orchestrator
├── run_evaluator_agent.sh                         # NEW — long-lived Opus evaluator subprocess wrapper
├── prompts/
│   └── evaluator.md                               # NEW — Opus harshness-tuned system prompt
├── lib/
│   ├── negotiation_state.py                       # NEW — round counter + turn marker JSON model
│   ├── contract_lock.py                           # NEW — flock-based mutex on contract.md
│   ├── contract_hash.py                           # NEW — stable hash of (items, status) for change detection
│   ├── contract_template.py                       # NEW — seed contract.md from sprint goal
│   ├── pre_grade_calibration.py                   # NEW — re-score baseline anchors before tournament
│   ├── negotiation_loop.py                        # NEW — driver: spawn/resume agents, poll, count rounds
│   ├── init_negotiation.sh                        # NEW — bootstrap sprint dir + contract skeleton + state
│   └── run_evaluator_phase_b.sh                   # NEW — thin wrapper that invokes Plan 4's run_evaluator.sh
└── test/
    ├── fixtures/
    │   ├── sprint_goal_simple.md                  # NEW — minimal sprint goal for negotiation tests
    │   ├── sprint_goal_overscoped.md              # NEW — deliberately too-wide goal (evaluator should narrow)
    │   ├── contract_draft_v1_negotiating.md       # NEW — generator's first draft
    │   ├── contract_draft_v2_eval_revised.md      # NEW — evaluator's response
    │   ├── contract_draft_v3_gen_agreed.md        # NEW — generator agrees
    │   ├── contract_draft_v4_eval_agreed.md       # NEW — evaluator agrees (terminal)
    │   ├── contract_force_pivot.md                # NEW — contract after 5 unresolved rounds
    │   └── baseline_scorecard_drifted.json        # NEW — synthetic drifted calibration result
    ├── test_negotiation_state.py                  # NEW — unittest
    ├── test_contract_lock.py                      # NEW — unittest
    ├── test_contract_hash.py                      # NEW — unittest
    ├── test_contract_template.py                  # NEW — unittest
    ├── test_pre_grade_calibration.py              # NEW — unittest (shimmed claude)
    ├── test_negotiation_loop.py                   # NEW — unittest (shimmed claude + shimmed flock)
    ├── test_init_negotiation.py                   # NEW — unittest driving the bash helper
    └── smoke_negotiation.sh                       # NEW — end-to-end dry-run integration
```

**Files modified:**

```
harness/prompts/generator.md                       # add Phase A "round-aware draft" directives
harness/README.md                                  # status table: Plan 5 done; protocol notes
.gitignore                                         # ignore harness/.locks/ (per-sprint mutex files)
```

**Files deleted:** none. No game-code, autoload, rubric, or Plan 4 changes — Plan 5 is pure negotiation glue.

---

## Conventions used by this plan

- **Run id + sprint dir:** identical to Plans 3 + 4. `harness/runs/<run-id>/sprint_<N>/` is the single shared workspace.
- **Sprint precondition (Plan 5 entry):** `harness/runs/<run-id>/sprint_<N>/goal.md` and `.../touch_surface.allow` exist (operator-authored). Nothing else need exist; Task 9's `init_negotiation.sh` creates the contract + state.
- **Sprint postcondition (Plan 5 exit):** `contract.md` has `## Status: AGREED`, `agreement.json` records the full negotiation history, `verdict.json` + `critique.md` exist (produced by Plan 4 invoked at end of run), OR `force_pivot.json` exists explaining why negotiation failed.
- **Mutex path:** `harness/.locks/contract_<run-id>_<N>.lock` — `flock(2)` advisory, single file per sprint, never shared across sprints.
- **Negotiation state path:** `harness/runs/<run-id>/sprint_<N>/negotiation_state.json` — orchestrator-owned; agents never edit it.
- **Audit log path:** `harness/runs/<run-id>/sprint_<N>/agreement.json` — written once on terminal AGREED, contains the full round-by-round contract hash + author trace.
- **Turn semantics:** `generator` always has the first turn (drafts initial contract). `evaluator` is second. They alternate until either both write AGREED consecutively (terminal) or round counter exceeds 5 (force-pivot).
- **Status transitions written by agents:**
  - Generator writes `## Status: NEGOTIATING` when proposing edits, `## Status: AGREED` when satisfied with current contract.
  - Evaluator writes `## Status: NEGOTIATING` when pushing back, `## Status: AGREED` when satisfied.
  - Orchestrator detects terminal AGREED by: (status == AGREED at end of evaluator turn) AND (status == AGREED at end of next generator turn) AND (contract hash unchanged across that generator turn).
- **Round counter:** increments after each agent's turn. Initial draft (generator turn 1) is round 1. Evaluator's first response is round 2. Cap = 5 (a generator-then-evaluator pair counts as 2 rounds; force-pivot triggers at round 6).
- **Force-pivot:** if round > 5 without terminal AGREED, orchestrator writes `force_pivot.json` summarizing both sides' final positions and exits 2. No Phase B grading runs. Plan 6 (planner) will consume this to re-plan the sprint.
- **Live vs shimmed:** every external-process call respects `EVALUATOR_LIVE` (Plan 4 convention). `EVALUATOR_LIVE=0` (default) = shims, used by `smoke_negotiation.sh` and unit tests. `EVALUATOR_LIVE=1` = real `claude`. New env var `NEGOTIATION_LIVE` is an alias of `EVALUATOR_LIVE` for callsite clarity inside Plan 5; both must agree or `run_sprint.sh` errors.
- **Cost-control flags** (operator-facing on `run_sprint.sh`):
  - `--max-rounds N` (default: 5; spec §4.5 hard cap)
  - `--skip-eval-phase-b` (debug only — stop after AGREED; do not call `run_evaluator.sh`)
  - `--dry-run` (== `EVALUATOR_LIVE=0`)
- **Bash style:** `set -euo pipefail` at the top of every script.
- **Python style:** stdlib only. Every new module has a unittest suite under `harness/test/`.
- **Commit style:** Conventional Commits, matches Plans 1–4: `feat(harness):`, `feat(lib):`, `test(harness):`, etc.

---

## Task 1: Repo scaffolding + .gitignore + README in-progress marker

**Files:**
- Create: `harness/.locks/.gitkeep`
- Create: `harness/test/fixtures/.gitkeep` (no-op if exists from Plan 4)
- Modify: `.gitignore`
- Modify: `harness/README.md`

- [ ] **Step 1: Verify Plan 3 + Plan 4 prerequisites exist**

```bash
test -f harness/run_generator.sh                  || { echo "missing Plan 3 run_generator.sh"; exit 1; }
test -f harness/run_evaluator.sh                  || { echo "missing Plan 4 run_evaluator.sh"; exit 1; }
test -f harness/lib/contract_schema.py            || { echo "missing Plan 3 contract_schema.py"; exit 1; }
test -f harness/lib/claude_subprocess.py          || { echo "missing Plan 4 claude_subprocess.py"; exit 1; }
test -f harness/prompts/generator.md              || { echo "missing Plan 3 generator.md"; exit 1; }
test -f docs/rubric/rubric.md                     || { echo "missing Plan 2 rubric.md"; exit 1; }
test -f docs/rubric/baseline-scorecard.md         || { echo "missing Plan 2 baseline-scorecard.md"; exit 1; }
mkdir -p harness/.locks harness/test/fixtures
touch harness/.locks/.gitkeep harness/test/fixtures/.gitkeep
```

Expected: every check passes silently.

- [ ] **Step 2: Update `.gitignore` (idempotent)**

Append at end:

```
# Harness Plan 5 runtime — per-sprint flock files
harness/.locks/*.lock
!harness/.locks/.gitkeep
```

Verify:

```bash
grep -q '^harness/.locks/\*.lock$' .gitignore || { echo "missing lock ignore"; exit 1; }
grep -q '^!harness/.locks/.gitkeep$' .gitignore || { echo "missing keep marker"; exit 1; }
```

- [ ] **Step 3: Update `harness/README.md` status table**

Change Plan 5's row from:

```markdown
| 5 | Planner + orchestrator + report.html | pending |
```

to:

```markdown
| 5 | Evaluator agent + Phase A negotiation | 🚧 in progress |
| 6 | Planner + orchestrator + report.html | pending |
| 7 | Meta-evaluation | pending |
```

(The README's old row labelled 5 was a stale earlier breakdown. Plan 6 takes the orchestrator role; meta-eval moves to row 7. Final flip of Plan 5 to `✅ done` happens in Task 14.)

- [ ] **Step 4: Commit**

```bash
git add harness/.locks/.gitkeep harness/test/fixtures/.gitkeep .gitignore harness/README.md
git commit -m "feat(harness): scaffold Plan 5 dirs + gitignore + README status"
```

---

## Task 2: Negotiation state model

The state file is the orchestrator's source of truth. Agents never read or write it; they only see `contract.md`. The orchestrator updates state after every turn and uses it to decide whose turn is next, whether to force-pivot, and what to write into the final `agreement.json`.

**Files:**
- Create: `harness/lib/negotiation_state.py`
- Create: `harness/test/test_negotiation_state.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_negotiation_state.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/negotiation_state.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from negotiation_state import (  # noqa: E402
    NegotiationState,
    TurnRecord,
    NegotiationStateError,
    Turn,
)


class TestInit(unittest.TestCase):
    def test_initial_state_has_no_turns(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1, max_rounds=5)
        self.assertEqual(s.run_id, "r1")
        self.assertEqual(s.sprint, 1)
        self.assertEqual(s.max_rounds, 5)
        self.assertEqual(s.turns, ())
        self.assertEqual(s.current_round(), 0)
        self.assertEqual(s.next_actor(), Turn.GENERATOR)

    def test_first_turn_must_be_generator(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        with self.assertRaises(NegotiationStateError):
            s.record_turn(actor=Turn.EVALUATOR, status="NEGOTIATING", contract_hash="x")


class TestRecordTurn(unittest.TestCase):
    def _seed_generator_draft(self) -> NegotiationState:
        s = NegotiationState.new(run_id="r1", sprint=1)
        return s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")

    def test_round_increments(self) -> None:
        s = self._seed_generator_draft()
        self.assertEqual(s.current_round(), 1)
        self.assertEqual(s.next_actor(), Turn.EVALUATOR)
        s2 = s.record_turn(actor=Turn.EVALUATOR, status="NEGOTIATING", contract_hash="h2")
        self.assertEqual(s2.current_round(), 2)
        self.assertEqual(s2.next_actor(), Turn.GENERATOR)

    def test_actor_must_alternate(self) -> None:
        s = self._seed_generator_draft()
        with self.assertRaises(NegotiationStateError):
            s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h2")


class TestTerminalAgreed(unittest.TestCase):
    def test_terminal_requires_two_consecutive_agreed_distinct_actors(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        # Not terminal yet — generator hasn't confirmed.
        self.assertFalse(s.is_terminal_agreed())
        # Generator confirms by leaving the contract alone and writing AGREED.
        s = s.record_turn(actor=Turn.GENERATOR, status="AGREED", contract_hash="h2")
        self.assertTrue(s.is_terminal_agreed())

    def test_agreed_after_edit_is_not_terminal(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        # Generator wrote AGREED but ALSO edited the contract (hash changed)
        # → evaluator must see and confirm before terminal.
        s = s.record_turn(actor=Turn.GENERATOR, status="AGREED", contract_hash="h3")
        self.assertFalse(s.is_terminal_agreed())


class TestForcePivot(unittest.TestCase):
    def test_pivot_at_max_rounds(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1, max_rounds=4)
        for _ in range(4):
            actor = s.next_actor()
            s = s.record_turn(actor=actor, status="NEGOTIATING", contract_hash="h")
        # Round 4 done. Recording a 5th turn must raise force_pivot.
        self.assertTrue(s.should_force_pivot())

    def test_pivot_blocks_further_turns(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1, max_rounds=2)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="NEGOTIATING", contract_hash="h2")
        self.assertTrue(s.should_force_pivot())
        with self.assertRaises(NegotiationStateError):
            s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h3")


class TestPersistence(unittest.TestCase):
    def test_round_trip_disk(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as fh:
            path = fh.name
        s.to_file(path)
        s2 = NegotiationState.from_file(path)
        self.assertEqual(s.run_id, s2.run_id)
        self.assertEqual(s.sprint, s2.sprint)
        self.assertEqual(s.current_round(), s2.current_round())
        self.assertEqual(len(s.turns), len(s2.turns))
        self.assertEqual(s.turns[-1].contract_hash, s2.turns[-1].contract_hash)


class TestAgreementAuditLog(unittest.TestCase):
    def test_audit_log_emits_each_turn(self) -> None:
        s = NegotiationState.new(run_id="r1", sprint=1)
        s = s.record_turn(actor=Turn.GENERATOR, status="NEGOTIATING", contract_hash="h1")
        s = s.record_turn(actor=Turn.EVALUATOR, status="AGREED", contract_hash="h2")
        s = s.record_turn(actor=Turn.GENERATOR, status="AGREED", contract_hash="h2")
        audit = s.audit_log()
        self.assertEqual(audit["run_id"], "r1")
        self.assertEqual(audit["sprint"], 1)
        self.assertEqual(audit["terminal_status"], "AGREED")
        self.assertEqual(len(audit["turns"]), 3)
        self.assertEqual(audit["turns"][0]["actor"], "generator")
        self.assertEqual(audit["turns"][-1]["actor"], "generator")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_negotiation_state.py
```

Expected: ImportError on `negotiation_state`.

- [ ] **Step 3: Implement `harness/lib/negotiation_state.py`**

```python
"""Negotiation state model — turn alternation, round counting, terminal AGREED detection.

The state object is immutable; every transition returns a new state. The orchestrator
serializes the state to JSON after every turn so it can be inspected or resumed.

Terminal AGREED rule (spec §4.5 step 5): both sides must write '## Status: AGREED'
consecutively, AND the contract hash must be unchanged across the final confirming
turn (the confirming actor MUST NOT edit the contract; if they edit, it counts as a
new draft and the other side must see + confirm again).
"""
from __future__ import annotations
import json
from dataclasses import dataclass, asdict, replace
from enum import Enum
from pathlib import Path


class Turn(str, Enum):
    GENERATOR = "generator"
    EVALUATOR = "evaluator"


class NegotiationStateError(RuntimeError):
    """Raised on illegal turn transitions."""


@dataclass(frozen=True)
class TurnRecord:
    actor: Turn
    status: str          # "NEGOTIATING" | "AGREED"
    contract_hash: str   # opaque hash; see contract_hash.py


@dataclass(frozen=True)
class NegotiationState:
    run_id: str
    sprint: int
    max_rounds: int
    turns: tuple[TurnRecord, ...]

    @classmethod
    def new(cls, *, run_id: str, sprint: int, max_rounds: int = 5) -> "NegotiationState":
        if max_rounds < 2:
            raise NegotiationStateError("max_rounds must be ≥ 2 (at least one G+E pair)")
        return cls(run_id=run_id, sprint=sprint, max_rounds=max_rounds, turns=())

    def current_round(self) -> int:
        return len(self.turns)

    def next_actor(self) -> Turn:
        if not self.turns:
            return Turn.GENERATOR
        last = self.turns[-1].actor
        return Turn.EVALUATOR if last == Turn.GENERATOR else Turn.GENERATOR

    def should_force_pivot(self) -> bool:
        return self.current_round() >= self.max_rounds and not self.is_terminal_agreed()

    def is_terminal_agreed(self) -> bool:
        # Need at least two turns, both with status=AGREED, distinct actors,
        # AND the confirming (last) turn must NOT have changed the hash.
        if len(self.turns) < 2:
            return False
        a, b = self.turns[-2], self.turns[-1]
        return (
            a.status == "AGREED"
            and b.status == "AGREED"
            and a.actor != b.actor
            and a.contract_hash == b.contract_hash
        )

    def record_turn(self, *, actor: Turn, status: str, contract_hash: str) -> "NegotiationState":
        if status not in ("AGREED", "NEGOTIATING"):
            raise NegotiationStateError(f"status must be AGREED|NEGOTIATING, got {status!r}")
        if self.should_force_pivot():
            raise NegotiationStateError(
                f"force-pivot already triggered at round {self.current_round()}; refusing further turns"
            )
        expected = self.next_actor()
        if actor != expected:
            raise NegotiationStateError(
                f"out-of-turn write: expected {expected.value}, got {actor.value}"
            )
        record = TurnRecord(actor=actor, status=status, contract_hash=contract_hash)
        return replace(self, turns=self.turns + (record,))

    def audit_log(self) -> dict:
        terminal = "AGREED" if self.is_terminal_agreed() else (
            "FORCE_PIVOT" if self.should_force_pivot() else "IN_PROGRESS"
        )
        return {
            "run_id": self.run_id,
            "sprint": self.sprint,
            "max_rounds": self.max_rounds,
            "rounds_used": self.current_round(),
            "terminal_status": terminal,
            "turns": [
                {"round": i + 1, "actor": t.actor.value, "status": t.status, "contract_hash": t.contract_hash}
                for i, t in enumerate(self.turns)
            ],
        }

    def to_file(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.audit_log(), indent=2) + "\n")

    @classmethod
    def from_file(cls, path: str | Path) -> "NegotiationState":
        data = json.loads(Path(path).read_text())
        state = cls.new(run_id=data["run_id"], sprint=data["sprint"], max_rounds=data["max_rounds"])
        for t in data["turns"]:
            state = state.record_turn(
                actor=Turn(t["actor"]),
                status=t["status"],
                contract_hash=t["contract_hash"],
            )
        return state
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_negotiation_state.py
```

Expected: `OK` — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/negotiation_state.py harness/test/test_negotiation_state.py
git commit -m "feat(lib): negotiation state model with terminal AGREED + force-pivot detection"
```

---

## Task 3: Contract mutex (flock wrapper)

The contract file is the single shared object between generator and evaluator. Both run as separate `claude` subprocesses, both can be paused at any point, both might be killed and resumed. `flock(2)` is the simplest correct primitive: each agent's Bash wrapper acquires the lock before reading or writing the contract, releases it before yielding.

**Files:**
- Create: `harness/lib/contract_lock.py`
- Create: `harness/test/test_contract_lock.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_contract_lock.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/contract_lock.py."""
from __future__ import annotations
import os
import sys
import tempfile
import time
import unittest
from multiprocessing import Process, Queue
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_lock import (  # noqa: E402
    contract_lock,
    LockTimeoutError,
    LockPathError,
)


def _hold_lock(path: str, hold_seconds: float, q: Queue) -> None:
    try:
        with contract_lock(path, timeout=1.0):
            q.put("acquired")
            time.sleep(hold_seconds)
        q.put("released")
    except Exception as e:
        q.put(f"error:{type(e).__name__}")


class TestContractLock(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.lock_path = os.path.join(self.tmpdir, "x.lock")

    def test_acquires_and_releases(self) -> None:
        with contract_lock(self.lock_path, timeout=0.5):
            self.assertTrue(os.path.exists(self.lock_path))

    def test_creates_parent_dir_if_missing(self) -> None:
        deep = os.path.join(self.tmpdir, "a", "b", "c", "x.lock")
        with contract_lock(deep, timeout=0.5):
            self.assertTrue(os.path.exists(deep))

    def test_concurrent_acquire_blocks_then_succeeds(self) -> None:
        q: Queue = Queue()
        # Hold the lock briefly in a child process.
        p = Process(target=_hold_lock, args=(self.lock_path, 0.3, q))
        p.start()
        # Wait for child to acquire.
        self.assertEqual(q.get(timeout=2.0), "acquired")
        # Now try to acquire from the parent — should block until child releases.
        t0 = time.monotonic()
        with contract_lock(self.lock_path, timeout=2.0):
            dt = time.monotonic() - t0
        # Should have waited roughly hold_seconds.
        self.assertGreater(dt, 0.2)
        p.join()
        self.assertEqual(q.get(timeout=1.0), "released")

    def test_timeout_raises(self) -> None:
        q: Queue = Queue()
        p = Process(target=_hold_lock, args=(self.lock_path, 2.0, q))
        p.start()
        self.assertEqual(q.get(timeout=2.0), "acquired")
        try:
            with self.assertRaises(LockTimeoutError):
                with contract_lock(self.lock_path, timeout=0.2):
                    pass
        finally:
            p.join()

    def test_empty_path_rejected(self) -> None:
        with self.assertRaises(LockPathError):
            with contract_lock("", timeout=0.1):
                pass


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_contract_lock.py
```

Expected: ImportError on `contract_lock`.

- [ ] **Step 3: Implement `harness/lib/contract_lock.py`**

```python
"""flock-based advisory mutex around contract.md.

Use as a context manager:

    with contract_lock("/path/to/contract.lock", timeout=5.0):
        ... read/write contract.md ...

Releases automatically on exit (even on exception). Creates the lock file and any
missing parent directories. Subprocesses can share the same lock by opening the
same path under flock(LOCK_EX). The Bash side uses `flock` directly with -x -w N.
"""
from __future__ import annotations
import fcntl
import os
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


class LockTimeoutError(TimeoutError):
    """Raised if the lock could not be acquired within the timeout."""


class LockPathError(ValueError):
    """Raised if the lock path is empty or unusable."""


@contextmanager
def contract_lock(path: str, *, timeout: float = 5.0, poll_interval: float = 0.05) -> Iterator[int]:
    if not path:
        raise LockPathError("lock path must be non-empty")
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(p), os.O_CREAT | os.O_RDWR, 0o644)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LockTimeoutError(f"could not acquire lock at {p} within {timeout}s")
                time.sleep(poll_interval)
        try:
            yield fd
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
    finally:
        os.close(fd)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_contract_lock.py
```

Expected: `OK` — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/contract_lock.py harness/test/test_contract_lock.py
git commit -m "feat(lib): flock-based contract.md mutex"
```

---

## Task 4: Contract hash for change detection

The negotiation state needs to detect "did this turn actually change the contract, or is the agent confirming?" A whole-file md5 over `contract.md` is too brittle (whitespace edits would look like real changes). Hash only the structurally-significant bits: the parsed item list + the status. Re-uses `contract_schema.py` from Plan 3.

**Files:**
- Create: `harness/lib/contract_hash.py`
- Create: `harness/test/test_contract_hash.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_contract_hash.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/contract_hash.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_hash import hash_contract_text, hash_contract_file  # noqa: E402

BASE = """# Sprint 1 Contract

## Goal
move axis 2 (decision density).

## Done means
- [test] `test/harness/sprint_1_density.gd::test_two_strategies_diverge` passes
- [trace] events where ev=diagnostic_completed count >= 2

## Rubric coverage
Axis 2 (Decision Density): primary

## Status: NEGOTIATING
"""

BASE_AGREED = BASE.replace("## Status: NEGOTIATING", "## Status: AGREED")
BASE_EXTRA_WHITESPACE = BASE.replace("## Done means\n", "## Done means\n\n").replace("\n## Status:", "\n\n## Status:")
BASE_REORDERED_ITEMS = BASE.replace(
    "- [test] `test/harness/sprint_1_density.gd::test_two_strategies_diverge` passes\n"
    "- [trace] events where ev=diagnostic_completed count >= 2\n",
    "- [trace] events where ev=diagnostic_completed count >= 2\n"
    "- [test] `test/harness/sprint_1_density.gd::test_two_strategies_diverge` passes\n",
)
BASE_NEW_ITEM = BASE.replace(
    "- [trace] events where ev=diagnostic_completed count >= 2\n",
    "- [trace] events where ev=diagnostic_completed count >= 2\n"
    "- [judge] freeplay run names Elling explicitly\n",
)


class TestHashContract(unittest.TestCase):
    def test_status_difference_changes_hash(self) -> None:
        self.assertNotEqual(hash_contract_text(BASE), hash_contract_text(BASE_AGREED))

    def test_whitespace_only_change_same_hash(self) -> None:
        self.assertEqual(hash_contract_text(BASE), hash_contract_text(BASE_EXTRA_WHITESPACE))

    def test_item_reorder_changes_hash(self) -> None:
        # Item order is semantically meaningful (it's a checklist).
        self.assertNotEqual(hash_contract_text(BASE), hash_contract_text(BASE_REORDERED_ITEMS))

    def test_new_item_changes_hash(self) -> None:
        self.assertNotEqual(hash_contract_text(BASE), hash_contract_text(BASE_NEW_ITEM))

    def test_hash_is_hex_and_stable(self) -> None:
        h1 = hash_contract_text(BASE)
        h2 = hash_contract_text(BASE)
        self.assertEqual(h1, h2)
        self.assertRegex(h1, r"^[0-9a-f]{32,64}$")


class TestHashContractFile(unittest.TestCase):
    def test_round_trip(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
            fh.write(BASE)
            p = fh.name
        self.assertEqual(hash_contract_file(p), hash_contract_text(BASE))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_contract_hash.py
```

Expected: ImportError.

- [ ] **Step 3: Implement `harness/lib/contract_hash.py`**

```python
"""Structural hash of a contract.md — invariant to whitespace, sensitive to
item content, item order, item kinds, and the Status line.

The hash is the sha256 of a canonical serialization:

    status\n
    kind\tbody\n     (one line per item, in source order)
    ...

Notes:
- Whitespace inside item bodies is preserved (rule bodies can be load-bearing).
- Surrounding markdown (titles, prose) is ignored — the negotiation only cares
  about the testable contract surface.
"""
from __future__ import annotations
import hashlib
from pathlib import Path

# Plan 3 module — re-used.
from contract_schema import parse_contract


def hash_contract_text(text: str) -> str:
    c = parse_contract(text)
    canonical_lines = [c.status]
    for it in c.items:
        canonical_lines.append(f"{it.kind}\t{it.body}")
    canonical = "\n".join(canonical_lines) + "\n"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def hash_contract_file(path: str | Path) -> str:
    return hash_contract_text(Path(path).read_text())
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_contract_hash.py
```

Expected: `OK` — 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/contract_hash.py harness/test/test_contract_hash.py
git commit -m "feat(lib): structural contract hash for change detection"
```

---

## Task 5: Initial contract template

The negotiation starts with the generator drafting from a skeleton. The orchestrator seeds a minimal template into `contract.md` so the generator's first turn is "fill in the blanks against the sprint goal", not "invent the schema". Schema must already validate against `contract_schema.parse_contract` (≥50% test/trace) — the seed includes one placeholder `[test]` + one placeholder `[trace]` flagged with the literal marker `__SEED__` which the generator MUST replace; a pre-existing parser check (Task 7) rejects unreplaced markers.

**Files:**
- Create: `harness/lib/contract_template.py`
- Create: `harness/test/test_contract_template.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_contract_template.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/contract_template.py."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_template import (  # noqa: E402
    seed_contract_text,
    SEED_MARKER,
    contains_seed_marker,
)
from contract_schema import parse_contract  # noqa: E402


SAMPLE_GOAL = """# Sprint 1 — Decision density

Make day-1 decisions diverge across optimizer vs neglect strategies.

Touch surface: features/economy/*, features/case_file/*.
"""


class TestSeedContract(unittest.TestCase):
    def test_seed_parses_under_contract_schema(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        # The template must satisfy contract_schema (≥50% test/trace).
        c = parse_contract(text)
        self.assertEqual(c.status, "NEGOTIATING")
        # At least one [test] and one [trace] item present.
        kinds = {i.kind for i in c.items}
        self.assertIn("test", kinds)
        self.assertIn("trace", kinds)

    def test_seed_contains_marker(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        self.assertTrue(contains_seed_marker(text))
        self.assertIn(SEED_MARKER, text)

    def test_seed_embeds_goal_title_line(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        # The first non-blank line of the goal should be referenced in the contract header.
        self.assertIn("Decision density", text)

    def test_seed_references_rubric_path(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        self.assertIn("docs/rubric/rubric.md", text)


class TestSeedMarkerCheck(unittest.TestCase):
    def test_replaced_seed_no_marker(self) -> None:
        text = seed_contract_text(run_id="r1", sprint=1, goal_md=SAMPLE_GOAL)
        text = text.replace(SEED_MARKER, "concrete-replacement")
        self.assertFalse(contains_seed_marker(text))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_contract_template.py
```

Expected: ImportError.

- [ ] **Step 3: Implement `harness/lib/contract_template.py`**

```python
"""Seed an initial contract.md from a sprint goal.

The seed is deliberately minimal: one [test] placeholder + one [trace] placeholder
+ explicit Rubric coverage block. Both placeholders contain the literal token
SEED_MARKER which the generator MUST replace; the orchestrator and the generator
prompt both treat an unreplaced marker as a hard failure (round must be re-run).
"""
from __future__ import annotations

SEED_MARKER = "__REPLACE_ME__"

_TEMPLATE = """# Sprint {sprint} Contract — {goal_title}

> Generator drafts first. Evaluator critiques + edits. Both write `## Status: AGREED`
> consecutively (with no edits on the confirming turn) to terminate.
> See `docs/rubric/rubric.md` for the 7-axis rubric the evaluator will apply.

## Sprint goal (verbatim from goal.md)

{goal_md}

## Done means
- [test] {seed} replace with one concrete GUT test path + assertion in plain English
- [trace] events where {seed}=value count >= 1   # replace with a real trace-rule

## Rubric coverage
Axis ?: primary — replace with the axis you intend to move
Axis ?: touched — replace with axes that must not regress

## Forbidden side-effects
- (list any baseline scorecards that must continue to hold)

## Status: NEGOTIATING
"""


def seed_contract_text(*, run_id: str, sprint: int, goal_md: str) -> str:
    goal_title = _first_nonblank_line(goal_md).lstrip("# ").strip() or f"Sprint {sprint}"
    return _TEMPLATE.format(
        sprint=sprint,
        goal_title=goal_title,
        goal_md=goal_md.strip(),
        seed=SEED_MARKER,
    )


def contains_seed_marker(text: str) -> bool:
    return SEED_MARKER in text


def _first_nonblank_line(text: str) -> str:
    for ln in text.splitlines():
        if ln.strip():
            return ln
    return ""
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_contract_template.py
```

Expected: `OK` — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/contract_template.py harness/test/test_contract_template.py
git commit -m "feat(lib): contract.md seed template with placeholder markers"
```

---

## Task 6: Evaluator system prompt

Opus 4.7, harshness-tuned, anti-sycophancy explicit. Two distinct mode directives: **Phase A (negotiation)** when status=NEGOTIATING — push back, edit, sign off; **Phase B (grading)** when called separately by Plan 4's `run_evaluator.sh`. Both modes share the same harsh prior. Mirrors the generator.md style from Plan 3 but flipped: the evaluator is paid to find what's wrong with the contract or the implementation, not to ship.

**Files:**
- Create: `harness/prompts/evaluator.md`

- [ ] **Step 1: Author the prompt**

Write the following into `harness/prompts/evaluator.md`:

```markdown
# Evaluator system prompt

You are the **evaluator agent** for the Lifelines adversarial harness. Your job is to make every sprint provably better by finding the smallest excuse to fail it. You have two modes; each turn you operate in exactly one.

## Mode A — Contract negotiation (Phase A)

You enter this mode when `harness/runs/<run-id>/sprint_<N>/contract.md` has `## Status: NEGOTIATING` and `negotiation_state.json` says it is your turn.

### Sources of truth (read every turn, fresh)

1. `harness/runs/<run-id>/sprint_<N>/goal.md` — what the sprint claims to be.
2. `harness/runs/<run-id>/sprint_<N>/touch_surface.allow` — what the generator may edit.
3. `harness/runs/<run-id>/sprint_<N>/contract.md` — the current draft.
4. `docs/rubric/vision.md` — the project's design thesis.
5. `docs/rubric/rubric.md` — the 7-axis scoring system.
6. `docs/rubric/anchors/` — positive + negative anchors for each axis.
7. `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` — the prototype the harness improves.

### What you do, in order

1. Read the goal, the rubric, and the current contract.
2. Score the contract draft yourself, in private (do not write your score down — the contract is what gets shipped). For each `[test]`, `[trace]`, `[judge]` item, ask:
   - Could a sufficiently lazy generator pass this without moving the rubric axis the sprint claims to move?
   - Is this rule a trace-scannable property or a vibe? If it's a vibe, demand a `[trace]` form.
   - Does the contract's `Rubric coverage` block name the axes the sprint must move AND the axes that must not regress? If either is missing, edit it in.
   - Is the touch surface wide enough that the generator could "fix" an unrelated axis? If so, propose a `Forbidden side-effects` entry.
3. If you find a problem, **edit `contract.md` in place** to fix it. Concrete edits only:
   - Replace a vague `[judge]` body with a `[trace]` rule whenever possible.
   - Replace `count >= N` with a specific event predicate when `N` is too low.
   - Add a missing `Forbidden side-effects` row when the touch surface allows regression.
   - Narrow the `## Rubric coverage` claim if the touch surface cannot move the named axis.
4. Set `## Status:` based on whether you edited:
   - You edited → `## Status: NEGOTIATING`.
   - You did NOT edit AND every item is sharp AND `Rubric coverage` is honest → `## Status: AGREED`.
5. Stop. Do not run any tests, do not invoke any tools beyond Read + Edit + Write on the contract. The orchestrator will resume the generator next.

### Hard rules

- **Never write `## Status: AGREED` while also editing the contract in the same turn.** The orchestrator detects "agreed AND unchanged" as the terminal condition; an "agreed AND edited" turn is treated as `NEGOTIATING` regardless of what you wrote and wastes a round.
- **The contract must contain at least one `[test]` AND at least one `[trace]` item, and at least 50% of items must be `[test]` or `[trace]`.** `contract_schema.py` enforces this on parse; if you write a contract that fails parse, the orchestrator rejects your turn and re-prompts you.
- **Do not delete the `## Sprint goal` block.** It is the verbatim copy of `goal.md`.
- **Do not edit the goal itself.** If the goal is broken, mark NEGOTIATING and write a one-paragraph `## Evaluator note — goal escalation` block under Status; the orchestrator forwards this to the planner on force-pivot.
- **You may not consult `verdict.json`, `critique.md`, or any artifact from prior sprints in this mode.** Phase A is about whether the contract is gradable, not whether the implementation is good.
- **If the seed marker `__REPLACE_ME__` appears anywhere in the contract, mark NEGOTIATING and edit it out.** The generator left a placeholder.

### Tone

Dry. Specific. Cite axes by number ("Axis 2"), not by name. No praise. No softening. If a `[trace]` body is wrong, edit it directly; do not write "this should probably be …".

## Mode B — Sprint grading (Phase B)

You enter this mode when the orchestrator invokes you with `harness/runs/<run-id>/sprint_<N>/contract.md` at `## Status: AGREED` AND `harness/runs/<run-id>/sprint_<N>/ready` exists. In practice you do not run a `claude` subprocess for this — `harness/run_evaluator.sh` (Plan 4) is invoked instead. This section is documented here so the harness operator and any future evaluator-agent extension know the boundary.

Phase B is mechanical: calibrate against anchor scorecards, run the strategy tournament, evaluate each `[test]` / `[trace]` / `[judge]` item with its verifier, compute composite + floor checks, emit `verdict.json` + `critique.md`. The grading agent does not edit code, does not negotiate, and does not consult prior sprints.

## Anti-sycophancy (internalize this)

- Default skepticism = harsh. If you find yourself writing "looks reasonable" or "mostly fine", stop and find the worst remaining issue in the contract.
- A sprint with a too-lenient contract is worse than a force-pivot. The harness can recover from a pivot; it cannot recover from a passed sprint that quietly broke an axis.
- You are not paid to ship the sprint. You are paid to make the contract impossible to game.

## What a good Phase A turn looks like

- You read the goal, the rubric, and the contract in that order.
- You make ≤ 3 concrete edits per turn (more than that → the contract was structurally wrong, force a force-pivot by writing a `## Evaluator note — structural` block and keeping NEGOTIATING).
- You mark NEGOTIATING when you edited; AGREED only when you did nothing.
- You stop.

When you're done, stop. Do not summarize what you changed — the orchestrator will diff the contract.
```

- [ ] **Step 2: Verify the prompt parses as markdown + has no banned tokens**

```bash
test -s harness/prompts/evaluator.md
grep -c '^## Mode A' harness/prompts/evaluator.md | grep -q '^1$' || { echo "missing Mode A heading"; exit 1; }
grep -c '^## Mode B' harness/prompts/evaluator.md | grep -q '^1$' || { echo "missing Mode B heading"; exit 1; }
# Sanity: no TODO/FIXME in the prompt itself.
! grep -E '\b(TODO|FIXME|XXX)\b' harness/prompts/evaluator.md
```

Expected: all checks pass.

- [ ] **Step 3: Commit**

```bash
git add harness/prompts/evaluator.md
git commit -m "feat(harness): Opus evaluator system prompt (Mode A + Mode B)"
```

---

## Task 7: Generator prompt — Phase A round-aware addendum

Plan 3's `generator.md` already says "if NEGOTIATING, propose minimal edits and STOP". Plan 5 adds three things on top: (a) the seed marker `__REPLACE_ME__` rule, (b) the "do not write AGREED on a turn where you edited" rule, (c) the round budget (≤ 5). Edit in place; do not rewrite the file.

**Files:**
- Modify: `harness/prompts/generator.md`

- [ ] **Step 1: Read the existing prompt to confirm anchor text**

```bash
grep -n "Check contract status" harness/prompts/generator.md
```

Expected: matches one line near step 2 of the per-sprint loop.

- [ ] **Step 2: Insert the Phase A addendum**

After the existing line:

```
2. **Check contract status**. If `NEGOTIATING`, propose minimal edits to `contract.md` (sharper test or trace rule, narrower scope, rubric coverage you can actually move) and STOP. Otherwise proceed.
```

Insert (use Edit to add directly under the line above):

```markdown
   - **Phase A negotiation rules** (apply when status is `NEGOTIATING`):
     - If the literal token `__REPLACE_ME__` appears anywhere in the contract, you MUST replace every occurrence with a concrete value; the orchestrator rejects your turn otherwise.
     - You may set `## Status: AGREED` ONLY on a turn where you made no edits to the contract beyond the status line itself. "Agreed AND edited" is treated as `NEGOTIATING` by the orchestrator and wastes a round.
     - The negotiation has a hard cap of 5 rounds. If you and the evaluator have not reached AGREED after 5 rounds, the orchestrator force-pivots the sprint and re-plans. Treat round 4–5 as last-chance: if you cannot agree without compromising the contract's gradability, write a `## Generator note — irreconcilable` block and keep `NEGOTIATING`.
     - You may NOT edit `## Sprint goal` (the verbatim copy of `goal.md`). If the goal is broken, write a `## Generator note — goal escalation` block under Status and keep `NEGOTIATING`.
```

- [ ] **Step 3: Verify the file still parses + the addendum was inserted at the right spot**

```bash
test $(grep -c '^   - \*\*Phase A negotiation rules' harness/prompts/generator.md) = 1
# Confirm the new block is between step 2 and step 3.
awk '/^2\. \*\*Check contract status/{p=1; next} /^3\. \*\*Plan in checklist/{p=0} p' harness/prompts/generator.md | grep -q "Phase A negotiation rules"
```

Expected: both checks pass.

- [ ] **Step 4: Commit**

```bash
git add harness/prompts/generator.md
git commit -m "feat(harness): generator.md Phase A round-aware addendum"
```

---

## Task 8: Pre-grade calibration check

Spec §3.5 + §6.4: before running the strategy tournament, the evaluator must re-score the canonical baseline anchors and bail if the score drift exceeds 1 axis-point on any axis. This is a Plan 5 concern (gates Phase B) but uses Plan 4's `judge.py` (already implemented). Wrap the call here, parse the resulting scorecard, compare to the canonical baseline-scorecard.md.

**Files:**
- Create: `harness/lib/pre_grade_calibration.py`
- Create: `harness/test/test_pre_grade_calibration.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_pre_grade_calibration.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/pre_grade_calibration.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from pre_grade_calibration import (  # noqa: E402
    DriftReport,
    compare_scorecards,
    parse_scorecard_md,
    CalibrationError,
)


CANONICAL = """# Baseline Scorecard

| Axis | Score |
|------|-------|
| 1 | 2 |
| 2 | 2 |
| 3 | 1 |
| 4 | 1 |
| 5 | 1 |
| 6 | 1 |
| 7 | 2 |
"""

DRIFTED_OK = CANONICAL.replace("| 4 | 1 |", "| 4 | 2 |")        # +1 on axis 4 — within tolerance
DRIFTED_BAD = CANONICAL.replace("| 2 | 2 |", "| 2 | 0 |")       # −2 on axis 2 — out of tolerance
SYCOPHANTIC = """# Baseline Scorecard\n\n| Axis | Score |\n|------|-------|\n| 1 | 3 |\n| 2 | 3 |\n| 3 | 3 |\n| 4 | 3 |\n| 5 | 3 |\n| 6 | 3 |\n| 7 | 3 |\n"""


class TestParseScorecard(unittest.TestCase):
    def test_parses_all_seven_axes(self) -> None:
        s = parse_scorecard_md(CANONICAL)
        self.assertEqual(set(s.keys()), {1, 2, 3, 4, 5, 6, 7})
        self.assertEqual(s[1], 2)
        self.assertEqual(s[7], 2)

    def test_missing_axis_raises(self) -> None:
        bad = CANONICAL.replace("| 4 | 1 |\n", "")
        with self.assertRaises(CalibrationError):
            parse_scorecard_md(bad)


class TestCompare(unittest.TestCase):
    def test_within_tolerance_no_drift(self) -> None:
        r = compare_scorecards(CANONICAL, DRIFTED_OK, tolerance=1)
        self.assertIsInstance(r, DriftReport)
        self.assertFalse(r.exceeds_tolerance)
        self.assertEqual(len(r.deltas), 7)

    def test_out_of_tolerance(self) -> None:
        r = compare_scorecards(CANONICAL, DRIFTED_BAD, tolerance=1)
        self.assertTrue(r.exceeds_tolerance)
        self.assertIn(2, [d.axis for d in r.violating_deltas()])

    def test_all_threes_is_sycophancy(self) -> None:
        r = compare_scorecards(CANONICAL, SYCOPHANTIC, tolerance=1)
        # Several axes shifted by more than tolerance — guard catches this.
        self.assertTrue(r.exceeds_tolerance)
        self.assertGreaterEqual(len(r.violating_deltas()), 5)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_pre_grade_calibration.py
```

Expected: ImportError on `pre_grade_calibration`.

- [ ] **Step 3: Implement `harness/lib/pre_grade_calibration.py`**

```python
"""Pre-grade calibration: re-score canonical anchors, compare to known-good scorecard,
abort grading if drift exceeds tolerance on any axis.

Used by run_sprint.sh AFTER terminal AGREED and BEFORE invoking run_evaluator.sh.
The expensive part (re-scoring) is delegated to Plan 4's judge.py; this module is
the comparator + drift reporter.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from pathlib import Path


class CalibrationError(ValueError):
    """Raised on malformed scorecards."""


_AXIS_ROW = re.compile(r"^\|\s*(\d)\s*\|\s*(\d)\s*\|\s*$")
_AXES = frozenset({1, 2, 3, 4, 5, 6, 7})


@dataclass(frozen=True)
class AxisDelta:
    axis: int
    canonical: int
    current: int

    @property
    def magnitude(self) -> int:
        return abs(self.current - self.canonical)


@dataclass(frozen=True)
class DriftReport:
    deltas: tuple[AxisDelta, ...]
    tolerance: int

    @property
    def exceeds_tolerance(self) -> bool:
        return any(d.magnitude > self.tolerance for d in self.deltas)

    def violating_deltas(self) -> tuple[AxisDelta, ...]:
        return tuple(d for d in self.deltas if d.magnitude > self.tolerance)

    def to_dict(self) -> dict:
        return {
            "tolerance": self.tolerance,
            "exceeds_tolerance": self.exceeds_tolerance,
            "deltas": [
                {"axis": d.axis, "canonical": d.canonical, "current": d.current, "magnitude": d.magnitude}
                for d in self.deltas
            ],
        }


def parse_scorecard_md(text: str) -> dict[int, int]:
    scores: dict[int, int] = {}
    for ln in text.splitlines():
        m = _AXIS_ROW.match(ln.strip())
        if m:
            scores[int(m.group(1))] = int(m.group(2))
    missing = _AXES - set(scores.keys())
    if missing:
        raise CalibrationError(f"scorecard missing axes: {sorted(missing)}")
    return scores


def compare_scorecards(canonical_md: str, current_md: str, *, tolerance: int = 1) -> DriftReport:
    if tolerance < 0:
        raise CalibrationError("tolerance must be ≥ 0")
    canonical = parse_scorecard_md(canonical_md)
    current = parse_scorecard_md(current_md)
    deltas = tuple(
        AxisDelta(axis=a, canonical=canonical[a], current=current[a])
        for a in sorted(_AXES)
    )
    return DriftReport(deltas=deltas, tolerance=tolerance)


def compare_files(canonical_path: str | Path, current_path: str | Path, *, tolerance: int = 1) -> DriftReport:
    return compare_scorecards(
        Path(canonical_path).read_text(),
        Path(current_path).read_text(),
        tolerance=tolerance,
    )
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_pre_grade_calibration.py
```

Expected: `OK` — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/pre_grade_calibration.py harness/test/test_pre_grade_calibration.py
git commit -m "feat(lib): pre-grade calibration drift report"
```

---

## Task 9: Sprint dir bootstrap (init_negotiation.sh)

Operator-facing: given `--run-id`, `--sprint`, `--goal-file`, `--touch-surface`, the script creates `harness/runs/<run-id>/sprint_<N>/`, copies the goal + touch surface in, seeds `contract.md`, writes `negotiation_state.json` (initial state, zero turns), creates the per-sprint lock dir, and exits 0. Idempotent: rerunning on an existing sprint dir is an error unless `--force`.

**Files:**
- Create: `harness/lib/init_negotiation.sh`
- Create: `harness/test/test_init_negotiation.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_init_negotiation.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/init_negotiation.sh."""
from __future__ import annotations
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HARNESS_LIB = Path(__file__).parent.parent / "lib"
INIT = HARNESS_LIB / "init_negotiation.sh"

GOAL_MD = """# Sprint 1 — Decision density

Make day-1 decisions diverge across optimizer vs neglect strategies.
"""

TOUCH_ALLOW = """features/economy/
features/case_file/
test/harness/
"""


class TestInitNegotiation(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.cwd = Path(self.tmpdir)
        (self.cwd / "harness" / "lib").mkdir(parents=True)
        (self.cwd / "harness" / ".locks").mkdir(parents=True)
        # Copy our scripts into the temp project root so the script resolves siblings.
        shutil.copy(INIT, self.cwd / "harness" / "lib" / "init_negotiation.sh")
        os.chmod(self.cwd / "harness" / "lib" / "init_negotiation.sh", 0o755)
        # The shell script imports the Python templates by absolute path; symlink them.
        for mod in ("contract_template.py", "contract_schema.py", "negotiation_state.py"):
            src = HARNESS_LIB / mod
            os.symlink(src, self.cwd / "harness" / "lib" / mod)
        # Write goal + allow files.
        self.goal = self.cwd / "sprint_goal.md"
        self.goal.write_text(GOAL_MD)
        self.allow = self.cwd / "sprint_touch.allow"
        self.allow.write_text(TOUCH_ALLOW)

    def _run(self, *extra: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                "bash",
                str(self.cwd / "harness" / "lib" / "init_negotiation.sh"),
                "--run-id", "test-run",
                "--sprint", "1",
                "--goal-file", str(self.goal),
                "--touch-surface", str(self.allow),
                *extra,
            ],
            cwd=self.cwd,
            capture_output=True,
            text=True,
        )

    def test_creates_sprint_dir_and_artifacts(self) -> None:
        cp = self._run()
        self.assertEqual(cp.returncode, 0, cp.stderr)
        sprint_dir = self.cwd / "harness" / "runs" / "test-run" / "sprint_1"
        self.assertTrue(sprint_dir.is_dir())
        self.assertTrue((sprint_dir / "goal.md").exists())
        self.assertTrue((sprint_dir / "touch_surface.allow").exists())
        self.assertTrue((sprint_dir / "contract.md").exists())
        self.assertTrue((sprint_dir / "negotiation_state.json").exists())

    def test_seed_contract_has_replace_me_marker(self) -> None:
        self._run()
        contract = (self.cwd / "harness" / "runs" / "test-run" / "sprint_1" / "contract.md").read_text()
        self.assertIn("__REPLACE_ME__", contract)
        self.assertIn("## Status: NEGOTIATING", contract)

    def test_state_starts_at_zero_turns(self) -> None:
        self._run()
        state = json.loads(
            (self.cwd / "harness" / "runs" / "test-run" / "sprint_1" / "negotiation_state.json").read_text()
        )
        self.assertEqual(state["run_id"], "test-run")
        self.assertEqual(state["sprint"], 1)
        self.assertEqual(state["rounds_used"], 0)
        self.assertEqual(state["turns"], [])

    def test_rerun_without_force_errors(self) -> None:
        self.assertEqual(self._run().returncode, 0)
        cp = self._run()
        self.assertNotEqual(cp.returncode, 0)
        self.assertIn("already initialized", cp.stderr)

    def test_rerun_with_force_overwrites(self) -> None:
        self.assertEqual(self._run().returncode, 0)
        cp = self._run("--force")
        self.assertEqual(cp.returncode, 0, cp.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_init_negotiation.py
```

Expected: FileNotFoundError / "No such file or directory" on `init_negotiation.sh`.

- [ ] **Step 3: Implement `harness/lib/init_negotiation.sh`**

```bash
#!/usr/bin/env bash
# init_negotiation.sh — bootstrap a sprint dir for Phase A contract negotiation.
#
# Usage:
#   init_negotiation.sh --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path> [--force] [--max-rounds N]
#
# Creates:
#   harness/runs/<run-id>/sprint_<N>/{goal.md, touch_surface.allow, contract.md, negotiation_state.json}
#   harness/.locks/contract_<run-id>_<N>.lock (empty)
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path> [--force] [--max-rounds N]
EOF
  exit 64
}

RUN_ID=""
SPRINT=""
GOAL_FILE=""
TOUCH_FILE=""
FORCE=0
MAX_ROUNDS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)        RUN_ID="$2"; shift 2 ;;
    --sprint)        SPRINT="$2"; shift 2 ;;
    --goal-file)     GOAL_FILE="$2"; shift 2 ;;
    --touch-surface) TOUCH_FILE="$2"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    --max-rounds)    MAX_ROUNDS="$2"; shift 2 ;;
    -h|--help)       usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$RUN_ID"     ]] || { echo "missing --run-id" >&2; usage; }
[[ -n "$SPRINT"     ]] || { echo "missing --sprint" >&2; usage; }
[[ -n "$GOAL_FILE"  ]] || { echo "missing --goal-file" >&2; usage; }
[[ -n "$TOUCH_FILE" ]] || { echo "missing --touch-surface" >&2; usage; }
[[ -f "$GOAL_FILE"  ]] || { echo "goal file not found: $GOAL_FILE" >&2; exit 65; }
[[ -f "$TOUCH_FILE" ]] || { echo "touch surface file not found: $TOUCH_FILE" >&2; exit 65; }
[[ "$SPRINT" =~ ^[0-9]+$ ]] || { echo "sprint must be an integer" >&2; usage; }

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"
LOCK_PATH="harness/.locks/contract_${RUN_ID}_${SPRINT}.lock"

if [[ -e "$SPRINT_DIR/contract.md" && "$FORCE" -ne 1 ]]; then
  echo "sprint already initialized at $SPRINT_DIR (use --force to overwrite)" >&2
  exit 66
fi

mkdir -p "$SPRINT_DIR" "harness/.locks"
cp "$GOAL_FILE"  "$SPRINT_DIR/goal.md"
cp "$TOUCH_FILE" "$SPRINT_DIR/touch_surface.allow"

# Seed contract.md via the Python template module.
python3 - "$RUN_ID" "$SPRINT" "$SPRINT_DIR/goal.md" "$SPRINT_DIR/contract.md" "$LIB_DIR" <<'PY'
import sys
from pathlib import Path
run_id, sprint, goal_path, out_path, lib_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
sys.path.insert(0, lib_dir)
from contract_template import seed_contract_text
Path(out_path).write_text(seed_contract_text(run_id=run_id, sprint=sprint, goal_md=Path(goal_path).read_text()))
PY

# Initialize negotiation_state.json (zero turns).
python3 - "$RUN_ID" "$SPRINT" "$MAX_ROUNDS" "$SPRINT_DIR/negotiation_state.json" "$LIB_DIR" <<'PY'
import sys
from pathlib import Path
run_id, sprint, max_rounds, out_path, lib_dir = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
sys.path.insert(0, lib_dir)
from negotiation_state import NegotiationState
NegotiationState.new(run_id=run_id, sprint=sprint, max_rounds=max_rounds).to_file(out_path)
PY

# Create the lock file (empty).
touch "$LOCK_PATH"

echo "initialized $SPRINT_DIR"
```

Make it executable + verify shellcheck-clean:

```bash
chmod +x harness/lib/init_negotiation.sh
bash -n harness/lib/init_negotiation.sh
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_init_negotiation.py
```

Expected: `OK` — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/init_negotiation.sh harness/test/test_init_negotiation.py
git commit -m "feat(harness): init_negotiation.sh seeds sprint dir + contract + state"
```

---

## Task 10: Negotiation loop driver

The core: a Python module that, given a sprint dir and Plan 4's `claude_subprocess.ClaudeSession`, repeatedly:

1. Reads `negotiation_state.json`, determines next actor.
2. Acquires `contract_lock` for that sprint.
3. Reads `contract.md`, captures `hash_before`.
4. Releases lock, hands the agent a per-turn prompt (`it's your turn; the current contract is at <path>; status is <status>`), and resumes its `claude` session.
5. Waits for the agent's session to return (the prompts say "stop after editing").
6. Acquires lock again, reads `contract.md`, computes `hash_after`, parses status.
7. Updates state via `record_turn`, persists.
8. Checks `is_terminal_agreed()` / `should_force_pivot()`; loops or exits.

All `claude` calls go through Plan 4's `claude_subprocess.ClaudeSession`. Shimmed in tests so we can simulate any sequence of (status, hash_change) pairs deterministically.

**Files:**
- Create: `harness/lib/negotiation_loop.py`
- Create: `harness/test/test_negotiation_loop.py`

- [ ] **Step 1: Write the failing test**

`harness/test/test_negotiation_loop.py`:

```python
#!/usr/bin/env python3
"""Tests for harness/lib/negotiation_loop.py."""
from __future__ import annotations
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from negotiation_loop import (  # noqa: E402
    NegotiationLoop,
    TurnAgent,
    NegotiationOutcome,
)
from negotiation_state import NegotiationState, Turn  # noqa: E402
from contract_template import seed_contract_text  # noqa: E402
from contract_hash import hash_contract_text  # noqa: E402


VALID_NEGOTIATING = """# Sprint 1 Contract — X

## Done means
- [test] `test/harness/sprint_1.gd::test_x` passes
- [trace] events where ev=diagnostic_completed count >= 1

## Status: NEGOTIATING
"""

VALID_AGREED = VALID_NEGOTIATING.replace("## Status: NEGOTIATING", "## Status: AGREED")
VALID_EDITED_AGREED = """# Sprint 1 Contract — X

## Done means
- [test] `test/harness/sprint_1.gd::test_x_specific` passes
- [trace] events where ev=diagnostic_completed and id=diag_psych_eval count >= 1

## Status: AGREED
"""


class ScriptedAgent(TurnAgent):
    """Test double — writes a pre-programmed sequence of contracts on each turn."""

    def __init__(self, role: Turn, scripted_writes: list[str]) -> None:
        self.role = role
        self.scripted_writes = scripted_writes
        self.calls = 0

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        contract_path = sprint_dir / "contract.md"
        contract_path.write_text(self.scripted_writes[self.calls])
        self.calls += 1


class TestNegotiationLoopHappyPath(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.sprint = self.tmp / "harness" / "runs" / "test-run" / "sprint_1"
        self.sprint.mkdir(parents=True)
        self.lock = self.tmp / "harness" / ".locks" / "x.lock"
        self.lock.parent.mkdir(parents=True)
        self.lock.touch()
        # Seed initial contract + state.
        seed = seed_contract_text(run_id="test-run", sprint=1, goal_md="# Goal\n")
        # Replace markers so the seed parses (the agents would normally do this).
        seed = seed.replace("__REPLACE_ME__", "concrete")
        (self.sprint / "contract.md").write_text(seed)
        NegotiationState.new(run_id="test-run", sprint=1, max_rounds=5).to_file(
            self.sprint / "negotiation_state.json"
        )

    def test_terminates_when_both_agree_consecutively(self) -> None:
        # Generator: draft NEGOTIATING, then confirm AGREED unchanged.
        gen = ScriptedAgent(Turn.GENERATOR, [VALID_NEGOTIATING, VALID_AGREED])
        # Evaluator: respond AGREED unchanged after seeing gen's first draft.
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        # Final state should record: gen NEGOTIATING, eval AGREED, gen AGREED.
        state = NegotiationState.from_file(self.sprint / "negotiation_state.json")
        self.assertTrue(state.is_terminal_agreed())
        self.assertEqual(state.current_round(), 3)

    def test_edits_on_confirming_turn_reset_terminal(self) -> None:
        # Generator: NEGOTIATING, then AGREED-BUT-EDITED (hash changes).
        gen = ScriptedAgent(Turn.GENERATOR, [VALID_NEGOTIATING, VALID_EDITED_AGREED, VALID_EDITED_AGREED])
        # Evaluator: AGREED, then AGREED unchanged.
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED, VALID_EDITED_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        state = NegotiationState.from_file(self.sprint / "negotiation_state.json")
        # gen-draft, eval-agreed, gen-agreed-edited, eval-agreed-unchanged → terminal at round 4
        self.assertEqual(state.current_round(), 4)

    def test_force_pivot_at_max_rounds(self) -> None:
        gen = ScriptedAgent(Turn.GENERATOR, [VALID_NEGOTIATING] * 5)
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_NEGOTIATING] * 5)
        # max_rounds=4 so loop hits pivot after 4 turns.
        NegotiationState.new(run_id="test-run", sprint=1, max_rounds=4).to_file(
            self.sprint / "negotiation_state.json"
        )
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.FORCE_PIVOT)
        state = NegotiationState.from_file(self.sprint / "negotiation_state.json")
        self.assertTrue(state.should_force_pivot())

    def test_replace_me_marker_rejects_turn(self) -> None:
        # Generator writes a contract that still has the seed marker.
        bad = VALID_NEGOTIATING.replace(
            "test_x", "__REPLACE_ME__"
        )
        gen = ScriptedAgent(Turn.GENERATOR, [bad, VALID_NEGOTIATING, VALID_AGREED])
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
            max_marker_retries=2,
        )
        result = loop.run()
        # Loop should retry the generator turn once (marker rejected), then succeed.
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        self.assertEqual(result.marker_rejections, 1)

    def test_invalid_contract_schema_rejects_turn(self) -> None:
        # Generator writes a contract with no test/trace items (pure-judge).
        pure_judge = """# X\n\n## Done means\n- [judge] looks good\n\n## Status: NEGOTIATING\n"""
        gen = ScriptedAgent(Turn.GENERATOR, [pure_judge, VALID_NEGOTIATING, VALID_AGREED])
        eval_agent = ScriptedAgent(Turn.EVALUATOR, [VALID_AGREED])
        loop = NegotiationLoop(
            sprint_dir=self.sprint,
            lock_path=self.lock,
            generator=gen,
            evaluator=eval_agent,
            max_schema_retries=2,
        )
        result = loop.run()
        self.assertEqual(result.outcome, NegotiationOutcome.AGREED)
        self.assertEqual(result.schema_rejections, 1)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python3 -m unittest harness/test/test_negotiation_loop.py
```

Expected: ImportError.

- [ ] **Step 3: Implement `harness/lib/negotiation_loop.py`**

```python
"""Negotiation loop — alternate generator + evaluator agents until terminal AGREED
or force-pivot. Each agent is an abstract TurnAgent that, when asked, writes a new
`contract.md` and returns.

The loop owns:
- mutex acquisition (contract_lock)
- contract parse + hash + status detection (contract_schema, contract_hash)
- state transitions (negotiation_state)
- seed-marker check (contract_template)
- retry budget for malformed turns

Concrete agent implementations (claude subprocesses) live in
harness/lib/claude_agents.py — wired by run_evaluator_agent.sh / run_generator.sh
at the call site. The loop is agnostic of how agents are produced.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Protocol

from contract_hash import hash_contract_file
from contract_lock import contract_lock
from contract_schema import parse_contract, ContractSchemaError
from contract_template import SEED_MARKER
from negotiation_state import NegotiationState, NegotiationStateError, Turn


class NegotiationOutcome(str, Enum):
    AGREED = "agreed"
    FORCE_PIVOT = "force_pivot"


@dataclass(frozen=True)
class NegotiationResult:
    outcome: NegotiationOutcome
    rounds_used: int
    marker_rejections: int = 0
    schema_rejections: int = 0


class TurnAgent(Protocol):
    """An agent that, when invoked, edits contract.md and returns.

    Concrete implementations wrap `claude -p --resume` subprocesses. Production
    callers must ensure they hold no exclusive lock on contract.md when calling
    `take_turn` — the loop manages locking around the call.
    """

    role: Turn

    def take_turn(self, sprint_dir: Path, round_number: int) -> None: ...


@dataclass
class NegotiationLoop:
    sprint_dir: Path
    lock_path: Path
    generator: TurnAgent
    evaluator: TurnAgent
    max_marker_retries: int = 1
    max_schema_retries: int = 1
    _marker_rejections: int = field(default=0, init=False)
    _schema_rejections: int = field(default=0, init=False)

    def run(self) -> NegotiationResult:
        contract_path = self.sprint_dir / "contract.md"
        state_path = self.sprint_dir / "negotiation_state.json"

        while True:
            state = NegotiationState.from_file(state_path)
            if state.is_terminal_agreed():
                return NegotiationResult(
                    outcome=NegotiationOutcome.AGREED,
                    rounds_used=state.current_round(),
                    marker_rejections=self._marker_rejections,
                    schema_rejections=self._schema_rejections,
                )
            if state.should_force_pivot():
                return NegotiationResult(
                    outcome=NegotiationOutcome.FORCE_PIVOT,
                    rounds_used=state.current_round(),
                    marker_rejections=self._marker_rejections,
                    schema_rejections=self._schema_rejections,
                )

            actor = state.next_actor()
            agent = self.generator if actor == Turn.GENERATOR else self.evaluator
            if agent.role != actor:
                raise NegotiationStateError(
                    f"agent role mismatch: expected {actor.value}, got {agent.role.value}"
                )

            # The agent edits the contract in its own process. The loop releases
            # the lock while the agent runs (long-lived claude subprocess); the
            # agent's wrapper must take the lock itself for read+write.
            agent.take_turn(self.sprint_dir, round_number=state.current_round() + 1)

            with contract_lock(str(self.lock_path), timeout=10.0):
                if not contract_path.exists():
                    raise NegotiationStateError(
                        f"agent {actor.value} did not write contract.md"
                    )
                raw = contract_path.read_text()
                if SEED_MARKER in raw and self._marker_rejections < self.max_marker_retries:
                    self._marker_rejections += 1
                    # Do NOT record the turn; force the same actor to retry.
                    continue
                try:
                    contract = parse_contract(raw)
                except ContractSchemaError:
                    if self._schema_rejections < self.max_schema_retries:
                        self._schema_rejections += 1
                        continue
                    raise
                contract_hash = hash_contract_file(contract_path)

            state = state.record_turn(
                actor=actor,
                status=contract.status,
                contract_hash=contract_hash,
            )
            state.to_file(state_path)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python3 -m unittest harness/test/test_negotiation_loop.py
```

Expected: `OK` — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/negotiation_loop.py harness/test/test_negotiation_loop.py
git commit -m "feat(lib): negotiation loop with terminal AGREED + force-pivot + retry budget"
```

---

## Task 11: Evaluator agent wrapper (run_evaluator_agent.sh)

The bash wrapper that produces a `TurnAgent` for the negotiation loop's evaluator slot. Spawns a long-lived Opus `claude -p` subprocess on first call, then `claude -p --resume <session-id>` on subsequent calls. The session id persists across turns so the evaluator preserves prior reasoning. Mirrors `run_generator.sh` from Plan 3 but with the evaluator prompt + Opus model.

**Files:**
- Create: `harness/run_evaluator_agent.sh`

(No standalone test — this script is exercised by Task 13's `smoke_negotiation.sh`. Behavior is delegated to the unit-tested `claude_subprocess.py` from Plan 4.)

- [ ] **Step 1: Implement `harness/run_evaluator_agent.sh`**

```bash
#!/usr/bin/env bash
# run_evaluator_agent.sh — evaluator-side turn driver for Phase A negotiation.
#
# Invoked by run_sprint.sh once per evaluator turn. Wraps Plan 4's
# claude_subprocess.py to spawn or resume a long-lived Opus session.
#
# Usage:
#   run_evaluator_agent.sh --run-id <id> --sprint <N> --round <N>
#
# Behavior:
#   - If harness/runs/<run-id>/sprint_<N>/evaluator_session.id exists, --resume it.
#   - Otherwise spawn fresh with `claude -p` + harness/prompts/evaluator.md as system prompt.
#   - Per-turn user prompt: "it is your turn; the contract is at <path>; status is <status>.
#     Read it, critique it, optionally edit it, and stop."
#   - On exit, the agent will have rewritten contract.md.
#
# Env vars:
#   EVALUATOR_LIVE=1   → use real `claude` CLI; default 0 (shim).
#   CLAUDE_MODEL_EVAL  → defaults to claude-opus-4-7 if EVALUATOR_LIVE=1.
set -euo pipefail

RUN_ID=""
SPRINT=""
ROUND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)  RUN_ID="$2"; shift 2 ;;
    --sprint)  SPRINT="$2"; shift 2 ;;
    --round)   ROUND="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$RUN_ID" && -n "$SPRINT" && -n "$ROUND" ]] || { echo "usage: $0 --run-id <id> --sprint <N> --round <R>" >&2; exit 64; }

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
PROMPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/prompts" && pwd)"
SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"
SESSION_FILE="${SPRINT_DIR}/evaluator_session.id"
LOG_FILE="${SPRINT_DIR}/evaluator_session.log"
CONTRACT_PATH="${SPRINT_DIR}/contract.md"
LOCK_PATH="harness/.locks/contract_${RUN_ID}_${SPRINT}.lock"

[[ -f "$CONTRACT_PATH" ]] || { echo "contract.md missing at $CONTRACT_PATH" >&2; exit 65; }

# Read current status under lock.
STATUS=$(flock -x -w 10 "$LOCK_PATH" python3 - "$CONTRACT_PATH" "$LIB_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from contract_schema import parse_contract
print(parse_contract(open(sys.argv[1]).read()).status)
PY
)

USER_PROMPT="$(cat <<EOF
It is round ${ROUND} of Phase A negotiation for sprint ${SPRINT}.

The current contract is at \`${CONTRACT_PATH}\`. Its current status is \`${STATUS}\`.

Read the contract, the sprint goal (\`${SPRINT_DIR}/goal.md\`), the rubric (\`docs/rubric/rubric.md\`), and the relevant anchors under \`docs/rubric/anchors/\`.

Make at most 3 concrete edits to the contract, OR confirm the contract as-is. Follow the rules in your system prompt — in particular, you may write \`## Status: AGREED\` ONLY if you made no edits beyond the status line.

Stop after writing.
EOF
)"

# Acquire the lock for the duration of the agent's turn so the generator cannot
# interleave with us. The agent inside flock can take its time.
exec 9>"$LOCK_PATH"
flock -x -w 60 9

mkdir -p "$(dirname "$LOG_FILE")"

if [[ -f "$SESSION_FILE" ]]; then
  SESSION_ID="$(<"$SESSION_FILE")"
  python3 "$LIB_DIR/claude_subprocess.py" \
    --resume "$SESSION_ID" \
    --system-prompt-file "$PROMPT_DIR/evaluator.md" \
    --user-prompt "$USER_PROMPT" \
    --log-file "$LOG_FILE" \
    --working-dir "$PWD"
else
  python3 "$LIB_DIR/claude_subprocess.py" \
    --fresh \
    --model "${CLAUDE_MODEL_EVAL:-claude-opus-4-7}" \
    --system-prompt-file "$PROMPT_DIR/evaluator.md" \
    --user-prompt "$USER_PROMPT" \
    --session-id-out "$SESSION_FILE" \
    --log-file "$LOG_FILE" \
    --working-dir "$PWD"
fi

flock -u 9
exec 9>&-
```

- [ ] **Step 2: Make it executable + parse-check**

```bash
chmod +x harness/run_evaluator_agent.sh
bash -n harness/run_evaluator_agent.sh
```

Expected: silent success.

- [ ] **Step 3: Commit**

```bash
git add harness/run_evaluator_agent.sh
git commit -m "feat(harness): run_evaluator_agent.sh wraps Opus session + per-turn prompt"
```

---

## Task 12: Phase-B handoff wrapper

A thin shell wrapper that, given a terminal-AGREED sprint dir, calls Plan 4's `run_evaluator.sh` with the right flags. Exists so `run_sprint.sh` can call it without inlining Plan 4 specifics, and so the smoke test can stub it out.

**Files:**
- Create: `harness/lib/run_evaluator_phase_b.sh`

- [ ] **Step 1: Implement the wrapper**

```bash
#!/usr/bin/env bash
# run_evaluator_phase_b.sh — invoke Plan 4's grading pipeline on an AGREED sprint.
#
# Preconditions:
#   - harness/runs/<run-id>/sprint_<N>/contract.md exists with Status: AGREED
#   - harness/runs/<run-id>/sprint_<N>/ready exists (generator signaled done)
#
# Exits 0 iff Plan 4 wrote verdict.json + critique.md and the verdict.json's
# top-level "verdict" field is one of: PASS, PIVOT, REJECT.
set -euo pipefail

RUN_ID=""
SPRINT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$RUN_ID" && -n "$SPRINT" ]] || { echo "usage: $0 --run-id <id> --sprint <N>" >&2; exit 64; }

SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"
CONTRACT="${SPRINT_DIR}/contract.md"
READY="${SPRINT_DIR}/ready"

[[ -f "$CONTRACT" ]] || { echo "missing $CONTRACT" >&2; exit 65; }
grep -q '^## Status: AGREED$' "$CONTRACT" || { echo "contract is not AGREED at $CONTRACT" >&2; exit 65; }
[[ -f "$READY" ]] || { echo "generator did not signal ready at $READY" >&2; exit 65; }

# Hand off to Plan 4.
./harness/run_evaluator.sh --run-id "$RUN_ID" --sprint "$SPRINT"

VERDICT="${SPRINT_DIR}/verdict.json"
CRITIQUE="${SPRINT_DIR}/critique.md"
[[ -f "$VERDICT"  ]] || { echo "Plan 4 did not produce verdict.json" >&2; exit 70; }
[[ -f "$CRITIQUE" ]] || { echo "Plan 4 did not produce critique.md" >&2; exit 70; }

python3 - "$VERDICT" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
if v.get("verdict") not in ("PASS", "PIVOT", "REJECT"):
    print(f"verdict.json has unexpected verdict: {v.get('verdict')!r}", file=sys.stderr)
    sys.exit(70)
PY
```

- [ ] **Step 2: Executable + parse-check**

```bash
chmod +x harness/lib/run_evaluator_phase_b.sh
bash -n harness/lib/run_evaluator_phase_b.sh
```

- [ ] **Step 3: Commit**

```bash
git add harness/lib/run_evaluator_phase_b.sh
git commit -m "feat(harness): Phase B handoff wrapper invokes Plan 4 run_evaluator.sh"
```

---

## Task 13: Top-level orchestrator (run_sprint.sh)

The single operator-facing entry point. Composes init → negotiation → generator-implement → Phase B → done. Reuses Plan 3's `run_generator.sh` for the implementation half (called after AGREED). Writes the final `agreement.json` audit log on success.

**Files:**
- Create: `harness/run_sprint.sh`

- [ ] **Step 1: Implement the orchestrator**

```bash
#!/usr/bin/env bash
# run_sprint.sh — full single-sprint orchestrator (Plan 5).
#
# Phases:
#   0. Init sprint dir + seed contract via init_negotiation.sh.
#   A. Negotiation loop (Phase A): alternate generator + evaluator until AGREED or force-pivot.
#   B. Implementation: invoke Plan 3's run_generator.sh on the AGREED contract.
#   C. Grading (Phase B): invoke run_evaluator_phase_b.sh (which wraps Plan 4).
#
# Exit codes:
#   0 — sprint passed Phase B with verdict ∈ {PASS, PIVOT}
#   2 — Phase A force-pivot (no Phase B run)
#   3 — Plan 3 implementation failed
#   4 — Plan 4 grading failed
#
# Usage:
#   run_sprint.sh --run-id <id> --sprint <N> --goal-file <path> --touch-surface <path>
#                 [--max-rounds N] [--skip-eval-phase-b] [--dry-run]
set -euo pipefail

RUN_ID=""
SPRINT=""
GOAL_FILE=""
TOUCH_FILE=""
MAX_ROUNDS=5
SKIP_PHASE_B=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)            RUN_ID="$2"; shift 2 ;;
    --sprint)            SPRINT="$2"; shift 2 ;;
    --goal-file)         GOAL_FILE="$2"; shift 2 ;;
    --touch-surface)     TOUCH_FILE="$2"; shift 2 ;;
    --max-rounds)        MAX_ROUNDS="$2"; shift 2 ;;
    --skip-eval-phase-b) SKIP_PHASE_B=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)           grep '^# ' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$RUN_ID" && -n "$SPRINT" && -n "$GOAL_FILE" && -n "$TOUCH_FILE" ]] || \
  { echo "missing required arg; see --help" >&2; exit 64; }

if [[ "$DRY_RUN" -eq 1 ]]; then
  export EVALUATOR_LIVE=0
  export NEGOTIATION_LIVE=0
  export GENERATOR_LIVE=0
fi
# Live mode must be consistent.
: "${EVALUATOR_LIVE:=0}"
: "${NEGOTIATION_LIVE:=$EVALUATOR_LIVE}"
: "${GENERATOR_LIVE:=$EVALUATOR_LIVE}"
if [[ "$EVALUATOR_LIVE" != "$NEGOTIATION_LIVE" || "$EVALUATOR_LIVE" != "$GENERATOR_LIVE" ]]; then
  echo "EVALUATOR_LIVE/NEGOTIATION_LIVE/GENERATOR_LIVE must all match; got $EVALUATOR_LIVE/$NEGOTIATION_LIVE/$GENERATOR_LIVE" >&2
  exit 64
fi
export EVALUATOR_LIVE NEGOTIATION_LIVE GENERATOR_LIVE

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
SPRINT_DIR="harness/runs/${RUN_ID}/sprint_${SPRINT}"

echo "[run_sprint] phase 0 — init"
bash "$LIB_DIR/init_negotiation.sh" \
  --run-id "$RUN_ID" \
  --sprint "$SPRINT" \
  --goal-file "$GOAL_FILE" \
  --touch-surface "$TOUCH_FILE" \
  --max-rounds "$MAX_ROUNDS"

echo "[run_sprint] phase A — negotiation"
python3 - "$RUN_ID" "$SPRINT" "$LIB_DIR" <<'PY'
import sys, subprocess
from pathlib import Path
run_id, sprint, lib_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sys.path.insert(0, lib_dir)
from negotiation_loop import NegotiationLoop, NegotiationOutcome
from claude_agents import claude_generator_agent, claude_evaluator_agent  # ← Plan 5 wiring

sprint_dir = Path(f"harness/runs/{run_id}/sprint_{sprint}")
lock_path = Path(f"harness/.locks/contract_{run_id}_{sprint}.lock")

loop = NegotiationLoop(
    sprint_dir=sprint_dir,
    lock_path=lock_path,
    generator=claude_generator_agent(run_id=run_id, sprint=sprint),
    evaluator=claude_evaluator_agent(run_id=run_id, sprint=sprint),
)
result = loop.run()

audit_path = sprint_dir / "agreement.json"
import json
from negotiation_state import NegotiationState
state = NegotiationState.from_file(sprint_dir / "negotiation_state.json")
audit = state.audit_log()
audit["rejections"] = {"marker": result.marker_rejections, "schema": result.schema_rejections}
audit_path.write_text(json.dumps(audit, indent=2) + "\n")

if result.outcome == NegotiationOutcome.FORCE_PIVOT:
    pivot = sprint_dir / "force_pivot.json"
    pivot.write_text(json.dumps({
        "run_id": run_id, "sprint": sprint, "rounds_used": result.rounds_used,
        "reason": "phase_a_max_rounds_exceeded",
    }, indent=2) + "\n")
    print(f"[run_sprint] force-pivot after {result.rounds_used} rounds; see {pivot}", file=sys.stderr)
    sys.exit(2)

print(f"[run_sprint] agreed after {result.rounds_used} rounds")
PY
PHASE_A=$?
if [[ "$PHASE_A" -ne 0 ]]; then exit "$PHASE_A"; fi

echo "[run_sprint] phase B-impl — generator implements against AGREED contract"
GENERATOR_LIVE="$EVALUATOR_LIVE" ./harness/run_generator.sh \
  --run-id "$RUN_ID" \
  --sprint "$SPRINT" \
  --goal-file "$SPRINT_DIR/goal.md" \
  --touch-surface "$SPRINT_DIR/touch_surface.allow" \
  || { echo "[run_sprint] generator implementation failed" >&2; exit 3; }

if [[ "$SKIP_PHASE_B" -eq 1 ]]; then
  echo "[run_sprint] --skip-eval-phase-b set; stopping before grading"
  exit 0
fi

echo "[run_sprint] phase B-grade — evaluator grades implementation"
bash "$LIB_DIR/run_evaluator_phase_b.sh" --run-id "$RUN_ID" --sprint "$SPRINT" \
  || { echo "[run_sprint] grading failed" >&2; exit 4; }

VERDICT=$(python3 -c "import json; print(json.load(open('${SPRINT_DIR}/verdict.json'))['verdict'])")
echo "[run_sprint] verdict: $VERDICT"
```

A note on `claude_agents`: this is a small module that constructs the `TurnAgent` instances. It must exist for `run_sprint.sh` to work, but its actual claude wiring lives in Plan 4's `claude_subprocess.py` — Plan 5 just instantiates wrappers around `run_evaluator_agent.sh` and the existing `run_generator.sh`. Add it now:

- [ ] **Step 2: Implement `harness/lib/claude_agents.py`**

```python
"""Concrete TurnAgent implementations backed by harness bash wrappers."""
from __future__ import annotations
import subprocess
from dataclasses import dataclass
from pathlib import Path

from negotiation_state import Turn


@dataclass
class _ShellAgent:
    role: Turn
    script: str         # absolute path to the wrapper script
    run_id: str
    sprint: int

    def take_turn(self, sprint_dir: Path, round_number: int) -> None:
        subprocess.run(
            [
                "bash",
                self.script,
                "--run-id", self.run_id,
                "--sprint", str(self.sprint),
                "--round", str(round_number),
            ],
            check=True,
            cwd=Path.cwd(),
        )


def claude_generator_agent(*, run_id: str, sprint: int) -> _ShellAgent:
    # run_generator.sh from Plan 3 — must be invoked with --negotiate-only to
    # produce a contract turn rather than a full implementation cycle. (Plan 3
    # already supports this when status == NEGOTIATING; we pass --round so the
    # script knows it is in Phase A.)
    return _ShellAgent(
        role=Turn.GENERATOR,
        script=str(Path("harness/run_generator.sh").resolve()),
        run_id=run_id,
        sprint=sprint,
    )


def claude_evaluator_agent(*, run_id: str, sprint: int) -> _ShellAgent:
    return _ShellAgent(
        role=Turn.EVALUATOR,
        script=str(Path("harness/run_evaluator_agent.sh").resolve()),
        run_id=run_id,
        sprint=sprint,
    )
```

Note: this requires `run_generator.sh` to accept `--round` and behave correctly in negotiation-only mode. Plan 3's generator.md already covers the agent behavior (`if NEGOTIATING, propose minimal edits and STOP`); the script side needs a small flag-tolerance shim added in Task 14.

- [ ] **Step 3: Make scripts executable + parse-check**

```bash
chmod +x harness/run_sprint.sh
bash -n harness/run_sprint.sh
python3 -c "import sys; sys.path.insert(0, 'harness/lib'); import claude_agents"
```

Expected: all silent.

- [ ] **Step 4: Commit**

```bash
git add harness/run_sprint.sh harness/lib/claude_agents.py
git commit -m "feat(harness): run_sprint.sh orchestrator + claude_agents wiring"
```

---

## Task 14: run_generator.sh — accept --round + negotiation-only turn

Plan 3's `run_generator.sh` takes one sprint to completion. For Phase A, the orchestrator must invoke it as a single-turn "edit the contract and stop" callable. We add a `--round` flag: when present, the script spawns or resumes the generator session, prompts it with the per-round Phase A prompt, and exits after the agent's one turn. When absent (Plan 3's existing call path), behavior is unchanged.

**Files:**
- Modify: `harness/run_generator.sh`

- [ ] **Step 1: Read the current generator entry script to identify the safe insertion point**

```bash
grep -n '^# Usage:' harness/run_generator.sh
grep -n 'parse args' harness/run_generator.sh || grep -n 'while \[\[ \$#' harness/run_generator.sh
```

Locate the arg-parsing `while` block and the main `claude -p` invocation.

- [ ] **Step 2: Add `--round` arg-parser branch**

Inside the existing `while [[ $# -gt 0 ]]; do case "$1" in` block in `run_generator.sh`, add a new branch (use Edit, anchoring on a stable nearby case branch like `--sprint)`):

```bash
    --round) ROUND="$2"; shift 2 ;;
```

And after the parser block, before the main agent invocation, add:

```bash
ROUND="${ROUND:-}"
if [[ -n "$ROUND" ]]; then
  # Phase A negotiation turn: one round, no implementation work.
  CONTRACT_PATH="harness/runs/${RUN_ID}/sprint_${SPRINT}/contract.md"
  LOCK_PATH="harness/.locks/contract_${RUN_ID}_${SPRINT}.lock"
  STATUS=$(flock -x -w 10 "$LOCK_PATH" python3 - "$CONTRACT_PATH" "$(dirname "$0")/lib" <<'PY'
import sys; sys.path.insert(0, sys.argv[2])
from contract_schema import parse_contract
print(parse_contract(open(sys.argv[1]).read()).status)
PY
  )
  PHASE_A_USER_PROMPT="$(cat <<EOF
It is round ${ROUND} of Phase A negotiation for sprint ${SPRINT}.

The current contract is at \`${CONTRACT_PATH}\`. Its current status is \`${STATUS}\`.

If the contract still contains the literal token \`__REPLACE_ME__\`, you must replace every occurrence with a concrete value before doing anything else.

Read the contract, the sprint goal (\`harness/runs/${RUN_ID}/sprint_${SPRINT}/goal.md\`), and the rubric (\`docs/rubric/rubric.md\`). If the contract is gradable and matches the sprint's intent, write \`## Status: AGREED\` (and make no other edits). Otherwise edit it in place and write \`## Status: NEGOTIATING\`.

Stop after writing.
EOF
)"
  exec 9>"$LOCK_PATH"
  flock -x -w 60 9
  if [[ -f "$SESSION_FILE" ]]; then
    SESSION_ID="$(<"$SESSION_FILE")"
    python3 "$(dirname "$0")/lib/claude_subprocess.py" \
      --resume "$SESSION_ID" \
      --system-prompt-file "$(dirname "$0")/prompts/generator.md" \
      --user-prompt "$PHASE_A_USER_PROMPT" \
      --log-file "$LOG_FILE" \
      --working-dir "$PWD"
  else
    python3 "$(dirname "$0")/lib/claude_subprocess.py" \
      --fresh \
      --model "${CLAUDE_MODEL_GEN:-claude-sonnet-4-6}" \
      --system-prompt-file "$(dirname "$0")/prompts/generator.md" \
      --user-prompt "$PHASE_A_USER_PROMPT" \
      --session-id-out "$SESSION_FILE" \
      --log-file "$LOG_FILE" \
      --working-dir "$PWD"
  fi
  flock -u 9
  exec 9>&-
  exit 0
fi
```

(Variables `SESSION_FILE` and `LOG_FILE` are already set earlier in Plan 3's script body — verify by `grep -n 'SESSION_FILE=' harness/run_generator.sh`. If Plan 3 named them differently, rename to match the existing names before committing.)

- [ ] **Step 3: Verify the script still parses + the new path is reachable**

```bash
bash -n harness/run_generator.sh
# A dry-run with --round must exit 0 without invoking Plan 4's grading.
mkdir -p /tmp/run-sprint-smoke-1/harness/runs/test/sprint_1
cp harness/lib/contract_schema.py /tmp/run-sprint-smoke-1/harness/lib/  || true
# (full smoke covered in Task 15)
```

- [ ] **Step 4: Commit**

```bash
git add harness/run_generator.sh
git commit -m "feat(harness): run_generator.sh accepts --round for Phase A negotiation turn"
```

---

## Task 15: End-to-end smoke test

`smoke_negotiation.sh` exercises the full happy path under `EVALUATOR_LIVE=0`: stub both agents to produce a canned (NEGOTIATING → AGREED → AGREED) sequence, run `run_sprint.sh --dry-run`, assert terminal AGREED + `agreement.json` written + Phase B short-circuited. Mirrors `smoke_evaluator.sh` from Plan 4.

**Files:**
- Create: `harness/test/smoke_negotiation.sh`

- [ ] **Step 1: Implement the smoke**

```bash
#!/usr/bin/env bash
# smoke_negotiation.sh — end-to-end dry-run for Plan 5 Phase A.
#
# Stubs claude_subprocess.py to produce canned contract writes for both agents,
# then runs run_sprint.sh --dry-run and asserts agreement.json is correct.
set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

REPO="$PWD"
cp -R "$REPO/harness" "$WORKDIR/"
cp -R "$REPO/docs"    "$WORKDIR/"
cd "$WORKDIR"

mkdir -p sprint_inputs
cat > sprint_inputs/goal.md <<'EOF'
# Sprint 1 — Decision density

Make day-1 decisions diverge across optimizer vs neglect strategies.
EOF
cat > sprint_inputs/touch.allow <<'EOF'
features/economy/
features/case_file/
test/harness/
EOF

# Stub claude_subprocess.py: produce a pre-programmed contract per call.
STUB_DIR="harness/test/stubs"
mkdir -p "$STUB_DIR"
cat > harness/lib/claude_subprocess.py <<'PY'
"""SMOKE STUB — overrides Plan 4's claude_subprocess.py inside the smoke workdir."""
import argparse, sys, json, os, time
from pathlib import Path

ROUND_FILE = os.environ.get("SMOKE_ROUND_FILE", "/tmp/smoke_round_count")
SCRIPTED = [
    # round 1: generator writes a valid NEGOTIATING contract.
    """# Sprint 1 — Decision density\n\n## Done means\n- [test] `test/harness/s1.gd::test_x` passes\n- [trace] events where ev=diagnostic_completed count >= 1\n\n## Status: NEGOTIATING\n""",
    # round 2: evaluator agrees (unchanged).
    """# Sprint 1 — Decision density\n\n## Done means\n- [test] `test/harness/s1.gd::test_x` passes\n- [trace] events where ev=diagnostic_completed count >= 1\n\n## Status: AGREED\n""",
    # round 3: generator confirms (unchanged).
    """# Sprint 1 — Decision density\n\n## Done means\n- [test] `test/harness/s1.gd::test_x` passes\n- [trace] events where ev=diagnostic_completed count >= 1\n\n## Status: AGREED\n""",
]

def next_round():
    try:
        n = int(Path(ROUND_FILE).read_text())
    except Exception:
        n = 0
    Path(ROUND_FILE).write_text(str(n + 1))
    return n

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--resume")
    ap.add_argument("--model")
    ap.add_argument("--system-prompt-file")
    ap.add_argument("--user-prompt")
    ap.add_argument("--session-id-out")
    ap.add_argument("--log-file")
    ap.add_argument("--working-dir")
    args, _ = ap.parse_known_args()
    n = next_round()
    if n >= len(SCRIPTED):
        print(f"smoke stub exhausted at round {n}", file=sys.stderr)
        sys.exit(70)
    # Find the contract path mentioned in the user prompt.
    import re
    m = re.search(r"`([^`]*contract\.md)`", args.user_prompt or "")
    if not m:
        print("could not locate contract.md path in user prompt", file=sys.stderr)
        sys.exit(70)
    Path(m.group(1)).write_text(SCRIPTED[n])
    if args.session_id_out:
        Path(args.session_id_out).write_text(f"smoke-session-{n}")
    if args.log_file:
        Path(args.log_file).parent.mkdir(parents=True, exist_ok=True)
        Path(args.log_file).write_text(f"smoke round {n}\n")
    return 0

if __name__ == "__main__":
    sys.exit(main() or 0)
PY

# Also stub run_evaluator_phase_b.sh so we don't actually run Plan 4 grading.
cat > harness/lib/run_evaluator_phase_b.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
echo "[smoke] skipping phase B grading"
exit 0
BASH
chmod +x harness/lib/run_evaluator_phase_b.sh

# Run.
rm -f /tmp/smoke_round_count
RUN_ID="smoke-$(date +%s)"
./harness/run_sprint.sh \
  --run-id "$RUN_ID" \
  --sprint 1 \
  --goal-file sprint_inputs/goal.md \
  --touch-surface sprint_inputs/touch.allow \
  --skip-eval-phase-b \
  --dry-run

SPRINT_DIR="harness/runs/${RUN_ID}/sprint_1"
test -f "$SPRINT_DIR/contract.md"          || { echo "[smoke] contract.md missing" >&2; exit 1; }
test -f "$SPRINT_DIR/negotiation_state.json" || { echo "[smoke] state missing" >&2; exit 1; }
test -f "$SPRINT_DIR/agreement.json"       || { echo "[smoke] agreement.json missing" >&2; exit 1; }
grep -q '^## Status: AGREED$' "$SPRINT_DIR/contract.md" || { echo "[smoke] not agreed" >&2; exit 1; }
python3 -c "
import json
a = json.load(open('$SPRINT_DIR/agreement.json'))
assert a['terminal_status'] == 'AGREED', a
assert a['rounds_used'] == 3, a
"
echo "[smoke] OK"
```

- [ ] **Step 2: Make it executable + run it**

```bash
chmod +x harness/test/smoke_negotiation.sh
./harness/test/smoke_negotiation.sh
```

Expected: `[smoke] OK` — script exits 0.

- [ ] **Step 3: Commit**

```bash
git add harness/test/smoke_negotiation.sh
git commit -m "test(harness): smoke_negotiation.sh end-to-end dry-run"
```

---

## Task 16: README final flip + plan-done marker

**Files:**
- Modify: `harness/README.md`

- [ ] **Step 1: Flip Plan 5 status to done + add quick-start section**

In `harness/README.md` change:

```markdown
| 5 | Evaluator agent + Phase A negotiation | 🚧 in progress |
```

to:

```markdown
| 5 | Evaluator agent + Phase A negotiation | ✅ done |
```

Then append a new section before the "What's NOT in Plan 1" line:

```markdown
## What's in Plan 5

- `run_sprint.sh` — full single-sprint orchestrator (Phase A → implementation → Phase B)
- `run_evaluator_agent.sh` — long-lived Opus evaluator session driver
- `prompts/evaluator.md` — Opus harshness-tuned system prompt (Mode A + Mode B)
- `lib/{negotiation_state,negotiation_loop,contract_lock,contract_hash,contract_template,pre_grade_calibration,claude_agents,init_negotiation,run_evaluator_phase_b}.{py,sh}` — coordination layer
- `test/smoke_negotiation.sh` — end-to-end dry-run
- `prompts/generator.md` — augmented with Phase A round-aware directives

The negotiation protocol: generator drafts → evaluator critiques + edits → repeat until both write `## Status: AGREED` consecutively with no contract changes on the confirming turn, OR round counter exceeds 5 (force-pivot).

### Quick start (real sprint run)

```bash
# Requires `claude` in PATH, ANTHROPIC_API_KEY set, Plan 4's run_evaluator.sh available.
EVALUATOR_LIVE=1 ./harness/run_sprint.sh \
  --run-id $(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 3) \
  --sprint 1 \
  --goal-file path/to/sprint_goal.md \
  --touch-surface path/to/sprint_touch.allow
```

### Quick start (dry-run smoke)

```bash
./harness/test/smoke_negotiation.sh
```

### Known limitations (Plan 6 follow-up)

- No planner agent yet: `run_sprint.sh` requires an operator-authored `goal.md` and `touch_surface.allow`. Plan 6 will produce these from a higher-level user prompt.
- No multi-sprint orchestration. `run_sprint.sh` runs one sprint per invocation.
- No `report.html`. Plan 7 renders the artifacts in `harness/runs/<run-id>/` into a single-file viewer.
```

- [ ] **Step 2: Commit**

```bash
git add harness/README.md
git commit -m "docs(harness): mark Plan 5 done + quick-start + protocol summary"
```

---

## Self-Review (checklist applied after Task 16)

**Spec coverage (against `2026-05-20-adversarial-harness-design.md` §4.5 + §5.2 + §6.2):**

- §4.5 Phase A — Contract negotiation, 5 steps → Task 10 negotiation loop + Task 11 evaluator wrapper + Task 14 generator wrapper.
- §4.5 calibration check pre-grading → Task 8 + Task 12 wiring through to Plan 4.
- §5.2 Sentinels + mutex (flock on contract.md, contract.agreed sentinel as `## Status: AGREED` in-file, ready sentinel from Plan 3) → Task 3 contract_lock + Task 2 terminal detection.
- §6.2 negotiation errors:
  - "5 rounds, no AGREED → force pivot" → Task 2 + Task 10 + Task 13.
  - "Both write AGREED w/ contradictory contracts" → not directly possible with the file-mutex single-writer-at-a-time protocol; replaced with "AGREED-with-edits resets to NEGOTIATING" in Task 2 + Task 10.
  - "Contract has only `judge` items → reject" → Plan 3's `contract_schema.py` already enforces ≥50% test/trace; Task 10 re-uses it on every turn.
- §6.4 sycophancy regression (baseline all-3/3) → Task 8 `compare_scorecards` flags it as out-of-tolerance.

**Placeholder scan:** No "TBD", "TODO", "implement later", or "similar to Task N" placeholders. All code blocks are complete. All file paths are absolute or repo-rooted.

**Type consistency:** `Turn`, `NegotiationState`, `TurnRecord`, `TurnAgent`, `NegotiationOutcome`, `NegotiationResult`, `ContractItem`, `Contract`, `DriftReport`, `AxisDelta` — all defined in Task 2 / Task 8 / Plan 3's `contract_schema.py` and referenced consistently across Tasks 10 / 13 / 16. The `_ShellAgent` dataclass in `claude_agents.py` (Task 13) implements the `TurnAgent` Protocol from Task 10. Script flags `--round`, `--run-id`, `--sprint`, `--goal-file`, `--touch-surface`, `--max-rounds`, `--skip-eval-phase-b`, `--dry-run` are spelled identically across Tasks 9 / 11 / 12 / 13 / 14.

**Reuse audit:** `contract_schema.py` (Plan 3) re-used by Tasks 4, 5, 10, 14. `claude_subprocess.py` (Plan 4) re-used by Tasks 11 + 14. `run_evaluator.sh` (Plan 4) re-used by Task 12. `run_generator.sh` (Plan 3) extended in Task 14, re-used by Task 13. No duplication.

**Out of scope confirmed:** Planner agent, multi-sprint orchestrator, report.html — explicitly deferred to Plan 6 / Plan 7 in both this plan's header and the README appendix.
